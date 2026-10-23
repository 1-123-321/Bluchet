-- Kulcskód schema. Apply with `supabase db push` or SQL editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_]{3,24}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  is_direct boolean not null default true check (is_direct),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.conversation_participants (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  client_message_id uuid not null,
  ciphertext text not null check (length(ciphertext) between 1 and 200000),
  -- Header contains only routing/protocol metadata; never plaintext message text.
  protocol_version text not null default 'signal-v1',
  created_at timestamptz not null default now(),
  delivery_status text not null default 'sent' check (delivery_status in ('sent','delivered','read')),
  unique (sender_id, client_message_id)
);
create index if not exists messages_conversation_created_idx on public.messages(conversation_id, created_at);

create table if not exists public.device_keys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id text not null,
  identity_key text not null,
  signed_prekey text not null,
  signed_prekey_signature text not null,
  one_time_prekeys jsonb not null default '[]'::jsonb,
  kyber_prekey text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, device_id)
);

create table if not exists public.user_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists public.abuse_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (length(reason) between 3 and 1000),
  created_at timestamptz not null default now(),
  check (reporter_id <> reported_user_id)
);

-- Create a profile after signup. Username comes from auth metadata and uniqueness
-- is enforced by PostgreSQL, not trusted to the client.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare candidate text;
begin
  candidate := lower(coalesce(new.raw_user_meta_data ->> 'username', 'user_' || substr(new.id::text, 1, 8)));
  if candidate !~ '^[a-z0-9_]{3,24}$' then candidate := 'user_' || substr(new.id::text, 1, 8); end if;
  insert into public.profiles(id, username) values (new.id, candidate);
  return new;
exception when unique_violation then
  raise exception 'Username is already taken';
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.search_profiles(search_term text)
returns table(id uuid, username text)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.username from public.profiles p
  where p.id <> auth.uid() and p.username like left(lower(search_term), 24) || '%'
    and length(search_term) >= 2
    and not exists (select 1 from public.user_blocks b where
      (b.blocker_id = auth.uid() and b.blocked_id = p.id) or (b.blocker_id = p.id and b.blocked_id = auth.uid()))
  order by p.username limit 30;
$$;

create or replace function public.get_or_create_direct_conversation(other_user uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); found_id uuid;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if other_user = me then raise exception 'Cannot start a conversation with yourself'; end if;
  if not exists(select 1 from public.profiles where id = other_user) then raise exception 'User not found'; end if;
  if exists(select 1 from public.user_blocks where (blocker_id=me and blocked_id=other_user) or (blocker_id=other_user and blocked_id=me)) then raise exception 'Conversation unavailable'; end if;
  select cp1.conversation_id into found_id
  from public.conversation_participants cp1
  join public.conversation_participants cp2 on cp1.conversation_id=cp2.conversation_id
  join public.conversations c on c.id=cp1.conversation_id and c.is_direct
  where cp1.user_id=me and cp2.user_id=other_user
    and (select count(*) from public.conversation_participants x where x.conversation_id=cp1.conversation_id)=2
  limit 1;
  if found_id is not null then return found_id; end if;
  insert into public.conversations default values returning id into found_id;
  insert into public.conversation_participants(conversation_id,user_id) values (found_id,me),(found_id,other_user);
  return found_id;
end; $$;

create or replace function public.is_conversation_member(cid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.conversation_participants cp where cp.conversation_id=cid and cp.user_id=auth.uid());
$$;

alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;
alter table public.device_keys enable row level security;
alter table public.user_blocks enable row level security;
alter table public.abuse_reports enable row level security;

create policy "profiles readable to signed in users" on public.profiles for select to authenticated using (true);
create policy "users update own profile" on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());
create policy "members read conversations" on public.conversations for select to authenticated using (public.is_conversation_member(id));
create policy "members read participants" on public.conversation_participants for select to authenticated using (public.is_conversation_member(conversation_id));
create policy "members read messages" on public.messages for select to authenticated using (public.is_conversation_member(conversation_id));
create policy "members send own ciphertext" on public.messages for insert to authenticated with check (sender_id=auth.uid() and public.is_conversation_member(conversation_id));
create policy "participants update delivery state" on public.messages for update to authenticated using (public.is_conversation_member(conversation_id)) with check (public.is_conversation_member(conversation_id));
create policy "users read own device keys" on public.device_keys for select to authenticated using (user_id=auth.uid());
create policy "users publish own device keys" on public.device_keys for insert to authenticated with check (user_id=auth.uid());
create policy "users update own device keys" on public.device_keys for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "users delete own device keys" on public.device_keys for delete to authenticated using (user_id=auth.uid());
-- Public keys are fetched via this restricted RPC so callers cannot list all key material.
create or replace function public.get_device_bundles(target_user uuid)
returns table(device_id text, identity_key text, signed_prekey text, signed_prekey_signature text, one_time_prekey jsonb, kyber_prekey text)
language sql stable security definer set search_path = '' as $$
 select k.device_id,k.identity_key,k.signed_prekey,k.signed_prekey_signature,
   (select value from jsonb_array_elements(k.one_time_prekeys) value limit 1),k.kyber_prekey
 from public.device_keys k where k.user_id=target_user and auth.uid() is not null
 and not exists(select 1 from public.user_blocks b where (b.blocker_id=auth.uid() and b.blocked_id=target_user) or (b.blocker_id=target_user and b.blocked_id=auth.uid()));
$$;
create policy "users manage own blocks" on public.user_blocks for all to authenticated using (blocker_id=auth.uid()) with check (blocker_id=auth.uid());
create policy "users create reports" on public.abuse_reports for insert to authenticated with check (reporter_id=auth.uid());
create policy "reporters view own reports" on public.abuse_reports for select to authenticated using (reporter_id=auth.uid());

grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.conversations, public.conversation_participants to authenticated;
grant select, insert on public.messages to authenticated;
grant update (delivery_status) on public.messages to authenticated;
grant select, insert, update, delete on public.device_keys to authenticated;
grant select, insert, delete on public.user_blocks to authenticated;
grant select, insert on public.abuse_reports to authenticated;
grant execute on function public.search_profiles(text) to authenticated;
grant execute on function public.get_or_create_direct_conversation(uuid) to authenticated;
grant execute on function public.get_device_bundles(uuid) to authenticated;

-- Enable Realtime delivery of ciphertext only.
alter publication supabase_realtime add table public.messages;
