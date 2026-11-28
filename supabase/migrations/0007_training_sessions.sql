-- Training plans: the coach builds a session from adopted videos, publishes it,
-- and after it has started every member can rate it once (stars + optional comment).

create table training_session (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references team(id) on delete cascade,
  title text not null check (length(title) between 1 and 80),
  starts_at timestamptz not null,
  duration_min int not null default 90 check (duration_min between 10 and 600),
  place text check (length(place) <= 80),
  note text check (length(note) <= 2000),
  status text not null default 'draft' check (status in ('draft','published')),
  created_by uuid references member(id) on delete set null,
  created_at timestamptz not null default now(),
  published_at timestamptz
);
create index on training_session (team_id, starts_at desc);

create table session_item (
  session_id uuid not null references training_session(id) on delete cascade,
  post_id uuid not null references post(id) on delete cascade,
  position int not null,
  minutes int check (minutes between 1 and 240),
  note text check (length(note) <= 300),
  primary key (session_id, post_id)
);
create index on session_item (post_id);

create table session_rating (
  session_id uuid not null references training_session(id) on delete cascade,
  member_id uuid not null references member(id) on delete cascade,
  stars int not null check (stars between 1 and 5),
  comment text check (length(comment) <= 500),
  created_at timestamptz not null default now(),
  primary key (session_id, member_id)
);
create index on session_rating (member_id);

alter table training_session enable row level security;
alter table session_item enable row level security;
alter table session_rating enable row level security;
revoke all on training_session, session_item, session_rating from anon, authenticated;

-- p_items: [{"post_id": "...", "minutes": 15, "note": "..."}] in display order
create or replace function save_session(p_token text, p_id uuid, p_title text, p_starts_at timestamptz,
  p_duration int, p_place text, p_note text, p_items jsonb)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token); sid uuid := p_id;
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  if sid is null then
    insert into public.training_session (team_id, title, starts_at, duration_min, place, note, created_by)
    values (m.team_id, trim(p_title), p_starts_at, coalesce(p_duration, 90), nullif(trim(p_place), ''), nullif(trim(p_note), ''), m.id)
    returning id into sid;
  else
    update public.training_session set title = trim(p_title), starts_at = p_starts_at, duration_min = coalesce(p_duration, 90),
      place = nullif(trim(p_place), ''), note = nullif(trim(p_note), '')
    where id = sid and team_id = m.team_id;
    if not found then raise exception 'not_found'; end if;
    delete from public.session_item where session_id = sid;
  end if;
  insert into public.session_item (session_id, post_id, position, minutes, note)
  select sid, (e->>'post_id')::uuid, (ord - 1)::int, nullif(e->>'minutes', '')::int, nullif(trim(e->>'note'), '')
  from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) with ordinality as x(e, ord)
  where exists (select 1 from public.post p where p.id = (e->>'post_id')::uuid and p.team_id = m.team_id);
  return sid;
end $$;

create or replace function publish_session(p_token text, p_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  update public.training_session set status = 'published', published_at = now()
   where id = p_id and team_id = m.team_id and status = 'draft';
  if not found then raise exception 'not_found'; end if;
end $$;

create or replace function delete_session(p_token text, p_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  delete from public.training_session where id = p_id and team_id = m.team_id;
  if not found then raise exception 'not_found'; end if;
end $$;

create or replace function rate_session(p_token text, p_id uuid, p_stars int, p_comment text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if not exists (select 1 from public.training_session s where s.id = p_id and s.team_id = m.team_id
                 and s.status = 'published' and s.starts_at <= now()) then raise exception 'not_ratable'; end if;
  insert into public.session_rating (session_id, member_id, stars, comment)
  values (p_id, m.id, p_stars, nullif(left(trim(p_comment), 500), ''))
  on conflict (session_id, member_id) do update set stars = excluded.stars, comment = excluded.comment, created_at = now();
end $$;

-- players see published sessions; ratings (average, count, comments) once rating has opened
create or replace function list_sessions(p_token text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  return coalesce((select jsonb_agg(x order by (x->>'starts_at')::timestamptz desc) from (
    select jsonb_build_object(
      'id', s.id, 'title', s.title, 'starts_at', s.starts_at, 'duration_min', s.duration_min,
      'place', s.place, 'note', s.note, 'status', s.status,
      'ratable', s.status = 'published' and s.starts_at <= now(),
      'items', coalesce((select jsonb_agg(jsonb_build_object('post_id', p.id, 'title', p.title, 'url', p.url,
                  'platform', p.platform, 'category', p.category, 'minutes', i.minutes, 'note', i.note) order by i.position)
                from public.session_item i join public.post p on p.id = i.post_id where i.session_id = s.id), '[]'::jsonb),
      'my_rating', (select jsonb_build_object('stars', r.stars, 'comment', r.comment) from public.session_rating r
                    where r.session_id = s.id and r.member_id = m.id),
      'rating_avg', (select round(avg(r.stars)::numeric, 1) from public.session_rating r where r.session_id = s.id),
      'rating_count', (select count(*) from public.session_rating r where r.session_id = s.id),
      'comments', case when m.role = 'coach' then (select coalesce(jsonb_agg(jsonb_build_object('stars', r.stars, 'comment', r.comment)
                  order by r.created_at desc), '[]'::jsonb) from public.session_rating r where r.session_id = s.id and r.comment is not null) end
    ) x
    from public.training_session s
    where s.team_id = m.team_id and (s.status = 'published' or m.role = 'coach')) q), '[]'::jsonb);
end $$;

grant execute on function save_session(text,uuid,text,timestamptz,int,text,text,jsonb), publish_session(text,uuid),
  delete_session(text,uuid), rate_session(text,uuid,int,text), list_sessions(text) to anon, authenticated;
revoke execute on function save_session(text,uuid,text,timestamptz,int,text,text,jsonb), publish_session(text,uuid),
  delete_session(text,uuid), rate_session(text,uuid,int,text), list_sessions(text) from public;
