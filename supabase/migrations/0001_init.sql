-- Hear Me Coach, beta schema.
-- Access model: no direct table access for clients. Everything goes through
-- SECURITY DEFINER functions that take a member token (issued on join).
-- Anonymity is enforced here: submitter names are only returned to coaches.

create extension if not exists pgcrypto with schema extensions;

create table team (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(name) between 1 and 80),
  player_code text not null unique,
  coach_code text not null unique,
  upvote_threshold int not null default 5 check (upvote_threshold between 1 and 100),
  created_at timestamptz not null default now()
);

create table member (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references team(id) on delete cascade,
  name text not null check (length(name) between 1 and 40),
  role text not null check (role in ('player','coach')),
  token_hash text not null unique,
  created_at timestamptz not null default now()
);

create table post (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references team(id) on delete cascade,
  submitter_id uuid references member(id) on delete set null,
  url text not null check (length(url) <= 2000),
  url_key text not null,
  platform text not null,
  title text check (length(title) <= 200),
  thumbnail_url text check (length(thumbnail_url) <= 2000),
  comment text check (length(comment) <= 500),
  anonymous boolean not null default false,
  status text not null default 'new'
    check (status in ('new','relevant','seen','adopted','rejected')),
  created_at timestamptz not null default now(),
  unique (team_id, url_key)
);

create table upvote (
  post_id uuid not null references post(id) on delete cascade,
  member_id uuid not null references member(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, member_id)
);

create table coach_review (
  post_id uuid primary key references post(id) on delete cascade,
  coach_id uuid references member(id) on delete set null,
  stars int check (stars between 1 and 5),
  note text check (length(note) <= 2000),
  note_public boolean not null default false,
  reason text check (length(reason) <= 300),
  updated_at timestamptz not null default now()
);

create index on post (team_id, created_at desc);
create index on upvote (post_id);
create index on upvote (member_id);
create index on member (team_id);
create index on post (submitter_id);
create index on coach_review (coach_id);

-- Lock tables: RLS on, no policies => anon/authenticated cannot touch them.
alter table team enable row level security;
alter table member enable row level security;
alter table post enable row level security;
alter table upvote enable row level security;
alter table coach_review enable row level security;
revoke all on team, member, post, upvote, coach_review from anon, authenticated;

-- ---------- helpers ----------

create or replace function _code() returns text
language sql volatile set search_path = '' as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
         1 + (get_byte(b, i) % 32), 1), '')
  from (select extensions.gen_random_bytes(6) b) x, generate_series(0,5) i
$$;

create or replace function _hash(t text) returns text
language sql immutable set search_path = '' as $$
  select encode(extensions.digest(t, 'sha256'), 'hex')
$$;

create or replace function _me(p_token text) returns public.member
language plpgsql stable security definer set search_path = '' as $$
declare m public.member;
begin
  select * into m from public.member where token_hash = public._hash(p_token);
  if m.id is null then raise exception 'not_authorized'; end if;
  return m;
end $$;

create or replace function _platform(u text) returns text
language sql immutable set search_path = '' as $$
  select case
    when u ~* '^https?://([a-z0-9-]+\.)*tiktok\.com' then 'tiktok'
    when u ~* '^https?://([a-z0-9-]+\.)*instagram\.com' then 'instagram'
    when u ~* '^https?://([a-z0-9-]+\.)*(youtube\.com|youtu\.be)' then 'youtube'
    when u ~* '^https?://([a-z0-9-]+\.)*(facebook\.com|fb\.watch)' then 'facebook'
    else 'web' end
$$;

create or replace function _url_key(u text) returns text
language plpgsql immutable set search_path = '' as $$
declare yt text;
begin
  yt := coalesce(
    substring(u from 'youtu\.be/([A-Za-z0-9_-]{6,})'),
    substring(u from '[?&]v=([A-Za-z0-9_-]{6,})'),
    substring(u from '/shorts/([A-Za-z0-9_-]{6,})'));
  if yt is not null then return 'youtube:' || yt; end if;
  -- drop query/fragment (tracking params), www., trailing slash
  return regexp_replace(
           regexp_replace(lower(split_part(split_part(u, '#', 1), '?', 1)),
                          '^https?://(www\.|m\.)?', ''),
           '/+$', '');
end $$;

create or replace function _member_json(m public.member) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'member_id', m.id, 'name', m.name, 'role', m.role,
    'team', jsonb_build_object('id', t.id, 'name', t.name,
      'threshold', t.upvote_threshold,
      'player_code', t.player_code,
      'coach_code', case when m.role = 'coach' then t.coach_code end))
  from public.team t where t.id = m.team_id
$$;

-- ---------- API ----------

create or replace function create_team(p_team_name text, p_coach_name text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare t public.team; m public.member;
        tok text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  insert into public.team (name, player_code, coach_code)
  values (trim(p_team_name), public._code(), public._code()) returning * into t;
  insert into public.member (team_id, name, role, token_hash)
  values (t.id, trim(p_coach_name), 'coach', public._hash(tok)) returning * into m;
  return public._member_json(m) || jsonb_build_object('token', tok);
end $$;

create or replace function join_team(p_code text, p_name text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare t public.team; r text; m public.member;
        tok text := encode(extensions.gen_random_bytes(24), 'hex');
        c text := upper(trim(p_code));
begin
  select * into t from public.team where player_code = c or coach_code = c;
  if t.id is null then raise exception 'invalid_code'; end if;
  r := case when t.coach_code = c then 'coach' else 'player' end;
  insert into public.member (team_id, name, role, token_hash)
  values (t.id, trim(p_name), r, public._hash(tok)) returning * into m;
  return public._member_json(m) || jsonb_build_object('token', tok);
end $$;

create or replace function whoami(p_token text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select public._member_json(public._me(p_token))
$$;

create or replace function list_posts(p_token text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  return coalesce((
    select jsonb_agg(row_to_json(x) order by x.created_at desc)
    from (
      select p.id, p.url, p.platform, p.title, p.thumbnail_url, p.comment,
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

create or replace function add_post(p_token text, p_url text, p_title text,
  p_thumbnail_url text, p_comment text, p_anonymous boolean)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
        u text := trim(p_url); k text; existing uuid; new_id uuid;
begin
  if u !~* '^https?://[^\s]+$' then raise exception 'invalid_url'; end if;
  k := public._url_key(u);
  select id into existing from public.post where team_id = m.team_id and url_key = k;
  if existing is not null then
    return jsonb_build_object('id', existing, 'duplicate', true);
  end if;
  insert into public.post (team_id, submitter_id, url, url_key, platform,
                           title, thumbnail_url, comment, anonymous)
  values (m.team_id, m.id, u, k, public._platform(u),
          nullif(left(trim(p_title), 200), ''),
          case when p_thumbnail_url ~* '^https://' then left(p_thumbnail_url, 2000) end,
          nullif(left(trim(p_comment), 500), ''),
          coalesce(p_anonymous, false))
  returning id into new_id;
  return jsonb_build_object('id', new_id, 'duplicate', false);
end $$;

create or replace function toggle_upvote(p_token text, p_post_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token); p public.post; n int; th int;
begin
  select * into p from public.post where id = p_post_id and team_id = m.team_id;
  if p.id is null then raise exception 'not_found'; end if;
  if p.submitter_id = m.id then raise exception 'own_post'; end if;
  if exists(select 1 from public.upvote where post_id = p.id and member_id = m.id) then
    delete from public.upvote where post_id = p.id and member_id = m.id;
  else
    insert into public.upvote (post_id, member_id) values (p.id, m.id);
  end if;
  select count(*) into n from public.upvote where post_id = p.id;
  select upvote_threshold into th from public.team where id = m.team_id;
  -- promote once threshold is reached; never demote coach decisions
  if p.status = 'new' and n >= th then
    update public.post set status = 'relevant' where id = p.id;
  end if;
  return jsonb_build_object('upvotes', n);
end $$;

create or replace function delete_post(p_token text, p_post_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  delete from public.post where id = p_post_id and team_id = m.team_id
    and (submitter_id = m.id or m.role = 'coach');
  if not found then raise exception 'not_allowed'; end if;
end $$;

create or replace function review_post(p_token text, p_post_id uuid, p_status text,
  p_stars int, p_note text, p_note_public boolean, p_reason text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  update public.post set status = p_status
   where id = p_post_id and team_id = m.team_id;
  if not found then raise exception 'not_found'; end if;
  insert into public.coach_review (post_id, coach_id, stars, note, note_public, reason, updated_at)
  values (p_post_id, m.id, p_stars, nullif(trim(p_note), ''), coalesce(p_note_public, false),
          nullif(trim(p_reason), ''), now())
  on conflict (post_id) do update set coach_id = excluded.coach_id, stars = excluded.stars,
    note = excluded.note, note_public = excluded.note_public, reason = excluded.reason,
    updated_at = now();
end $$;

create or replace function set_threshold(p_token text, p_threshold int)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  update public.team set upvote_threshold = p_threshold where id = m.team_id;
  -- apply new threshold to waiting posts
  update public.post p set status = 'relevant'
   where p.team_id = m.team_id and p.status = 'new'
     and (select count(*) from public.upvote u where u.post_id = p.id) >= p_threshold;
end $$;

create or replace function leave_team(p_token text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  delete from public.post where submitter_id = m.id;
  delete from public.member where id = m.id;
end $$;

-- Expose only the API functions.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function create_team(text,text), join_team(text,text), whoami(text),
  list_posts(text), add_post(text,text,text,text,text,boolean), toggle_upvote(text,uuid),
  delete_post(text,uuid), review_post(text,uuid,text,int,text,boolean,text),
  set_threshold(text,int), leave_team(text) to anon, authenticated;
