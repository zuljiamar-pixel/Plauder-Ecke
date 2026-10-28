/* Plauderecke: Sprach- und Videoanrufe */
/* Einmal im Supabase "SQL Editor" ausführen. Mehrmals ausführen schadet nicht. Braucht vorher funktionen.sql. */
/* Ein Anruf ist eine Nachricht der Art "call": darüber klingelt es bei den anderen und es kommt eine Benachrichtigung. */
/* Im Text steht zuerst "audio" oder "video", am Ende "ended:Sekunden", "missed" oder "declined". */

alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check check (kind in ('text', 'image', 'video', 'audio', 'poll', 'call'));

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

/* Kontrolle: hier sollte "Anrufe sind bereit!" stehen */
select 'Anrufe sind bereit!' as status;
