-- Custom username/password backend for email-disabled Supabase projects.
-- This adds a minimal server-side auth layer and message/conversation helpers
-- without relying on Supabase Email Auth.

create table if not exists public.user_credentials (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  username text not null unique,
  password_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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
  join public.conversation_participants cp2 on cp1.conversation_id = cp2.conversation_id
  join public.conversations c on c.id = cp1.conversation_id and c.is_direct
  where cp1.user_id = actor_id
    and cp2.user_id = other_user
    and (select count(*) from public.conversation_participants x where x.conversation_id = cp1.conversation_id) = 2
  limit 1;

  if found_id is not null then
    return found_id;
  end if;

  insert into public.conversations default values returning id into found_id;
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

  insert into public.messages(id, conversation_id, sender_id, client_message_id, ciphertext, protocol_version, delivery_status)
  values (gen_random_uuid(), conversation_id, actor_id, gen_random_uuid(), ciphertext, 'signal-v1', 'sent')
  returning id into msg_id;

  return msg_id;
end;
$$;

create policy "profiles readable to anon" on public.profiles for select to anon using (true);
create policy "profiles readable to authenticated" on public.profiles for select to authenticated using (true);

create policy "profiles readable to anon" on public.profiles for select to public using (true);

grants for frontend demo access:
grant select on public.profiles to anon;
grant select on public.profiles to authenticated;
grant select on public.conversations to anon;
grant select on public.conversation_participants to anon;
grant select, insert on public.messages to anon;
grant update (delivery_status) on public.messages to anon;
grant execute on function public.normalize_username(text) to anon;
grant execute on function public.register_user(text, text) to anon;
grant execute on function public.login_user(text, text) to anon;
grant execute on function public.get_or_create_direct_conversation_for_user(uuid, uuid) to anon;
grant execute on function public.insert_message_for_user(uuid, uuid, text) to anon;

-- keep realtime publication if it exists
alter publication supabase_realtime add table public.messages;
