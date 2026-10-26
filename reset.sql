/* Plauderecke: alles auf Anfang. Löscht alle Gruppen, Mitglieder, Nachrichten und Benachrichtigungs-Anmeldungen. */
/* Die Website, die Einstellungen und die Benachrichtigungs-Funktion bleiben. Danach einfach eine neue Gruppe erstellen. */

delete from public.messages;
delete from public.members;
delete from public.groups;
delete from public.push_subscriptions;

/* Kontrolle: hier sollte jetzt überall 0 stehen */
select 'Alles gelöscht, neu anfangen!' as status,
  (select count(*) from public.groups) as gruppen,
  (select count(*) from public.members) as mitglieder,
  (select count(*) from public.messages) as nachrichten;
