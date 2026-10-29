/* Plauderecke: Fehlerbericht für Anrufe */
/* Einmal im Supabase "SQL Editor" ausführen. Mehrmals ausführen schadet nicht. Braucht vorher anrufe.sql. */
/* Nach jedem Anruf speichert die Website, wie die Verbindung lief (nur Technik, kein Ton, kein Bild, keine Nachrichten). */
/* Lesen kann das nur der Besitzer im Supabase-Dashboard. Nach 14 Tagen wird es gelöscht. */

create table if not exists public.call_stats (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  message_id uuid,
  user_id uuid not null default auth.uid(),
  info jsonb not null check (pg_column_size(info) < 8000)
);
alter table public.call_stats enable row level security;
revoke all on public.call_stats from anon, authenticated;
grant insert on public.call_stats to authenticated;
drop policy if exists "call stats: add own" on public.call_stats;
create policy "call stats: add own" on public.call_stats
  for insert to authenticated with check (user_id = auth.uid());

create or replace function public.call_stats_trim() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.call_stats where created_at < now() - interval '14 days';
  return null;
end $$;
revoke execute on function public.call_stats_trim() from public, anon, authenticated;
drop trigger if exists call_stats_trim on public.call_stats;
create trigger call_stats_trim after insert on public.call_stats for each statement execute function public.call_stats_trim();

/* Kontrolle: hier sollte "Fehlerbericht ist bereit!" stehen */
select 'Fehlerbericht ist bereit!' as status;
