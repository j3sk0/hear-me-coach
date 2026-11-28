-- Invitation link (?code=XXXXXX): shows which team you are about to join before entering your name.
-- Only answers for valid team codes, returns nothing secret.
create or replace function team_preview(p_code text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('name', t.name, 'sport', t.sport, 'color', t.color, 'logo', t.logo,
           'role', case when t.coach_code = upper(trim(p_code)) then 'coach' else 'player' end,
           'members', (select count(*) from public.member m where m.team_id = t.id))
  from public.team t
  where t.mode = 'team' and (t.player_code = upper(trim(p_code)) or t.coach_code = upper(trim(p_code)))
$$;
revoke execute on function team_preview(text) from public;
grant execute on function team_preview(text) to anon, authenticated;
