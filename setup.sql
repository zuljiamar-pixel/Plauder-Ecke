/* Plauderecke: Datenbank einrichten */
/* Einmal im Supabase "SQL Editor" einfügen und auf "Run" tippen. */
/* Das Skript darf auch mehrmals laufen, es macht dann nichts kaputt. */

/* ---------- Tabellen ---------- */

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  invite_code text not null unique default substr(replace(gen_random_uuid()::text, '-', ''), 1, 12),
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null default auth.uid(),
  name text not null check (char_length(name) between 1 and 30),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null default auth.uid(),
  kind text not null default 'text' check (kind in ('text', 'image', 'video', 'audio')),
  text text not null default '' check (char_length(text) <= 2000),
  media jsonb,
  created_at timestamptz not null default now()
);

create index if not exists messages_group_time on public.messages (group_id, created_at desc);

alter table public.groups enable row level security;
alter table public.members enable row level security;
alter table public.messages enable row level security;

/* ---------- Wer darf was ---------- */

/* Ist die angemeldete Person in dieser Gruppe? (security definer, damit sich die Regeln nicht im Kreis drehen) */
create or replace function public.is_member(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.members where group_id = g and user_id = auth.uid());
$$;
grant execute on function public.is_member(uuid) to authenticated;

drop policy if exists "groups: members read" on public.groups;
create policy "groups: members read" on public.groups
  for select to authenticated using (public.is_member(id));

drop policy if exists "members: group mates read" on public.members;
create policy "members: group mates read" on public.members
  for select to authenticated using (public.is_member(group_id));

drop policy if exists "members: change own name" on public.members;
create policy "members: change own name" on public.members
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "members: leave" on public.members;
create policy "members: leave" on public.members
  for delete to authenticated using (user_id = auth.uid());

/* Beim eigenen Eintrag darf nur der Name geändert werden, nicht die Gruppe */
revoke update on public.members from anon, authenticated;
grant update (name) on public.members to authenticated;

drop policy if exists "messages: members read" on public.messages;
create policy "messages: members read" on public.messages
  for select to authenticated using (public.is_member(group_id));

drop policy if exists "messages: members write" on public.messages;
create policy "messages: members write" on public.messages
  for insert to authenticated with check (user_id = auth.uid() and public.is_member(group_id));

drop policy if exists "messages: delete own" on public.messages;
create policy "messages: delete own" on public.messages
  for delete to authenticated using (user_id = auth.uid());

/* ---------- Gruppe erstellen und mit Einladungscode beitreten ---------- */

create or replace function public.create_group(group_name text, my_name text) returns public.groups
language plpgsql security definer set search_path = public as $$
declare g public.groups;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into public.groups (name, created_by) values (trim(group_name), auth.uid()) returning * into g;
  insert into public.members (group_id, user_id, name) values (g.id, auth.uid(), trim(my_name));
  return g;
end $$;

create or replace function public.join_group(code text, my_name text) returns public.groups
language plpgsql security definer set search_path = public as $$
declare g public.groups;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into g from public.groups where invite_code = trim(code);
  if not found then raise exception 'invite code not found' using errcode = 'P0002'; end if;
  insert into public.members (group_id, user_id, name) values (g.id, auth.uid(), trim(my_name))
    on conflict (group_id, user_id) do nothing;
  return g;
end $$;

revoke execute on function public.create_group(text, text) from public, anon;
revoke execute on function public.join_group(text, text) from public, anon;
grant execute on function public.create_group(text, text) to authenticated;
grant execute on function public.join_group(text, text) to authenticated;

/* ---------- Live-Updates ---------- */

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'members') then
    alter publication supabase_realtime add table public.members;
  end if;
end $$;

/* ---------- Speicher für Fotos, Videos und Sprachnachrichten ---------- */
/* Dateien liegen unter zufälligen Namen; hochladen dürfen nur Mitglieder der jeweiligen Gruppe. */

insert into storage.buckets (id, name, public, file_size_limit)
values ('media', 'media', true, 52428800)
on conflict (id) do update set public = true, file_size_limit = 52428800;

drop policy if exists "media: members upload" on storage.objects;
create policy "media: members upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'media' and public.is_member(((storage.foldername(name))[1])::uuid));

drop policy if exists "media: see own" on storage.objects;
create policy "media: see own" on storage.objects
  for select to authenticated using (bucket_id = 'media' and owner_id = (auth.uid())::text);

drop policy if exists "media: delete own" on storage.objects;
create policy "media: delete own" on storage.objects
  for delete to authenticated using (bucket_id = 'media' and owner_id = (auth.uid())::text);

/* Kontrolle: hier sollte jetzt eine Zeile mit 3 Tabellen und dem Speicher stehen */
select 'Plauderecke ist eingerichtet' as status,
  (select count(*) from pg_tables where schemaname = 'public' and tablename in ('groups', 'members', 'messages')) as tabellen,
  (select count(*) from storage.buckets where id = 'media') as speicher;
