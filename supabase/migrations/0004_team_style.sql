alter table team add column color text check (color ~ '^#[0-9a-fA-F]{6}$');
alter table team add column logo text check (length(logo) <= 200000 and logo ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$');

create or replace function _member_json(m public.member) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'member_id', m.id, 'name', m.name, 'role', m.role,
    'team', jsonb_build_object('id', t.id, 'name', t.name, 'sport', t.sport, 'mode', t.mode,
      'color', t.color, 'logo', t.logo,
      'threshold', t.upvote_threshold,
      'player_code', case when t.mode = 'team' then t.player_code end,
      'coach_code', case when m.role = 'coach' and t.mode = 'team' then t.coach_code end,
      'categories', coalesce((select jsonb_agg(c.name order by c.created_at, c.name)
                              from public.category c where c.team_id = t.id), '[]'::jsonb)))
  from public.team t where t.id = m.team_id
$$;

-- p_color / p_logo: '' clears, null keeps
create or replace function set_team_style(p_token text, p_color text, p_logo text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token);
begin
  if m.role <> 'coach' then raise exception 'coach_only'; end if;
  update public.team set
    color = case when p_color is null then color when p_color = '' then null else p_color end,
    logo  = case when p_logo  is null then logo  when p_logo  = '' then null else p_logo  end
  where id = m.team_id;
end $$;

revoke execute on function set_team_style(text,text,text) from public;
grant execute on function set_team_style(text,text,text) to anon, authenticated;
