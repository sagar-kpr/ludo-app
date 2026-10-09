create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  avatar_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.guest_sessions (
  id uuid primary key default gen_random_uuid(),
  guest_token_hash text not null unique,
  display_name text not null check (char_length(display_name) between 1 and 40),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days'
);

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9]{4,8}(-[A-Z0-9]{2,8})?$'),
  host_user_id uuid references public.profiles(id),
  host_guest_session_id uuid references public.guest_sessions(id),
  status text not null default 'lobby' check (status in ('lobby', 'playing', 'finished', 'expired')),
  capacity integer not null default 4 check (capacity between 2 and 4),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  check (host_user_id is not null or host_guest_session_id is not null)
);

create table if not exists public.room_members (
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid references public.profiles(id),
  guest_session_id uuid references public.guest_sessions(id),
  display_name text not null check (char_length(display_name) between 1 and 40),
  color text not null check (color in ('coral', 'sun', 'mint', 'violet')),
  ready boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (room_id, display_name),
  check (user_id is not null or guest_session_id is not null)
);

create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null unique references public.rooms(id) on delete cascade,
  rules_version text not null default 'standard-v1',
  state jsonb not null,
  version bigint not null default 0,
  winner_id text,
  updated_at timestamptz not null default now()
);

create table if not exists public.match_events (
  id bigint generated always as identity primary key,
  match_id uuid not null references public.matches(id) on delete cascade,
  version bigint not null,
  event_type text not null,
  actor_id text not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  unique (match_id, version)
);

create table if not exists public.chat_messages (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  sender_id text not null,
  sender_name text not null,
  body text not null check (char_length(body) between 1 and 240),
  created_at timestamptz not null default now()
);

create index if not exists room_members_room_idx on public.room_members(room_id);
create index if not exists match_events_match_version_idx on public.match_events(match_id, version);
create index if not exists chat_messages_room_created_idx on public.chat_messages(room_id, created_at);

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.matches enable row level security;
alter table public.chat_messages enable row level security;

drop policy if exists "profiles are readable" on public.profiles;
drop policy if exists "users manage own profile" on public.profiles;
drop policy if exists "room members can read rooms" on public.rooms;
drop policy if exists "room members can read members" on public.room_members;
drop policy if exists "room members can read matches" on public.matches;
drop policy if exists "room members can read chat" on public.chat_messages;

create policy "profiles are readable" on public.profiles for select using (true);
create policy "users manage own profile" on public.profiles for all using (auth.uid() = id) with check (auth.uid() = id);
create policy "room members can read rooms" on public.rooms for select using (
  exists (select 1 from public.room_members m where m.room_id = rooms.id and m.user_id = auth.uid())
);
create policy "room members can read members" on public.room_members for select using (
  exists (select 1 from public.room_members own where own.room_id = room_members.room_id and own.user_id = auth.uid())
);
create policy "room members can read matches" on public.matches for select using (
  exists (select 1 from public.room_members m where m.room_id = matches.room_id and m.user_id = auth.uid())
);
create policy "room members can read chat" on public.chat_messages for select using (
  exists (select 1 from public.room_members m where m.room_id = chat_messages.room_id and m.user_id = auth.uid())
);
