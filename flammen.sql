/* Plauderecke: Flammen schon mit 1 Nachricht pro Tag */
/* Einmal im Supabase "SQL Editor" ausführen. Mehrmals ausführen schadet nicht. Braucht vorher update.sql. */

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

/* Kontrolle: hier sollte "Flammen sind bereit!" stehen */
select 'Flammen sind bereit!' as status;
