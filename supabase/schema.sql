create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  email text,
  email_verified boolean not null default false,
  created_at timestamptz not null default now()
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

create policy "profiles_select_all"
on public.profiles
for select
using (true);

create policy "profiles_insert_own"
on public.profiles
for insert
with check (auth.uid() = id);

create policy "profiles_update_own"
on public.profiles
for update
using (auth.uid() = id)
with check (auth.uid() = id);

create policy "conversations_select_own"
on public.conversations
for select
using (
  exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = id
      and cp.user_id = auth.uid()
  )
);

create policy "conversations_insert_any"
on public.conversations
for insert
with check (true);

create policy "conversation_participants_select_own"
on public.conversation_participants
for select
using (user_id = auth.uid());

create policy "conversation_participants_insert_own"
on public.conversation_participants
for insert
with check (user_id = auth.uid());

create policy "messages_select_own"
on public.messages
for select
using (
  exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = messages.conversation_id
      and cp.user_id = auth.uid()
  )
);

create policy "messages_insert_own"
on public.messages
for insert
with check (
  sender_id = auth.uid()
  and exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = messages.conversation_id
      and cp.user_id = auth.uid()
  )
);

grant usage on schema public to anon, authenticated;
grant select, insert, update on public.profiles to anon, authenticated;
grant select, insert, update on public.conversations to anon, authenticated;
grant select, insert, update on public.conversation_participants to anon, authenticated;
grant select, insert, update on public.messages to anon, authenticated;

create or replace function public.get_or_create_direct_conversation(other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user uuid := auth.uid();
  existing_id uuid;
  new_id uuid;
begin
  if current_user is null or other_user is null then
    raise exception 'Bejelentkezett felhasználó szükséges.';
  end if;

  if current_user = other_user then
    raise exception 'Nem kezdhetsz chatet saját magaddal.';
  end if;

  select cp.conversation_id
  into existing_id
  from public.conversation_participants cp
  where cp.user_id = current_user
    and cp.conversation_id in (
      select cp2.conversation_id
      from public.conversation_participants cp2
      where cp2.user_id = other_user
    )
  limit 1;

  if existing_id is not null then
    return existing_id;
  end if;

  insert into public.conversations default values
  returning id into new_id;

  insert into public.conversation_participants (conversation_id, user_id)
  values
    (new_id, current_user),
    (new_id, other_user);

  return new_id;
end;
$$;

grant execute on function public.get_or_create_direct_conversation(uuid) to authenticated, anon;
