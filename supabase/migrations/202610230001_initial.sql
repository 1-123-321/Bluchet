-- Custom username/password backend for email-disabled Supabase projects.
-- This adds a minimal server-side auth layer and message/conversation helpers
-- without relying on Supabase Email Auth.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  email text,
  email_verified boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.user_credentials (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  username text not null unique,
  password_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table if not exists public.conversation_participants (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null,
  primary key (conversation_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null,
  ciphertext text not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;

create or replace function public.normalize_username(value text)
returns text
language sql stable as $$
  select lower(regexp_replace(trim(value), '\s+', '_', 'g'));
$$;

create or replace function public.register_user(p_username text, p_password text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  normalized text;
  user_id uuid;
begin
  normalized := public.normalize_username(p_username);

  if normalized !~ '^[a-z0-9_]{3,24}$' then
    raise exception 'Invalid username';
  end if;

  if length(trim(p_password)) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;

  if exists(select 1 from public.profiles where username = normalized) then
    raise exception 'Username already taken';
  end if;

  user_id := gen_random_uuid();

  insert into public.profiles(id, username)
  values (user_id, normalized);

  insert into public.user_credentials(user_id, username, password_hash)
  values (user_id, normalized, crypt(p_password, gen_salt('bf')));

  return user_id;
exception when unique_violation then
  raise exception 'Username already taken';
end;
$$;

create or replace function public.login_user(p_username text, p_password text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  normalized text;
  result_id uuid;
begin
  normalized := public.normalize_username(p_username);

  select uc.user_id into result_id
  from public.user_credentials uc
  where uc.username = normalized
    and crypt(p_password, uc.password_hash) = uc.password_hash;

  if result_id is null then
    raise exception 'Invalid username or password';
  end if;

  return result_id;
end;
$$;

create or replace function public.is_conversation_member_for_user(cid uuid, user_id uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = cid
      and cp.user_id = user_id
  );
$$;

create or replace function public.get_or_create_direct_conversation_for_user(actor_id uuid, other_user uuid)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  found_id uuid;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  if other_user = actor_id then
    raise exception 'Cannot start a conversation with yourself';
  end if;

  if not exists(select 1 from public.profiles where id = actor_id) then
    raise exception 'User not found';
  end if;

  if not exists(select 1 from public.profiles where id = other_user) then
    raise exception 'User not found';
  end if;

  select cp1.conversation_id into found_id
  from public.conversation_participants cp1
  join public.conversation_participants cp2
    on cp1.conversation_id = cp2.conversation_id
  where cp1.user_id = actor_id
    and cp2.user_id = other_user
  group by cp1.conversation_id
  having count(*) = 2
  limit 1;

  if found_id is not null then
    return found_id;
  end if;

  insert into public.conversations default values
  returning id into found_id;

  insert into public.conversation_participants(conversation_id, user_id)
  values (found_id, actor_id), (found_id, other_user);

  return found_id;
end;
$$;

create or replace function public.insert_message_for_user(actor_id uuid, conversation_id uuid, ciphertext text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  msg_id uuid;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  if not public.is_conversation_member_for_user(conversation_id, actor_id) then
    raise exception 'Not a member of this conversation';
  end if;

  if length(trim(ciphertext)) < 1 or length(ciphertext) > 200000 then
    raise exception 'Invalid message length';
  end if;

  insert into public.messages(id, conversation_id, sender_id, ciphertext)
  values (gen_random_uuid(), conversation_id, actor_id, ciphertext)
  returning id into msg_id;

  return msg_id;
end;
$$;

create policy if not exists "profiles_select_all"
on public.profiles
for select
using (true);

create policy if not exists "profiles_insert_own"
on public.profiles
for insert
with check (auth.uid() = id);

create policy if not exists "profiles_update_own"
on public.profiles
for update
using (auth.uid() = id)
with check (auth.uid() = id);

create policy if not exists "conversations_select_own"
on public.conversations
for select
using (
  exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = public.conversations.id
      and cp.user_id = auth.uid()
  )
);

create policy if not exists "conversations_insert_any"
on public.conversations
for insert
with check (true);

create policy if not exists "conversation_participants_select_own"
on public.conversation_participants
for select
using (user_id = auth.uid());

create policy if not exists "conversation_participants_insert_own"
on public.conversation_participants
for insert
with check (user_id = auth.uid());

create policy if not exists "messages_select_own"
on public.messages
for select
using (
  exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = public.messages.conversation_id
      and cp.user_id = auth.uid()
  )
);

create policy if not exists "messages_insert_own"
on public.messages
for insert
with check (
  sender_id = auth.uid()
  and exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = public.messages.conversation_id
      and cp.user_id = auth.uid()
  )
);

grant usage on schema public to anon, authenticated;
grant select, insert, update on public.profiles to anon, authenticated;
grant select, insert, update on public.conversations to anon, authenticated;
grant select, insert, update on public.conversation_participants to anon, authenticated;
grant select, insert, update on public.messages to anon, authenticated;
grant execute on function public.normalize_username(text) to anon, authenticated;
grant execute on function public.register_user(text, text) to anon, authenticated;
grant execute on function public.login_user(text, text) to anon, authenticated;
grant execute on function public.get_or_create_direct_conversation_for_user(uuid, uuid) to anon, authenticated;
grant execute on function public.insert_message_for_user(uuid, uuid, text) to anon, authenticated;
