/* Plauderecke: Benachrichtigungen einrichten */
/* Einmal im Supabase "SQL Editor" einfügen und auf "Run" tippen. Darf auch mehrmals laufen. */

create extension if not exists pg_net;

/* Welche Handys Benachrichtigungen wollen */
create table if not exists public.push_subscriptions (
  endpoint text primary key,
  user_id uuid not null default auth.uid(),
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;

drop policy if exists "push: see own" on public.push_subscriptions;
create policy "push: see own" on public.push_subscriptions
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "push: turn off own" on public.push_subscriptions;
create policy "push: turn off own" on public.push_subscriptions
  for delete to authenticated using (user_id = auth.uid());

create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_endpoint !~ '^https://' or length(p_endpoint) > 1000 or length(p_p256dh) > 200 or length(p_auth) > 100 then raise exception 'bad subscription'; end if;
  insert into public.push_subscriptions (endpoint, user_id, p256dh, auth) values (p_endpoint, auth.uid(), p_p256dh, p_auth)
    on conflict (endpoint) do update set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth, created_at = now();
end $$;
revoke execute on function public.save_push_subscription(text, text, text) from public, anon;
grant execute on function public.save_push_subscription(text, text, text) to authenticated;

/* Geheime Schlüssel für den Versand. Nur der Server kann sie lesen, keine Regel gibt sie frei. */
create table if not exists public.push_config (
  id int primary key default 1 check (id = 1),
  secret text not null default replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
  vapid_public text,
  vapid_private text
);
alter table public.push_config enable row level security;
revoke all on public.push_config from anon, authenticated;
insert into public.push_config (id) values (1) on conflict (id) do nothing;

/* Bei jeder neuen Nachricht die Funktion "notify" anstoßen. Klappt das nicht, wird die Nachricht trotzdem gespeichert. */
create or replace function public.notify_new_message() returns trigger
language plpgsql security definer set search_path = public as $$
declare s text;
begin
  select secret into s from public.push_config where id = 1;
  perform net.http_post(
    url := 'https://yyruenmtgfvegxenbhvp.supabase.co/functions/v1/swift-task',
    body := jsonb_build_object('message', jsonb_build_object('id', new.id, 'group_id', new.group_id, 'user_id', new.user_id, 'kind', new.kind, 'text', left(new.text, 200))),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-plauder-secret', s),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  return new;
end $$;

drop trigger if exists messages_notify on public.messages;
create trigger messages_notify after insert on public.messages
  for each row execute function public.notify_new_message();

/* Kontrolle: hier sollte jetzt eine Zeile mit "ja" und 1 stehen */
select 'Benachrichtigungen sind eingerichtet' as status,
  (case when exists (select 1 from pg_extension where extname = 'pg_net') then 'ja' else 'nein' end) as pg_net,
  (select count(*) from public.push_config) as config;
