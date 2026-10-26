/* Plauderecke: Update für Profilbilder, Gelesen, Reaktionen und Flammen */
/* Einmal im Supabase "SQL Editor" ausführen. Mehrmals ausführen schadet nicht. */

/* ---------- Profilbilder ---------- */
alter table public.members add column if not exists avatar text;
alter table public.members drop constraint if exists members_avatar_ok;
alter table public.members add constraint members_avatar_ok
  check (avatar is null or avatar ~ '^[0-9a-f-]{36}/[0-9a-z-]{8,40}\.[a-z0-9]{2,5}$');

/* Beim eigenen Eintrag dürfen Name und Profilbild geändert werden, sonst nichts */
grant update (name, avatar) on public.members to authenticated;

/* ---------- Gelesen: bis wann jemand eine Gruppe gelesen hat ---------- */
alter table public.members add column if not exists last_read timestamptz;
/* Wer schon dabei ist, startet ohne Berg von ungelesenen Nachrichten */
update public.members set last_read = now() where last_read is null;

/* Die Zeit kommt vom Server, damit eine falsch gehende Handy-Uhr nichts durcheinanderbringt */
create or replace function public.mark_read(g uuid) returns timestamptz
language sql security definer set search_path = public as $$
  update public.members set last_read = now() where group_id = g and user_id = auth.uid() returning last_read;
$$;
revoke execute on function public.mark_read(uuid) from public, anon;
grant execute on function public.mark_read(uuid) to authenticated;

/* ---------- Reaktionen auf Nachrichten ---------- */
create table if not exists public.reactions (
  message_id uuid not null references public.messages (id) on delete cascade,
  user_id uuid not null default auth.uid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
create index if not exists reactions_group on public.reactions (group_id);
alter table public.reactions enable row level security;
revoke insert, update, delete on public.reactions from anon, authenticated;
grant select on public.reactions to authenticated;
drop policy if exists "reactions: members read" on public.reactions;
create policy "reactions: members read" on public.reactions
  for select to authenticated using (public.is_member(group_id));

/* Reagieren geht nur hierüber: gleiches Emoji nochmal = Reaktion weg, anderes Emoji = ersetzen */
create or replace function public.react(msg uuid, e text) returns text
language plpgsql security definer set search_path = public as $$
declare g uuid; cur text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select group_id into g from public.messages where id = msg;
  if g is null or not public.is_member(g) then raise exception 'not allowed'; end if;
  select emoji into cur from public.reactions where message_id = msg and user_id = auth.uid();
  if e is null or e = '' or e = cur then
    delete from public.reactions where message_id = msg and user_id = auth.uid();
    return null;
  end if;
  insert into public.reactions (message_id, user_id, group_id, emoji) values (msg, auth.uid(), g, left(e, 16))
    on conflict (message_id, user_id) do update set emoji = excluded.emoji, created_at = now();
  return e;
end $$;
revoke execute on function public.react(uuid, text) from public, anon;
grant execute on function public.react(uuid, text) to authenticated;

do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'reactions') then
    alter publication supabase_realtime add table public.reactions;
  end if;
end $$;

/* ---------- Chat-Liste: letzte Nachricht, Ungelesene und Flammen pro Gruppe in einem Rutsch ---------- */
/* Flamme: so viele Tage am Stück, an denen im Chat mindestens eine Nachricht geschickt wurde */
create or replace function public.chat_list() returns table (
  group_id uuid, last_id uuid, last_by uuid, last_kind text, last_sticker boolean, last_at timestamptz,
  unread int, streak int, streak_today boolean
)
language sql stable security definer set search_path = public as $$
  with mine as (
    select mb.group_id, coalesce(mb.last_read, mb.joined_at) as seen from public.members mb where mb.user_id = auth.uid()
  ),
  latest as (
    select distinct on (m.group_id) m.group_id, m.id, m.user_id, m.kind, coalesce(m.media->>'sticker' = 'true', false) as sticker, m.created_at
    from public.messages m join mine on mine.group_id = m.group_id
    order by m.group_id, m.created_at desc
  ),
  unseen as (
    select m.group_id, count(*)::int as n
    from public.messages m join mine on mine.group_id = m.group_id
    where m.created_at > mine.seen and m.user_id <> auth.uid()
    group by m.group_id
  ),
  days as (
    select m.group_id, (m.created_at at time zone 'Europe/Zurich')::date as d
    from public.messages m join mine on mine.group_id = m.group_id
    where m.created_at > now() - interval '400 days'
    group by m.group_id, (m.created_at at time zone 'Europe/Zurich')::date
  ),
  runs as (
    select days.group_id, days.d, days.d - (row_number() over (partition by days.group_id order by days.d))::int as run from days
  ),
  streaks as (
    select runs.group_id, max(runs.d) as last_day, count(*)::int as len from runs group by runs.group_id, runs.run
  ),
  current_streak as (
    select streaks.group_id, streaks.len, streaks.last_day = (now() at time zone 'Europe/Zurich')::date as today
    from streaks where streaks.last_day >= (now() at time zone 'Europe/Zurich')::date - 1
  )
  select mine.group_id, latest.id, latest.user_id, latest.kind, latest.sticker, latest.created_at,
    coalesce(unseen.n, 0), coalesce(current_streak.len, 0), coalesce(current_streak.today, false)
  from mine
  left join latest on latest.group_id = mine.group_id
  left join unseen on unseen.group_id = mine.group_id
  left join current_streak on current_streak.group_id = mine.group_id;
$$;
revoke execute on function public.chat_list() from public, anon;
grant execute on function public.chat_list() to authenticated;

/* Kontrolle: hier sollte "Update fertig!" stehen und überall eine 1 */
select 'Update fertig!' as status,
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'members' and column_name = 'avatar') as profilbilder,
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'members' and column_name = 'last_read') as gelesen,
  (select count(*) from pg_tables where schemaname = 'public' and tablename = 'reactions') as reaktionen,
  (select count(*) from pg_proc where proname = 'chat_list') as chatliste;
