-- Seeded categories keep their training order (Aufwärmen first, Ausklang last).
create or replace function _seed_categories(p_team uuid) returns void
language sql volatile security definer set search_path = '' as $$
  insert into public.category (team_id, name, created_at)
  select p_team, n, now() + make_interval(secs => i / 1000.0)
  from unnest(array['Aufwärmen','Technik','Spielform','Taktik','Abschluss','Kondition','Ausklang']) with ordinality as x(n, i)
  on conflict do nothing
$$;
-- create_team: solo categories seeded the same way (see Supabase project for full function body)
revoke execute on function _seed_categories(uuid) from public, anon, authenticated;
