# Hear Me Coach – Beta

Spieler teilen Trainingsvideos (TikTok, Instagram, YouTube, Facebook) als Link in den Pool ihrer Mannschaft.
Mitspieler upvoten. Ab der Schwelle landet der Beitrag beim Coach, der bewertet, Notizen macht und ihn ins Training aufnimmt.

## Aufbau
- `docs/` – PWA (eine HTML-Datei, Manifest mit Share Target, Service Worker, Icons). Keine Build-Schritte.
- `supabase/migrations/0001_init.sql` – Datenbank. Bereits angewendet auf Projekt `hear-me-coach` (eu-central-1).
- `SPEC.md` – Lastenheft.

## Zugang (Beta)
Kein Passwort: Coach legt Mannschaft an und bekommt Spieler-Code und Co-Trainer-Code.
Wer mit Code beitritt, bekommt einen persönlichen Schlüssel, gespeichert im Browser.
Alle Daten laufen über Datenbank-Funktionen, die den Schlüssel prüfen. Tabellen sind für Clients gesperrt.
Anonymität wird in der Datenbank durchgesetzt: Spieler bekommen bei anonymen Beiträgen keinen Namen geliefert.

## Demo
Ohne Verbindung zu Supabase (oder mit `?demo`) startet die App mit Beispieldaten und einem Personen-Umschalter.

## Veröffentlichen
Der Ordner `docs/` muss über HTTPS erreichbar sein (für Installation und Teilen-Menü), z. B.:
- GitHub Pages, Cloudflare Pages oder Netlify: Ordner `docs/` hochladen.
- Eigener Server: beliebiger Webserver mit TLS, z. B. Caddy:
  `docker run -d -p 443:443 -v $PWD/app:/srv caddy caddy file-server --domain coach.example.de --root /srv`

## Bekannte Grenzen der Beta
- Ohne Passwort: Wer den Browser-Speicher löscht, muss neu beitreten (neues Profil).
- iPhone: Kein Eintrag im Teilen-Menü (Einschränkung von iOS für Web-Apps), Link kopieren und einfügen.
- Vorschaubilder: TikTok und YouTube automatisch, Instagram nur als Linkkarte.
- Kein Telegram-Bot und keine Push-Nachrichten.

## Live
GitHub Pages veröffentlicht den Ordner `docs/` unter https://j3sk0.github.io/hear-me-coach/
