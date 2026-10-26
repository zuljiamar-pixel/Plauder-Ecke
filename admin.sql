/* Plauderecke: Admin (Ersteller) einrichten */
/* Einmal im Supabase "SQL Editor" ausführen. Unten erscheint dein persönlicher Admin-Link. Den nur selbst öffnen und nie weitergeben! */

/* Das Geheimnis hinter dem Admin-Link. Keine Regel gibt es frei, nur die Datenbank selbst kennt es. */
create table if not exists public.admin_config (
  id int primary key default 1 check (id = 1),
  secret text not null default substr(replace(gen_random_uuid()::text, '-', ''), 1, 20)
);
alter table public.admin_config enable row level security;
revoke all on public.admin_config from anon, authenticated;
insert into public.admin_config (id) values (1) on conflict (id) do nothing;

/* Wer Admin ist. Alle dürfen es sehen (für die Krone), niemand kann sich selbst eintragen. */
create table if not exists public.admins (
  user_id uuid primary key,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
revoke insert, update, delete on public.admins from anon, authenticated;
drop policy if exists "admins: visible to everyone" on public.admins;
create policy "admins: visible to everyone" on public.admins
  for select to authenticated using (true);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;
grant execute on function public.is_admin() to authenticated;

/* Admin-Link öffnen: wer das richtige Geheimnis mitbringt, wird Admin */
create or replace function public.claim_admin(code text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from public.admin_config where secret = trim(code)) then raise exception 'wrong admin code'; end if;
  insert into public.admins (user_id) values (auth.uid()) on conflict (user_id) do nothing;
  return true;
end $$;
revoke execute on function public.claim_admin(text) from public, anon;
grant execute on function public.claim_admin(text) to authenticated;

/* Neuer Einladungslink für eine Gruppe, der alte geht danach nicht mehr */
create or replace function public.new_invite_code(g uuid) returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public.is_admin() then raise exception 'only admins'; end if;
  update public.groups set invite_code = substr(replace(gen_random_uuid()::text, '-', ''), 1, 12) where id = g returning invite_code into c;
  return c;
end $$;
revoke execute on function public.new_invite_code(uuid) from public, anon;
grant execute on function public.new_invite_code(uuid) to authenticated;

/* Admins dürfen Leute entfernen, jede Nachricht löschen und Gruppen löschen */
drop policy if exists "members: leave or removed by admin" on public.members;
create policy "members: leave or removed by admin" on public.members
  for delete to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists "messages: delete own or admin" on public.messages;
create policy "messages: delete own or admin" on public.messages
  for delete to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists "groups: admin deletes" on public.groups;
create policy "groups: admin deletes" on public.groups
  for delete to authenticated using (public.is_admin());

drop policy if exists "media: see own" on storage.objects;
create policy "media: see own" on storage.objects
  for select to authenticated using (bucket_id = 'media' and (owner_id = (auth.uid())::text or public.is_admin()));

drop policy if exists "media: delete own" on storage.objects;
create policy "media: delete own" on storage.objects
  for delete to authenticated using (bucket_id = 'media' and (owner_id = (auth.uid())::text or public.is_admin()));

/* Dein persönlicher Admin-Link. In jedem Browser öffnen, in dem du Plauderecke benutzt. */
select 'https://zuljiamar-pixel.github.io/Plauder-Ecke/#admin=' || secret as dein_admin_link from public.admin_config;
