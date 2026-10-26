/* Plauderecke: Private Chats zu zweit */
/* Einmal im Supabase "SQL Editor" ausführen. Mehrmals ausführen schadet nicht. */
/* Ein privater Chat ist eine kleine Gruppe mit genau zwei Leuten. Niemand sonst kann sie sehen oder beitreten, auch der Admin nicht. */

alter table public.groups add column if not exists is_dm boolean not null default false;

/* Privaten Chat öffnen: gibt es schon einen mit dieser Person, kommt der, sonst wird einer gemacht. Geht nur mit Leuten aus deinen Gruppen. */
create or replace function public.open_dm(other uuid, my_name text) returns public.groups
language plpgsql security definer set search_path = public as $$
declare g public.groups; mine text := left(trim(coalesce(my_name, '')), 30); theirs text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if other is null or other = auth.uid() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.members a join public.members b on b.group_id = a.group_id where a.user_id = auth.uid() and b.user_id = other) then raise exception 'not allowed'; end if;
  /* Schreiben beide gleichzeitig zum ersten Mal, gibt es trotzdem nur einen Chat */
  perform pg_advisory_xact_lock(hashtext(least(auth.uid()::text, other::text) || greatest(auth.uid()::text, other::text)));
  select gr.* into g from public.groups gr
    where gr.is_dm
      and exists (select 1 from public.members m where m.group_id = gr.id and m.user_id = auth.uid())
      and exists (select 1 from public.members m where m.group_id = gr.id and m.user_id = other)
    limit 1;
  if found then return g; end if;
  select m.name into theirs from public.members m where m.user_id = other order by m.joined_at desc limit 1;
  if mine = '' then select m.name into mine from public.members m where m.user_id = auth.uid() order by m.joined_at desc limit 1; end if;
  mine := coalesce(nullif(mine, ''), 'Ich'); theirs := coalesce(nullif(theirs, ''), 'Jemand');
  insert into public.groups (name, created_by, is_dm) values (left(mine || ' & ' || theirs, 40), auth.uid(), true) returning * into g;
  insert into public.members (group_id, user_id, name) values (g.id, auth.uid(), mine), (g.id, other, theirs);
  return g;
end $$;
revoke execute on function public.open_dm(uuid, text) from public, anon;
grant execute on function public.open_dm(uuid, text) to authenticated;

/* Einladungslinks gehen nur für richtige Gruppen, nie für private Chats */
create or replace function public.join_group(code text, my_name text) returns public.groups
language plpgsql security definer set search_path = public as $$
declare g public.groups;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into g from public.groups where invite_code = trim(code);
  if not found or g.is_dm then raise exception 'invite code not found' using errcode = 'P0002'; end if;
  insert into public.members (group_id, user_id, name) values (g.id, auth.uid(), trim(my_name))
    on conflict (group_id, user_id) do nothing;
  return g;
end $$;
revoke execute on function public.join_group(text, text) from public, anon;
grant execute on function public.join_group(text, text) to authenticated;

/* Kontrolle: hier sollte "Private Chats sind bereit!" stehen */
select 'Private Chats sind bereit!' as status,
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'groups' and column_name = 'is_dm') as spalte_da;
