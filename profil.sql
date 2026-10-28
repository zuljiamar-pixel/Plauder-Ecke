/* Plauderecke: Status, Geburtstag, "Zuletzt online", Gruppenbild und Gruppenname */
/* Einmal im Supabase "SQL Editor" ausführen. Mehrmals ausführen schadet nicht. Braucht vorher setup.sql und funktionen.sql. */

/* ---------- Über dich: ein Status-Satz, der Geburtstag (nur Tag und Monat) und wann man zuletzt da war ---------- */
create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  status text check (status is null or char_length(status) <= 60),
  birthday text check (birthday is null or birthday ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'),
  show_seen boolean not null default true,
  seen_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;

/* Was ich von den Leuten aus meinen Gruppen sehe. Wer "Zuletzt online" ausgeschaltet hat, zeigt keine Zeit. */
create or replace function public.people()
returns table (user_id uuid, status text, birthday text, seen_at timestamptz, show_seen boolean)
language sql stable security definer set search_path = public as $$
  select p.user_id, p.status, p.birthday,
    case when p.show_seen or p.user_id = auth.uid() then p.seen_at end,
    case when p.user_id = auth.uid() then p.show_seen end
  from public.profiles p
  where p.user_id = auth.uid() or exists (
    select 1 from public.members a join public.members b on b.group_id = a.group_id
    where a.user_id = auth.uid() and b.user_id = p.user_id);
$$;
revoke execute on function public.people() from public, anon;
grant execute on function public.people() to authenticated;

/* Nur was mitgeschickt wird, ändert sich: {"status": "..."}, {"birthday": "03-14"}, {"show_seen": false} */
create or replace function public.set_profile(p jsonb) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into public.profiles (user_id) values (auth.uid()) on conflict (user_id) do nothing;
  update public.profiles set
    status = case when p ? 'status' then nullif(left(btrim(regexp_replace(coalesce(p->>'status', ''), '\s+', ' ', 'g')), 60), '') else status end,
    birthday = case when p ? 'birthday' then nullif(btrim(coalesce(p->>'birthday', '')), '') else birthday end,
    show_seen = case when p ? 'show_seen' then coalesce((p->>'show_seen')::boolean, true) else show_seen end,
    updated_at = now()
  where user_id = auth.uid();
  return true;
end $$;
revoke execute on function public.set_profile(jsonb) from public, anon;
grant execute on function public.set_profile(jsonb) to authenticated;

/* Die Website meldet sich alle paar Minuten, solange sie offen ist */
create or replace function public.seen() returns timestamptz
language plpgsql security definer set search_path = public as $$
declare t timestamptz := now();
begin
  if auth.uid() is null then return null; end if;
  insert into public.profiles (user_id, seen_at) values (auth.uid(), t)
    on conflict (user_id) do update set seen_at = t;
  return t;
end $$;
revoke execute on function public.seen() from public, anon;
grant execute on function public.seen() to authenticated;

/* ---------- Gruppenbild und Gruppenname: alle in der Gruppe dürfen sie ändern (nicht bei privaten Chats) ---------- */
alter table public.groups add column if not exists pic text;
alter table public.groups drop constraint if exists groups_pic_ok;
alter table public.groups add constraint groups_pic_ok
  check (pic is null or pic ~ '^[0-9a-f-]{36}/[0-9a-z-]{8,40}\.[a-z0-9]{2,5}$');

create or replace function public.rename_group(g uuid, n text) returns text
language plpgsql security definer set search_path = public as $$
declare nn text := left(btrim(regexp_replace(coalesce(n, ''), '\s+', ' ', 'g')), 40);
begin
  if auth.uid() is null or not public.is_member(g) then raise exception 'not allowed'; end if;
  if (select is_dm from public.groups where id = g) then raise exception 'private chat'; end if;
  if nn = '' then raise exception 'empty name'; end if;
  update public.groups set name = nn where id = g;
  return nn;
end $$;
revoke execute on function public.rename_group(uuid, text) from public, anon;
grant execute on function public.rename_group(uuid, text) to authenticated;

create or replace function public.set_group_pic(g uuid, p text) returns text
language plpgsql security definer set search_path = public as $$
declare pp text := nullif(btrim(coalesce(p, '')), '');
begin
  if auth.uid() is null or not public.is_member(g) then raise exception 'not allowed'; end if;
  if (select is_dm from public.groups where id = g) then raise exception 'private chat'; end if;
  if pp is not null and split_part(pp, '/', 1) <> g::text then raise exception 'bad picture'; end if;
  update public.groups set pic = pp where id = g;
  return pp;
end $$;
revoke execute on function public.set_group_pic(uuid, text) from public, anon;
grant execute on function public.set_group_pic(uuid, text) to authenticated;

/* Kontrolle: hier sollte "Profil und Gruppen sind bereit!" stehen */
select 'Profil und Gruppen sind bereit!' as status,
  (select count(*) from pg_tables where schemaname = 'public' and tablename = 'profiles') as tabellen;
