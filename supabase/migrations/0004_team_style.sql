alter table team add column color text check (color ~ '^#[0-9a-fA-F]{6}$');
alter table team add column logo text check (length(logo) <= 200000 and logo ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$');
-- _member_json now also returns color and logo; set_team_style(token, color, logo): '' clears, null keeps. Coach only.
