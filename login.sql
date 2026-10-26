/* Plauderecke: Login mit Benutzername und Passwort */
/* Einmal im Supabase "SQL Editor" ausführen. Mehrmals ausführen schadet nicht. */
/* Es werden keine E-Mails verschickt: der Benutzername wird intern zu name@plauderecke.invalid, diese Adresse gibt es nirgends. */

create extension if not exists pgcrypto with schema extensions;

/* Welcher Benutzername zu wem gehört. Nur die Funktionen unten kommen da ran. */
create table if not exists public.accounts (
  user_id uuid primary key,
  username text not null unique check (username ~ '^[a-z0-9._-]{3,20}$'),
  created_at timestamptz not null default now()
);
alter table public.accounts enable row level security;
revoke all on public.accounts from anon, authenticated;

/* Hat das Handy schon einen Login? Gibt den Benutzernamen zurück, sonst nichts */
create or replace function public.account_status() returns text
language sql stable security definer set search_path = public as $$
  select username from public.accounts where user_id = auth.uid();
$$;
revoke execute on function public.account_status() from public;
grant execute on function public.account_status() to anon, authenticated;

/* Aus dem bisherigen Gast wird ein Account mit Benutzername und Passwort. Gruppen und Nachrichten bleiben. */
create or replace function public.register_account(uname text, pw text) returns text
language plpgsql security definer set search_path = public as $$
declare u text := lower(trim(uname)); mail text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from auth.users where id = auth.uid()) then raise exception 'no user'; end if;
  if u !~ '^[a-z0-9._-]{3,20}$' then raise exception 'bad username'; end if;
  if pw is null or char_length(pw) < 6 then raise exception 'short password'; end if;
  if exists (select 1 from public.accounts where user_id = auth.uid()) then raise exception 'already registered'; end if;
  mail := u || '@plauderecke.invalid';
  if exists (select 1 from public.accounts where username = u) or exists (select 1 from auth.users where lower(email) = mail) then raise exception 'username taken'; end if;
  update auth.users set
    email = mail,
    encrypted_password = extensions.crypt(pw, extensions.gen_salt('bf', 10)),
    email_confirmed_at = coalesce(email_confirmed_at, now()),
    is_anonymous = false,
    raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"provider": "email", "providers": ["email"]}'::jsonb,
    updated_at = now()
  where id = auth.uid();
  begin
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (auth.uid()::text, auth.uid(), jsonb_build_object('sub', auth.uid()::text, 'email', mail, 'email_verified', true), 'email', now(), now(), now());
  exception when others then null;
  end;
  insert into public.accounts (user_id, username) values (auth.uid(), u);
  return u;
end $$;
revoke execute on function public.register_account(text, text) from public, anon;
grant execute on function public.register_account(text, text) to authenticated;

/* Account löschen: alles von dir weg, auch deine Nachrichten. Danach ist der Benutzername wieder frei. */
create or replace function public.delete_my_account() returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if to_regclass('public.reactions') is not null then execute 'delete from public.reactions where user_id = $1' using me; end if;
  if to_regclass('public.push_subscriptions') is not null then execute 'delete from public.push_subscriptions where user_id = $1' using me; end if;
  if to_regclass('public.admins') is not null then execute 'delete from public.admins where user_id = $1' using me; end if;
  delete from public.messages where user_id = me;
  delete from public.members where user_id = me;
  delete from public.accounts where user_id = me;
  delete from auth.users where id = me;
  return true;
end $$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

/* Kontrolle: hier sollte "Login ist bereit!" stehen */
select 'Login ist bereit!' as status, (select count(*) from public.accounts) as accounts;
