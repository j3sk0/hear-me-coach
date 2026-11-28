-- Duplicate members (e.g. joined twice on an iPhone: once in Safari, once in the installed app).
--  * join_team warns when the name already exists in the team (p_force = true to join anyway)
--  * coaches can list members, merge a duplicate into the real profile, or remove a member

-- moves everything from p_drop to p_keep (same team), then deletes p_drop
create or replace function _merge_members(p_keep uuid, p_drop uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare k public.member; d public.member;
begin
  select * into k from public.member where id = p_keep;
  select * into d from public.member where id = p_drop;
  if k.id is null or d.id is null or k.team_id <> d.team_id or k.id = d.id then raise exception 'not_found'; end if;
  update public.member_token set member_id = k.id where member_id = d.id;
  update public.push_device set member_id = k.id where member_id = d.id;
  update public.post set submitter_id = k.id where submitter_id = d.id;
  -- upvotes: keep one per post; the kept profile cannot upvote its own (now merged) posts
  insert into public.upvote (post_id, member_id, created_at)
    select u.post_id, k.id, u.created_at from public.upvote u join public.post p on p.id = u.post_id
    where u.member_id = d.id and p.submitter_id is distinct from k.id
    on conflict do nothing;
  delete from public.upvote where member_id = d.id;
  delete from public.upvote u using public.post p where u.post_id = p.id and u.member_id = k.id and p.submitter_id = k.id;
  update public.coach_review set coach_id = k.id where coach_id = d.id;
  update public.training_session set created_by = k.id where created_by = d.id;
  update public.workout_log set member_id = k.id where member_id = d.id;
  insert into public.session_rating (session_id, member_id, stars, comment, created_at)
    select session_id, k.id, stars, comment, created_at from public.session_rating where member_id = d.id
    on conflict do nothing;
  delete from public.session_rating where member_id = d.id;
  -- the kept profile gets the higher role; keep its access code, else take the other one
  delete from public.member where id = d.id;  -- free unique code/key hashes before copying them
  update public.member set
    role = case when d.role = 'coach' then 'coach' else k.role end,
    login_code_hash = coalesce(k.login_code_hash, d.login_code_hash),
    share_key_hash = coalesce(k.share_key_hash, d.share_key_hash)
  where id = k.id;
end $$;

drop function join_team(text, text);
create or replace function join_team(p_code text, p_name text, p_force boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare t public.team; m public.member; c text := upper(trim(p_code));
begin
  select * into t from public.team where (player_code = c or coach_code = c) and mode = 'team';
  if t.id is null then raise exception 'invalid_code'; end if;
  if not coalesce(p_force, false) and exists (select 1 from public.member where team_id = t.id and lower(trim(name)) = lower(trim(p_name))) then
    raise exception 'name_taken';
  end if;
  insert into public.member (team_id, name, role)
  values (t.id, trim(p_name), case when t.coach_code = c then 'coach' else 'player' end) returning * into m;
  return public._session(m, true);
end $$;

create or replace function list_members(p_token text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', x.id, 'name', x.name, 'role', x.role, 'joined', x.created_at, 'me', x.id = m.id,
      'has_code', x.login_code_hash is not null,
      'devices', (select count(*) from public.member_token t where t.member_id = x.id),
      'push', (select count(*) from public.push_device d where d.member_id = x.id) > 0,
      'videos', (select count(*) from public.post p where p.submitter_id = x.id),
      'upvotes', (select count(*) from public.upvote u where u.member_id = x.id),
      'last_active', (select max(t.created_at) from public.member_token t where t.member_id = x.id)
    ) order by lower(x.name), x.created_at) from public.member x where x.team_id = m.team_id), '[]'::jsonb);
end $$;

create or replace function merge_members(p_token text, p_keep uuid, p_drop uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  if not exists (select 1 from public.member where id = p_keep and team_id = m.team_id)
     or not exists (select 1 from public.member where id = p_drop and team_id = m.team_id) then raise exception 'not_found'; end if;
  perform public._merge_members(p_keep, p_drop);
end $$;

create or replace function remove_member(p_token text, p_member uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  if p_member = m.id then raise exception 'not_allowed'; end if;
  delete from public.member where id = p_member and team_id = m.team_id;
  if not found then raise exception 'not_found'; end if;
end $$;

revoke execute on function _merge_members(uuid,uuid) from public, anon, authenticated;
revoke execute on function join_team(text,text,boolean), list_members(text), merge_members(text,uuid,uuid), remove_member(text,uuid) from public;
grant execute on function join_team(text,text,boolean), list_members(text), merge_members(text,uuid,uuid), remove_member(text,uuid) to anon, authenticated;
