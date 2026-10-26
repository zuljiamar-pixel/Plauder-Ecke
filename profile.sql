/* Plauderecke: Profilbilder */
/* Einmal im Supabase "SQL Editor" ausführen. Danach kann jeder in der App ein Profilbild wählen. */

/* Wo das Profilbild liegt (eine Datei im Speicher "media"). Es steht bei jeder Gruppe, in der man ist. */
alter table public.members add column if not exists avatar text;
alter table public.members drop constraint if exists members_avatar_ok;
alter table public.members add constraint members_avatar_ok
  check (avatar is null or avatar ~ '^[0-9a-f-]{36}/[0-9a-z-]{8,40}\.[a-z0-9]{2,5}$');

/* Beim eigenen Eintrag dürfen jetzt Name und Profilbild geändert werden, sonst nichts */
grant update (name, avatar) on public.members to authenticated;

/* Kontrolle: hier sollte "Profilbilder sind bereit!" stehen */
select 'Profilbilder sind bereit!' as status,
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'members' and column_name = 'avatar') as spalte_da;
