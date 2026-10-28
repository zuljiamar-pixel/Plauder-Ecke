/* Plauderecke: Hintergründe, Umfragen, @Erwähnen, Stummschalten, Bearbeiten */
/* Einmal im Supabase "SQL Editor" ausführen. Mehrmals ausführen schadet nicht. Braucht vorher setup.sql und push.sql. */

/* ---------- Chat-Hintergrund: eine Farbe (p:name) oder ein eigenes Foto (i:datei), für alle in der Gruppe gleich ---------- */
alter table public.groups add column if not exists is_dm boolean not null default false;
alter table public.groups add column if not exists theme text;
alter table public.groups drop constraint if exists groups_theme_ok;
alter table public.groups add constraint groups_theme_ok
  check (theme is null or theme ~ '^(p:[a-z]{2,12}|i:[0-9a-f-]{36}/[0-9a-z-]{8,40}\.[a-z0-9]{2,5})$');

create or replace function public.set_theme(g uuid, t text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_member(g) then raise exception 'not allowed'; end if;
  update public.groups set theme = nullif(trim(coalesce(t, '')), '') where id = g;
  return nullif(trim(coalesce(t, '')), '');
end $$;
revoke execute on function public.set_theme(uuid, text) from public, anon;
grant execute on function public.set_theme(uuid, text) to authenticated;

/* ---------- Nachrichten bearbeiten: nur den Text der eigenen Nachrichten ---------- */
alter table public.messages add column if not exists edited_at timestamptz;
alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check check (kind in ('text', 'image', 'video', 'audio', 'poll', 'call'));

create or replace function public.message_edited() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.text is distinct from old.text then
    if old.kind = 'text' and btrim(new.text) = '' then raise exception 'empty message'; end if;
    new.edited_at := now();
  end if;
  return new;
end $$;
drop trigger if exists messages_edited on public.messages;
create trigger messages_edited before update on public.messages for each row execute function public.message_edited();

revoke update on public.messages from anon, authenticated;
grant update (text) on public.messages to authenticated;
drop policy if exists "messages: edit own" on public.messages;
create policy "messages: edit own" on public.messages
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

/* ---------- Umfragen: eine Stimme pro Person, nochmal tippen nimmt sie zurück ---------- */
create table if not exists public.poll_votes (
  message_id uuid not null references public.messages (id) on delete cascade,
  user_id uuid not null default auth.uid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  choice int not null check (choice between 0 and 9),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
create index if not exists poll_votes_group on public.poll_votes (group_id);
alter table public.poll_votes enable row level security;
revoke insert, update, delete on public.poll_votes from anon, authenticated;
grant select on public.poll_votes to authenticated;
drop policy if exists "votes: members read" on public.poll_votes;
create policy "votes: members read" on public.poll_votes
  for select to authenticated using (public.is_member(group_id));

create or replace function public.vote(msg uuid, pick int) returns int
language plpgsql security definer set search_path = public as $$
declare g uuid; k text; n int; cur int;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select m.group_id, m.kind, case when jsonb_typeof(m.media->'options') = 'array' then jsonb_array_length(m.media->'options') else 0 end
    into g, k, n from public.messages m where m.id = msg;
  if g is null or k <> 'poll' or not public.is_member(g) then raise exception 'not allowed'; end if;
  select v.choice into cur from public.poll_votes v where v.message_id = msg and v.user_id = auth.uid();
  if pick is null or pick = cur then
    delete from public.poll_votes v where v.message_id = msg and v.user_id = auth.uid();
    return null;
  end if;
  if pick < 0 or pick >= least(n, 10) then raise exception 'bad choice'; end if;
  insert into public.poll_votes (message_id, user_id, group_id, choice) values (msg, auth.uid(), g, pick)
    on conflict (message_id, user_id) do update set choice = excluded.choice, created_at = now();
  return pick;
end $$;
revoke execute on function public.vote(uuid, int) from public, anon;
grant execute on function public.vote(uuid, int) to authenticated;

/* ---------- Stummschalten: wer eine Gruppe stumm hat, bekommt keine Benachrichtigung, ausser mit @ ---------- */
create table if not exists public.mutes (
  user_id uuid not null default auth.uid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, group_id)
);
alter table public.mutes enable row level security;
revoke all on public.mutes from anon;
revoke update on public.mutes from authenticated;
grant select, insert, delete on public.mutes to authenticated;
drop policy if exists "mutes: own read" on public.mutes;
create policy "mutes: own read" on public.mutes for select to authenticated using (user_id = auth.uid());
drop policy if exists "mutes: own add" on public.mutes;
create policy "mutes: own add" on public.mutes for insert to authenticated with check (user_id = auth.uid() and public.is_member(group_id));
drop policy if exists "mutes: own remove" on public.mutes;
create policy "mutes: own remove" on public.mutes for delete to authenticated using (user_id = auth.uid());

/* ---------- Wer eine Benachrichtigung bekommt und was drinsteht (die Benachrichtigungs-Funktion fragt hier nach) ---------- */
/* Stummgeschaltet: nichts, ausser man wird mit @Name oder @alle erwähnt. Privater Chat: oben steht, wer schreibt. */
create or replace function public.push_targets(g uuid, sender uuid, k text, t text)
returns table (endpoint text, p256dh text, auth text, title text, body text)
language sql stable security definer set search_path = public as $$
  with grp as (select gr.name, gr.is_dm from public.groups gr where gr.id = g),
  snd as (select coalesce((select m.name from public.members m where m.group_id = g and m.user_id = sender), 'Jemand') as name),
  lbl as (select case k
      when 'audio' then '🎤 Sprachnachricht'
      when 'video' then '🎬 Video' || case when coalesce(t, '') <> '' then ' ' || t else '' end
      when 'image' then '📷 Foto' || case when coalesce(t, '') <> '' then ' ' || t else '' end
      when 'poll' then '📊 Umfrage: ' || coalesce(t, '')
      when 'call' then case when t = 'video' then '📹 Videoanruf' else '📞 Anruf' end || ' – tippen zum Abnehmen'
      else coalesce(t, '') end as txt),
  who as (
    select mem.user_id,
      (position(lower('@' || mem.name) in lower(coalesce(t, ''))) > 0 or lower(coalesce(t, '')) like '%@alle%') as mentioned
    from public.members mem where mem.group_id = g and mem.user_id <> sender
  )
  select s.endpoint, s.p256dh, s.auth,
    case when (select is_dm from grp) then (select name from snd)
         when who.mentioned then '📣 ' || (select name from grp)
         else (select name from grp) end,
    left(case when (select is_dm from grp) then (select txt from lbl) else (select name from snd) || ': ' || (select txt from lbl) end, 200)
  from who
  join public.push_subscriptions s on s.user_id = who.user_id
  where who.mentioned or not exists (select 1 from public.mutes mu where mu.user_id = who.user_id and mu.group_id = g);
$$;
revoke execute on function public.push_targets(uuid, uuid, text, text) from public, anon, authenticated;

/* ---------- Live-Updates für Hintergründe und Abstimmungen ---------- */
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'groups') then
    alter publication supabase_realtime add table public.groups;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'poll_votes') then
    alter publication supabase_realtime add table public.poll_votes;
  end if;
end $$;

/* Kontrolle: hier sollte "Neue Funktionen sind bereit!" stehen */
select 'Neue Funktionen sind bereit!' as status,
  (select count(*) from pg_tables where schemaname = 'public' and tablename in ('poll_votes', 'mutes')) as tabellen;
