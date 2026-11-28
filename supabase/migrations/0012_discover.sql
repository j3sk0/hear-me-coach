-- "Entdecken": what is popular across all teams of the same sport.
-- Only aggregates are shown (no member names, no team names, no comments or notes).
-- Teams take part by default; the coach can switch it off (team.share_discover).

alter table team add column share_discover boolean not null default true;

create index if not exists post_url_key_idx on post (url_key);

-- p_sport: null = my team's sport; p_days: time window (null = all time); p_sort: 'popular' | 'training' | 'new'
create or replace function discover(p_token text, p_sport text default null, p_days int default 30, p_sort text default 'popular')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m public.member := public._me(p_token); sp text; since timestamptz;
begin
  select coalesce(nullif(trim(p_sport), ''), t.sport) into sp from public.team t where t.id = m.team_id;
  since := case when p_days is null then '-infinity'::timestamptz else now() - make_interval(days => p_days) end;
  return coalesce((
    with ps as (
      select p.*, (select count(*) from public.upvote u where u.post_id = p.id) as ups,
             (select count(*) from public.workout_log l where l.post_id = p.id) as dones,
             (select r.stars from public.coach_review r where r.post_id = p.id) as stars
      from public.post p join public.team t on t.id = p.team_id
      where t.mode = 'team' and lower(t.sport) = lower(sp) and (t.share_discover or t.id = m.team_id)
        and p.created_at >= since and p.status <> 'rejected'),
    agg as (
      select url_key,
             (array_agg(url order by created_at))[1] as url,
             (array_agg(platform order by created_at))[1] as platform,
             (array_agg(title order by (title is null), created_at))[1] as title,
             (array_agg(thumbnail_url order by (thumbnail_url is null), created_at desc))[1] as thumbnail_url,
             mode() within group (order by category) as category,
             count(distinct team_id)::int as teams,
             sum(ups)::int as upvotes,
             count(distinct team_id) filter (where status = 'adopted')::int as adopted_teams,
             sum(dones)::int as done,
             round(avg(stars)::numeric, 1) as coach_stars,
             max(created_at) as last_shared,
             bool_or(team_id = m.team_id) as in_my_team
      from ps group by url_key),
    ranked as (
      select *, case p_sort when 'training' then adopted_teams * 10 + done
                            when 'new' then extract(epoch from last_shared)
                            else upvotes + adopted_teams * 3 + (teams - 1) * 2 end as score
      from agg where upvotes > 0 or adopted_teams > 0 or teams > 1
      order by score desc, last_shared desc limit 100)
    select jsonb_agg(to_jsonb(r) - 'url_key' - 'score' order by r.score desc, r.last_shared desc) from ranked r), '[]'::jsonb);
end $$;

-- which sports have shared content (for the sport picker)
create or replace function discover_sports(p_token text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('sport', s, 'teams', n) order by n desc, s), '[]'::jsonb) from (
    select t.sport s, count(distinct t.id)::int n from public.team t
    where t.mode = 'team' and t.share_discover and exists (select 1 from public.post p where p.team_id = t.id)
    group by t.sport) q
  where (public._me(p_token)).id is not null
$$;

create or replace function set_share_discover(p_token text, p_on boolean)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  update public.team set share_discover = coalesce(p_on, true) where id = m.team_id;
end $$;

create or replace function _member_json(m public.member) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'member_id', m.id, 'name', m.name, 'role', m.role,
    'team', jsonb_build_object('id', t.id, 'name', t.name, 'sport', t.sport, 'mode', t.mode,
      'color', t.color, 'logo', t.logo, 'share_discover', t.share_discover,
      'threshold', t.upvote_threshold,
      'player_code', case when t.mode = 'team' then t.player_code end,
      'coach_code', case when m.role = 'coach' and t.mode = 'team' then t.coach_code end,
      'categories', coalesce((select jsonb_agg(c.name order by c.created_at, c.name)
                              from public.category c where c.team_id = t.id), '[]'::jsonb)))
  from public.team t where t.id = m.team_id
$$;

revoke execute on function discover(text,text,int,text), discover_sports(text), set_share_discover(text,boolean) from public;
grant execute on function discover(text,text,int,text), discover_sports(text), set_share_discover(text,boolean) to anon, authenticated;
