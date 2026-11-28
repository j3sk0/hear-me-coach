-- Push notifications via Expo Push (the native app registers its Expo push token).
-- Events are written to an outbox by triggers; a pg_cron job sends due messages every minute.
-- Upvotes and "videos waiting for the coach" are bundled; nothing is sent 22:00-07:00 (Berlin) unless the member turns quiet hours off.

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

create table push_device (
  push_token text primary key check (push_token ~ '^Expo(nent)?PushToken\[.+\]$'),
  member_id uuid not null references member(id) on delete cascade,
  platform text check (platform in ('ios','android')),
  created_at timestamptz not null default now(),
  last_seen timestamptz not null default now()
);
create index on push_device (member_id);

create table notify_pref (
  member_id uuid primary key references member(id) on delete cascade,
  new_post boolean not null default true,
  upvotes boolean not null default true,
  coach_queue boolean not null default true,
  adopted boolean not null default true,
  new_session boolean not null default true,
  rate_reminder boolean not null default true,
  results boolean not null default true,
  quiet_hours boolean not null default true
);

create table notification_outbox (
  id bigint generated always as identity primary key,
  member_id uuid not null references member(id) on delete cascade,
  kind text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}',
  group_key text,
  created_at timestamptz not null default now(),
  send_after timestamptz not null default now(),
  sent_at timestamptz
);
create index on notification_outbox (send_after) where sent_at is null;
create unique index notification_outbox_group on notification_outbox (member_id, group_key) where sent_at is null and group_key is not null;

alter table training_session add column reminder_sent_at timestamptz;
alter table training_session add column results_sent_at timestamptz;

alter table push_device enable row level security;
alter table notify_pref enable row level security;
alter table notification_outbox enable row level security;
revoke all on push_device, notify_pref, notification_outbox from anon, authenticated;

-- ---------- enqueue helpers ----------
create or replace function _enqueue(p_member uuid, p_kind text, p_title text, p_body text, p_data jsonb,
  p_group text default null, p_delay interval default '0')
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_group is null then
    insert into public.notification_outbox (member_id, kind, title, body, data, send_after)
    values (p_member, p_kind, p_title, p_body, coalesce(p_data, '{}'), now() + p_delay);
  else
    insert into public.notification_outbox (member_id, kind, title, body, data, group_key, send_after)
    values (p_member, p_kind, p_title, p_body, coalesce(p_data, '{}'), p_group, now() + p_delay)
    on conflict (member_id, group_key) where sent_at is null and group_key is not null
    do update set title = excluded.title, body = excluded.body, data = excluded.data;
  end if;
end $$;

-- new post -> everyone else in the team
create or replace function _on_post_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
declare t public.team; who text;
begin
  select * into t from public.team where id = new.team_id;
  if t.mode <> 'team' then return new; end if;
  who := case when new.anonymous then 'Jemand' else coalesce((select name from public.member where id = new.submitter_id), 'Jemand') end;
  perform public._enqueue(m.id, 'new_post', 'Neues Video im Pool',
    who || ' hat ' || coalesce('„' || new.title || '“', 'ein Video') || ' geteilt. Jetzt anschauen und upvoten.',
    jsonb_build_object('tab', 'pool', 'post_id', new.id))
  from public.member m where m.team_id = new.team_id and m.id is distinct from new.submitter_id;
  return new;
end $$;
create trigger post_notify after insert on post for each row execute function _on_post_insert();

-- upvote -> submitter (bundled over 10 minutes)
create or replace function _on_upvote_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
declare p public.post; n int;
begin
  select * into p from public.post where id = new.post_id;
  if p.submitter_id is null or p.submitter_id = new.member_id then return new; end if;
  select coalesce((o.data->>'count')::int, 0) + 1 into n from (select 1) x
    left join public.notification_outbox o on o.member_id = p.submitter_id and o.group_key = 'upvote:' || p.id and o.sent_at is null;
  perform public._enqueue(p.submitter_id, 'upvotes', 'Neue Upvotes',
    'Dein Video ' || coalesce('„' || p.title || '“ ', '') || 'hat ' || n || case when n = 1 then ' neuen Upvote.' else ' neue Upvotes.' end,
    jsonb_build_object('tab', 'mine', 'post_id', p.id, 'count', n), 'upvote:' || p.id, interval '10 minutes');
  return new;
end $$;
create trigger upvote_notify after insert on upvote for each row execute function _on_upvote_insert();

-- status changes: reached threshold -> coaches (bundled 5 min); adopted -> submitter
create or replace function _on_post_status() returns trigger
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if new.status = 'relevant' and old.status = 'new' then
    select count(*) into n from public.post where team_id = new.team_id and status = 'relevant';
    perform public._enqueue(m.id, 'coach_queue', 'Videos warten auf dich',
      case when n = 1 then '1 Video hat genug Upvotes. Schau es dir an.' else n || ' Videos haben genug Upvotes. Schau sie dir an.' end,
      jsonb_build_object('tab', 'coach', 'count', n), 'coach_queue:' || new.team_id, interval '5 minutes')
    from public.member m where m.team_id = new.team_id and m.role = 'coach';
  elsif new.status = 'adopted' and old.status <> 'adopted' and new.submitter_id is not null
        and (select role from public.member where id = new.submitter_id) <> 'coach' then
    perform public._enqueue(new.submitter_id, 'adopted', 'Dein Video kommt ins Training',
      'Der Coach hat ' || coalesce('„' || new.title || '“', 'dein Video') || ' ins Training aufgenommen.',
      jsonb_build_object('tab', 'training', 'post_id', new.id));
  end if;
  return new;
end $$;
create trigger post_status_notify after update of status on post for each row execute function _on_post_status();

-- session published -> everyone except the coach who published
create or replace function _on_session_publish() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'published' and (tg_op = 'INSERT' or old.status <> 'published') then
    perform public._enqueue(m.id, 'new_session', 'Neues Training: ' || new.title,
      to_char(new.starts_at at time zone 'Europe/Berlin', 'DD.MM. "um" HH24:MI "Uhr"') || coalesce(', ' || new.place, '')
        || '. Schau dir an, was dran ist.',
      jsonb_build_object('tab', 'training', 'session_id', new.id))
    from public.member m where m.team_id = new.team_id and m.id is distinct from new.created_by;
  end if;
  return new;
end $$;
create trigger session_notify after insert or update of status on training_session for each row execute function _on_session_publish();

-- ---------- scheduled: rating reminders (when the session ends) and results (24 h later) ----------
create or replace function _session_jobs() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare s record; n int; a numeric;
begin
  for s in select * from public.training_session
           where status = 'published' and reminder_sent_at is null
             and starts_at + make_interval(mins => duration_min) <= now()
             and starts_at + make_interval(mins => duration_min) > now() - interval '2 days' loop
    perform public._enqueue(m.id, 'rate_reminder', 'Wie war das Training?',
      'Bewerte „' || s.title || '“ mit ein paar Sternen. Dauert 10 Sekunden.',
      jsonb_build_object('tab', 'training', 'session_id', s.id, 'rate', true))
    from public.member m where m.team_id = s.team_id
      and not exists (select 1 from public.session_rating r where r.session_id = s.id and r.member_id = m.id);
    update public.training_session set reminder_sent_at = now() where id = s.id;
  end loop;
  for s in select * from public.training_session
           where status = 'published' and results_sent_at is null
             and starts_at + make_interval(mins => duration_min) <= now() - interval '24 hours' loop
    select count(*), round(avg(stars)::numeric, 1) into n, a from public.session_rating where session_id = s.id;
    if n > 0 then
      perform public._enqueue(m.id, 'results', 'Ergebnis: ' || s.title,
        replace(a::text, '.', ',') || ' von 5 Sternen bei ' || n || case when n = 1 then ' Bewertung.' else ' Bewertungen.' end,
        jsonb_build_object('tab', 'training', 'session_id', s.id))
      from public.member m where m.team_id = s.team_id;
    end if;
    update public.training_session set results_sent_at = now() where id = s.id;
  end loop;
end $$;

-- ---------- sender ----------
create or replace function _send_push() returns int
language plpgsql volatile security definer set search_path = '' as $$
declare msgs jsonb; ids bigint[]; quiet boolean :=
  extract(hour from now() at time zone 'Europe/Berlin') >= 22 or extract(hour from now() at time zone 'Europe/Berlin') < 7;
begin
  perform public._session_jobs();
  -- drop messages the member has switched off or that cannot be delivered (no device)
  update public.notification_outbox o set sent_at = now()
   where o.sent_at is null and o.send_after <= now() and (
     not exists (select 1 from public.push_device d where d.member_id = o.member_id)
     or exists (select 1 from public.notify_pref p where p.member_id = o.member_id and not (
        case o.kind when 'new_post' then p.new_post when 'upvotes' then p.upvotes when 'coach_queue' then p.coach_queue
          when 'adopted' then p.adopted when 'new_session' then p.new_session when 'rate_reminder' then p.rate_reminder
          when 'results' then p.results else true end)));
  with due as (
    select o.* from public.notification_outbox o
     left join public.notify_pref p on p.member_id = o.member_id
     where o.sent_at is null and o.send_after <= now()
       and not (quiet and coalesce(p.quiet_hours, true))
     order by o.id limit 90)
  select array_agg(distinct due.id),
         jsonb_agg(jsonb_build_object('to', d.push_token, 'title', due.title, 'body', due.body,
           'data', due.data || jsonb_build_object('kind', due.kind), 'sound', 'default', 'channelId', 'default'))
    into ids, msgs
    from due join public.push_device d on d.member_id = due.member_id;
  if ids is null then return 0; end if;
  perform net.http_post(url := 'https://exp.host/--/api/v2/push/send',
    body := msgs, headers := '{"Content-Type":"application/json","Accept":"application/json"}'::jsonb);
  update public.notification_outbox set sent_at = now() where id = any(ids);
  delete from public.notification_outbox where sent_at < now() - interval '30 days';
  return array_length(ids, 1);
end $$;

select cron.schedule('hmc-send-push', '* * * * *', 'select public._send_push()');

-- ---------- API ----------
create or replace function register_push(p_token text, p_push_token text, p_platform text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  insert into public.push_device (push_token, member_id, platform) values (p_push_token, m.id, p_platform)
  on conflict (push_token) do update set member_id = excluded.member_id, platform = excluded.platform, last_seen = now();
  insert into public.notify_pref (member_id) values (m.id) on conflict do nothing;
end $$;

create or replace function unregister_push(p_push_token text)
returns void language sql volatile security definer set search_path = '' as $$
  delete from public.push_device where push_token = p_push_token
$$;

create or replace function get_notify_prefs(p_token text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token); r jsonb;
begin
  insert into public.notify_pref (member_id) values (m.id) on conflict do nothing;
  select to_jsonb(p) - 'member_id' into r from public.notify_pref p where p.member_id = m.id;
  return r || jsonb_build_object('devices', (select count(*) from public.push_device where member_id = m.id));
end $$;

create or replace function set_notify_prefs(p_token text, p_prefs jsonb)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  insert into public.notify_pref (member_id) values (m.id) on conflict do nothing;
  update public.notify_pref set
    new_post = coalesce((p_prefs->>'new_post')::boolean, new_post),
    upvotes = coalesce((p_prefs->>'upvotes')::boolean, upvotes),
    coach_queue = coalesce((p_prefs->>'coach_queue')::boolean, coach_queue),
    adopted = coalesce((p_prefs->>'adopted')::boolean, adopted),
    new_session = coalesce((p_prefs->>'new_session')::boolean, new_session),
    rate_reminder = coalesce((p_prefs->>'rate_reminder')::boolean, rate_reminder),
    results = coalesce((p_prefs->>'results')::boolean, results),
    quiet_hours = coalesce((p_prefs->>'quiet_hours')::boolean, quiet_hours)
  where member_id = m.id;
end $$;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function create_team(text,text,text,text), join_team(text,text), whoami(text),
  list_posts(text), add_post(text,text,text,text,text,boolean,text), toggle_upvote(text,uuid),
  delete_post(text,uuid), review_post(text,uuid,text,int,text,boolean,text),
  set_threshold(text,int), leave_team(text), set_post_category(text,uuid,text),
  set_team(text,text,text), add_category(text,text), delete_category(text,text),
  rate_post(text,uuid,int), log_workout(text,uuid,text), undo_workout(text,uuid), list_my_log(text),
  set_team_style(text,text,text), login_with_code(text), new_login_code(text), new_share_key(text),
  share_link(text,text,boolean), logout(text),
  save_session(text,uuid,text,timestamptz,int,text,text,jsonb), publish_session(text,uuid),
  delete_session(text,uuid), rate_session(text,uuid,int,text), list_sessions(text),
  register_push(text,text,text), unregister_push(text), get_notify_prefs(text), set_notify_prefs(text,jsonb)
  to anon, authenticated;
