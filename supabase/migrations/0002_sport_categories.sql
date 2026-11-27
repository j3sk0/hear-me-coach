-- Sport per team, categories per team (grow automatically when someone types a new one).

alter table team add column sport text not null default 'Allgemein' check (length(sport) between 1 and 40);
alter table post add column category text check (length(category) <= 30);

create table category (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references team(id) on delete cascade,
  name text not null check (length(name) between 1 and 30),
  created_at timestamptz not null default now()
);
create unique index category_team_name on category (team_id, lower(name));
alter table category enable row level security;
revoke all on category from anon, authenticated;

create or replace function _seed_categories(p_team uuid) returns void
language sql volatile security definer set search_path = '' as $$
  insert into public.category (team_id, name)
  select p_team, n from unnest(array['Aufwärmen','Technik','Spielform','Taktik','Abschluss','Kondition','Ausklang']) n
  on conflict do nothing
$$;
select public._seed_categories(id) from public.team;

create or replace function _clean_cat(c text) returns text
language sql immutable set search_path = '' as $$
  select nullif(left(regexp_replace(trim(coalesce(c,'')), '\s+', ' ', 'g'), 30), '')
$$;

-- returns the stored spelling, adding the category to the team list if new
create or replace function _ensure_category(p_team uuid, p_name text) returns text
language plpgsql volatile security definer set search_path = '' as $$
declare n text := public._clean_cat(p_name); existing text;
begin
  if n is null then return null; end if;
  select name into existing from public.category where team_id = p_team and lower(name) = lower(n);
  if existing is not null then return existing; end if;
  if (select count(*) from public.category where team_id = p_team) >= 60 then raise exception 'too_many_categories'; end if;
  insert into public.category (team_id, name) values (p_team, n);
  return n;
end $$;

create or replace function _member_json(m public.member) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'member_id', m.id, 'name', m.name, 'role', m.role,
    'team', jsonb_build_object('id', t.id, 'name', t.name, 'sport', t.sport,
      'threshold', t.upvote_threshold,
      'player_code', t.player_code,
      'coach_code', case when m.role = 'coach' then t.coach_code end,
      'categories', coalesce((select jsonb_agg(c.name order by c.created_at, c.name)
                              from public.category c where c.team_id = t.id), '[]'::jsonb)))
  from public.team t where t.id = m.team_id
$$;

drop function create_team(text, text);
create or replace function create_team(p_team_name text, p_coach_name text, p_sport text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare t public.team; m public.member;
        tok text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  insert into public.team (name, player_code, coach_code, sport)
  values (trim(p_team_name), public._code(), public._code(),
          coalesce(nullif(left(trim(p_sport), 40), ''), 'Allgemein')) returning * into t;
  perform public._seed_categories(t.id);
  insert into public.member (team_id, name, role, token_hash)
  values (t.id, trim(p_coach_name), 'coach', public._hash(tok)) returning * into m;
  return public._member_json(m) || jsonb_build_object('token', tok);
end $$;

drop function add_post(text, text, text, text, text, boolean);
create or replace function add_post(p_token text, p_url text, p_title text,
  p_thumbnail_url text, p_comment text, p_anonymous boolean, p_category text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
        u text := trim(p_url); k text; existing uuid; new_id uuid; cat text;
begin
  if u !~* '^https?://[^\s]+$' then raise exception 'invalid_url'; end if;
  k := public._url_key(u);
  select id into existing from public.post where team_id = m.team_id and url_key = k;
  if existing is not null then
    return jsonb_build_object('id', existing, 'duplicate', true);
  end if;
  cat := public._ensure_category(m.team_id, p_category);
  insert into public.post (team_id, submitter_id, url, url_key, platform,
                           title, thumbnail_url, comment, anonymous, category)
  values (m.team_id, m.id, u, k, public._platform(u),
          nullif(left(trim(p_title), 200), ''),
          case when p_thumbnail_url ~* '^https://' then left(p_thumbnail_url, 2000) end,
          nullif(left(trim(p_comment), 500), ''),
          coalesce(p_anonymous, false), cat)
  returning id into new_id;
  return jsonb_build_object('id', new_id, 'duplicate', false);
end $$;

-- coach can re-file a post
create or replace function set_post_category(p_token text, p_post_id uuid, p_category text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token); cat text;
begin
  if not exists (select 1 from public.post where id = p_post_id and team_id = m.team_id
                 and (submitter_id = m.id or m.role = 'coach')) then raise exception 'not_allowed'; end if;
  cat := public._ensure_category(m.team_id, p_category);
  update public.post set category = cat where id = p_post_id;
end $$;

create or replace function set_team(p_token text, p_name text, p_sport text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  update public.team set
    name = coalesce(nullif(left(trim(p_name), 80), ''), name),
    sport = coalesce(nullif(left(trim(p_sport), 40), ''), sport)
  where id = m.team_id;
end $$;

create or replace function add_category(p_token text, p_name text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  perform public._ensure_category(m.team_id, p_name);
end $$;

-- removes the category from the list; posts keep their label
create or replace function delete_category(p_token text, p_name text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  delete from public.category where team_id = m.team_id and lower(name) = lower(trim(p_name));
end $$;

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
grant execute on function create_team(text,text,text), join_team(text,text), whoami(text),
  list_posts(text), add_post(text,text,text,text,text,boolean,text), toggle_upvote(text,uuid),
  delete_post(text,uuid), review_post(text,uuid,text,int,text,boolean,text),
  set_threshold(text,int), leave_team(text), set_post_category(text,uuid,text),
  set_team(text,text,text), add_category(text,text), delete_category(text,text)
  to anon, authenticated;
