-- Names are unique per team (case-insensitive): a second "Malte" has to add a surname, initial or nickname.
-- Members can rename themselves.
create or replace function join_team(p_code text, p_name text, p_force boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare t public.team; m public.member; c text := upper(trim(p_code));
begin
  select * into t from public.team where (player_code = c or coach_code = c) and mode = 'team';
  if t.id is null then raise exception 'invalid_code'; end if;
  -- p_force is kept for older app versions but no longer allows duplicate names
  if exists (select 1 from public.member where team_id = t.id and lower(trim(name)) = lower(trim(p_name))) then
    raise exception 'name_taken';
  end if;
  insert into public.member (team_id, name, role)
  values (t.id, trim(p_name), case when t.coach_code = c then 'coach' else 'player' end) returning * into m;
  return public._session(m, true);
end $$;

create or replace function rename_me(p_token text, p_name text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token); n text := trim(coalesce(p_name, ''));
begin
  if length(n) < 1 or length(n) > 40 then raise exception 'invalid_name'; end if;
  if exists (select 1 from public.member where team_id = m.team_id and id <> m.id and lower(trim(name)) = lower(n)) then
    raise exception 'name_taken';
  end if;
  update public.member set name = n where id = m.id;
end $$;

revoke execute on function rename_me(text,text) from public;
grant execute on function rename_me(text,text) to anon, authenticated;
