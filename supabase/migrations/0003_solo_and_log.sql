-- Solo mode (personal collection without a coach) and a workout log for statistics.

alter table team add column mode text not null default 'team' check (mode in ('team','solo'));

create table workout_log (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references post(id) on delete cascade,
  member_id uuid not null references member(id) on delete cascade,
  done_at timestamptz not null default now(),
  note text check (length(note) <= 300)
);
create index on workout_log (member_id, done_at desc);
create index on workout_log (post_id);
alter table workout_log enable row level security;
revoke all on workout_log from anon, authenticated;

create or replace function _member_json(m public.member) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'member_id', m.id, 'name', m.name, 'role', m.role,
    'team', jsonb_build_object('id', t.id, 'name', t.name, 'sport', t.sport, 'mode', t.mode,
      'threshold', t.upvote_threshold,
      'player_code', case when t.mode = 'team' then t.player_code end,
      'coach_code', case when m.role = 'coach' and t.mode = 'team' then t.coach_code end,
      'categories', coalesce((select jsonb_agg(c.name order by c.created_at, c.name)
                              from public.category c where c.team_id = t.id), '[]'::jsonb)))
  from public.team t where t.id = m.team_id
$$;

drop function create_team(text, text, text);
create or replace function create_team(p_team_name text, p_coach_name text, p_sport text, p_mode text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare t public.team; m public.member;
        tok text := encode(extensions.gen_random_bytes(24), 'hex');
        md text := case when p_mode = 'solo' then 'solo' else 'team' end;
begin
  insert into public.team (name, player_code, coach_code, sport, mode)
  values (trim(p_team_name), public._code(), public._code(),
          coalesce(nullif(left(trim(p_sport), 40), ''), 'Allgemein'), md) returning * into t;
  if md = 'solo' then
    insert into public.category (team_id, name)
    select t.id, n from unnest(array['Aufwärmen','Brust','Rücken','Schultern','Arme','Beine','Core','Cardio','Dehnen']) n;
  else
    perform public._seed_categories(t.id);
  end if;
  insert into public.member (team_id, name, role, token_hash)
  values (t.id, trim(p_coach_name), 'coach', public._hash(tok)) returning * into m;
  return public._member_json(m) || jsonb_build_object('token', tok);
end $$;

-- solo collections cannot be joined
create or replace function join_team(p_code text, p_name text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare t public.team; r text; m public.member;
        tok text := encode(extensions.gen_random_bytes(24), 'hex');
        c text := upper(trim(p_code));
begin
  select * into t from public.team where (player_code = c or coach_code = c) and mode = 'team';
  if t.id is null then raise exception 'invalid_code'; end if;
  r := case when t.coach_code = c then 'coach' else 'player' end;
  insert into public.member (team_id, name, role, token_hash)
  values (t.id, trim(p_name), r, public._hash(tok)) returning * into m;
  return public._member_json(m) || jsonb_build_object('token', tok);
end $$;

-- quick star rating (coach, or owner in solo mode)
create or replace function rate_post(p_token text, p_post_id uuid, p_stars int)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  if not exists (select 1 from public.post where id = p_post_id and team_id = m.team_id) then raise exception 'not_found'; end if;
  insert into public.coach_review (post_id, coach_id, stars)
  values (p_post_id, m.id, case when p_stars between 1 and 5 then p_stars end)
  on conflict (post_id) do update set stars = excluded.stars, coach_id = excluded.coach_id, updated_at = now();
end $$;

create or replace function log_workout(p_token text, p_post_id uuid, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token); n int;
begin
  if not exists (select 1 from public.post where id = p_post_id and team_id = m.team_id) then raise exception 'not_found'; end if;
  insert into public.workout_log (post_id, member_id, note) values (p_post_id, m.id, nullif(left(trim(p_note), 300), ''));
  select count(*) into n from public.workout_log where post_id = p_post_id and member_id = m.id;
  return jsonb_build_object('count', n);
end $$;

-- undo: removes my most recent log entry for this post
create or replace function undo_workout(p_token text, p_post_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  delete from public.workout_log where id = (
    select id from public.workout_log where post_id = p_post_id and member_id = m.id
    order by done_at desc limit 1);
end $$;

-- my own log (for statistics, computed in the app)
create or replace function list_my_log(p_token text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('post_id', l.post_id, 'done_at', l.done_at,
           'title', p.title, 'category', p.category, 'platform', p.platform) order by l.done_at desc), '[]'::jsonb)
  from public.workout_log l join public.post p on p.id = l.post_id
  where l.member_id = (public._me(p_token)).id
$$;

create or replace function list_posts(p_token text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  return coalesce((
    select jsonb_agg(row_to_json(x) order by x.created_at desc)
    from (
      select p.id, p.url, p.platform, p.title, p.thumbnail_url, p.comment, p.category,
             p.anonymous, p.status, p.created_at,
             (p.submitter_id = m.id) as mine,
             case when not p.anonymous or m.role = 'coach' or p.submitter_id = m.id
                  then s.name end as submitter,
             (select count(*) from public.upvote u where u.post_id = p.id)::int as upvotes,
             exists(select 1 from public.upvote u
                    where u.post_id = p.id and u.member_id = m.id) as voted,
             case when m.role = 'coach' then
               (select coalesce(jsonb_agg(mm.name order by mm.name), '[]')
                from public.upvote u join public.member mm on mm.id = u.member_id
                where u.post_id = p.id) end as voters,
             (select count(*) from public.workout_log l where l.post_id = p.id and l.member_id = m.id)::int as done_count,
             (select max(l.done_at) from public.workout_log l where l.post_id = p.id and l.member_id = m.id) as last_done,
             (select jsonb_build_object(
                'stars', r.stars,
                'note', case when m.role = 'coach' or r.note_public then r.note end,
                'note_public', r.note_public,
                'reason', case when m.role = 'coach' or p.submitter_id = m.id then r.reason end)
              from public.coach_review r where r.post_id = p.id) as review
      from public.post p
      left join public.member s on s.id = p.submitter_id
      where p.team_id = m.team_id
    ) x), '[]'::jsonb);
end $$;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function create_team(text,text,text,text), join_team(text,text), whoami(text),
  list_posts(text), add_post(text,text,text,text,text,boolean,text), toggle_upvote(text,uuid),
  delete_post(text,uuid), review_post(text,uuid,text,int,text,boolean,text),
  set_threshold(text,int), leave_team(text), set_post_category(text,uuid,text),
  set_team(text,text,text), add_category(text,text), delete_category(text,text),
  rate_post(text,uuid,int), log_workout(text,uuid,text), undo_workout(text,uuid), list_my_log(text)
  to anon, authenticated;
