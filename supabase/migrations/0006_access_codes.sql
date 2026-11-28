-- Persistent identity without e-mail:
--  * every member gets a personal access code (shown once, can be renewed) to sign in on any device
--  * one member can be signed in on several devices (member_token)
--  * a separate share key lets an iPhone shortcut drop links into the pool (can only add posts)

create table member_token (
  token_hash text primary key,
  member_id uuid not null references member(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index on member_token (member_id);
alter table member_token enable row level security;
revoke all on member_token from anon, authenticated;
insert into member_token (token_hash, member_id) select token_hash, id from member;
alter table member alter column token_hash drop not null;

alter table member add column login_code_hash text unique;
alter table member add column share_key_hash text unique;

create or replace function _me(p_token text) returns public.member
language plpgsql stable security definer set search_path = '' as $$
declare m public.member;
begin
  select mb.* into m from public.member_token t join public.member mb on mb.id = t.member_id
   where t.token_hash = public._hash(p_token);
  if m.id is null then raise exception 'not_authorized'; end if;
  return m;
end $$;

-- 12 characters from a 32-letter alphabet without look-alikes (60 bits), shown as XXXX-XXXX-XXXX
create or replace function _login_code() returns text
language sql volatile set search_path = '' as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + (get_byte(b, i) % 32), 1)
                    || case when i in (3, 7) then '-' else '' end, '')
  from (select extensions.gen_random_bytes(12) b) x, generate_series(0, 11) i
$$;
create or replace function _norm_code(c text) returns text
language sql immutable set search_path = '' as $$
  select upper(regexp_replace(coalesce(c, ''), '[^A-Za-z0-9]', '', 'g'))
$$;

-- issues a device token and a fresh access code for member m
create or replace function _session(m public.member, with_code boolean) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare tok text := encode(extensions.gen_random_bytes(24), 'hex'); code text;
begin
  insert into public.member_token (token_hash, member_id) values (public._hash(tok), m.id);
  if with_code then
    code := public._login_code();
    update public.member set login_code_hash = public._hash(public._norm_code(code)) where id = m.id;
  end if;
  return public._member_json(m) || jsonb_build_object('token', tok, 'login_code', code);
end $$;

create or replace function create_team(p_team_name text, p_coach_name text, p_sport text, p_mode text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare t public.team; m public.member;
        md text := case when p_mode = 'solo' then 'solo' else 'team' end;
begin
  insert into public.team (name, player_code, coach_code, sport, mode)
  values (trim(p_team_name), public._code(), public._code(),
          coalesce(nullif(left(trim(p_sport), 40), ''), 'Allgemein'), md) returning * into t;
  if md = 'solo' then
    insert into public.category (team_id, name, created_at)
    select t.id, n, now() + make_interval(secs => i / 1000.0)
    from unnest(array['Aufwärmen','Brust','Rücken','Schultern','Arme','Beine','Core','Cardio','Dehnen']) with ordinality as x(n, i);
  else
    perform public._seed_categories(t.id);
  end if;
  insert into public.member (team_id, name, role) values (t.id, trim(p_coach_name), 'coach') returning * into m;
  return public._session(m, true);
end $$;

create or replace function join_team(p_code text, p_name text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare t public.team; m public.member; c text := upper(trim(p_code));
begin
  select * into t from public.team where (player_code = c or coach_code = c) and mode = 'team';
  if t.id is null then raise exception 'invalid_code'; end if;
  insert into public.member (team_id, name, role)
  values (t.id, trim(p_name), case when t.coach_code = c then 'coach' else 'player' end) returning * into m;
  return public._session(m, true);
end $$;

-- sign in on another device (or inside the installed app) with the personal access code
create or replace function login_with_code(p_code text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m public.member;
begin
  if length(public._norm_code(p_code)) <> 12 then raise exception 'invalid_login'; end if;
  select * into m from public.member where login_code_hash = public._hash(public._norm_code(p_code));
  if m.id is null then raise exception 'invalid_login'; end if;
  return public._session(m, false);
end $$;

-- replace my access code (old one stops working; signed-in devices stay signed in)
create or replace function new_login_code(p_token text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token); code text := public._login_code();
begin
  update public.member set login_code_hash = public._hash(public._norm_code(code)) where id = m.id;
  return code;
end $$;

-- share key for the iPhone shortcut; can only add posts
create or replace function new_share_key(p_token text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare m public.member := public._me(p_token); k text := 'hmc_' || encode(extensions.gen_random_bytes(18), 'hex');
begin
  update public.member set share_key_hash = public._hash(k) where id = m.id;
  return k;
end $$;

-- called by the shortcut: text may be the shared URL or a caption containing it
create or replace function share_link(p_key text, p_text text, p_anonymous boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m public.member; tok text := encode(extensions.gen_random_bytes(24), 'hex');
        u text := substring(coalesce(p_text, '') from 'https?://[^\s"''<>]+'); r jsonb;
begin
  select * into m from public.member where share_key_hash = public._hash(trim(coalesce(p_key, '')));
  if m.id is null then raise exception 'invalid_key'; end if;
  if u is null then raise exception 'invalid_url'; end if;
  -- short-lived internal token so add_post's checks apply unchanged
  insert into public.member_token (token_hash, member_id) values (public._hash(tok), m.id);
  r := public.add_post(tok, u, null, null, null, coalesce(p_anonymous, false), null);
  delete from public.member_token where token_hash = public._hash(tok);
  return r || jsonb_build_object('message',
    case when (r->>'duplicate')::boolean then 'Ist schon im Pool – gib ihm ein Upvote!' else 'Im Pool! Jetzt brauchst du Upvotes.' end);
end $$;

-- sign out this device only
create or replace function logout(p_token text)
returns void language sql volatile security definer set search_path = '' as $$
  delete from public.member_token where token_hash = public._hash(p_token)
$$;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function create_team(text,text,text,text), join_team(text,text), whoami(text),
  list_posts(text), add_post(text,text,text,text,text,boolean,text), toggle_upvote(text,uuid),
  delete_post(text,uuid), review_post(text,uuid,text,int,text,boolean,text),
  set_threshold(text,int), leave_team(text), set_post_category(text,uuid,text),
  set_team(text,text,text), add_category(text,text), delete_category(text,text),
  rate_post(text,uuid,int), log_workout(text,uuid,text), undo_workout(text,uuid), list_my_log(text),
  set_team_style(text,text,text), login_with_code(text), new_login_code(text), new_share_key(text),
  share_link(text,text,boolean), logout(text)
  to anon, authenticated;
