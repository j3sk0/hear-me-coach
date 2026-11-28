# Hear Me Coach

Spieler finden Trainingsvideos auf TikTok, Instagram oder YouTube und teilen sie mit ihrer Mannschaft. Alle stimmen ab, ab einer Schwelle landet das Video beim Coach. Der Coach bewertet, nimmt Übungen ins Training auf, stellt Trainingseinheiten zusammen, und nach dem Training bewertet die Mannschaft die Einheit. Wer allein trainiert, nutzt den Solo-Modus als eigene Sammlung mit Statistik.

| | |
|---|---|
| **Web-App (live)** | https://j3sk0.github.io/hear-me-coach/ |
| **Datenbank** | Supabase-Projekt `hear-me-coach` (eu-central-1, Frankfurt) |
| **Native App** | `mobile/` (Expo, iOS und Android) – Einrichtung siehe [ANLEITUNG-APP.md](ANLEITUNG-APP.md) |
| **Lastenheft** | [SPEC.md](SPEC.md) |

## Funktionen

**Mannschaft**
- Mannschaft anlegen (Sportart wählbar, Farbe und Feldlinien je Sportart, Vereinsfarbe und -logo)
- Beitritt per Spieler-Code, Co-Trainer per Coach-Code
- Videos teilen: direkt aus TikTok/Instagram/YouTube (native App, Android-Web-App), per Link oder Einfügen-Knopf
- Kategorien (Aufwärmen, Technik, Spielform, Taktik, Abschluss, Kondition, Ausklang); neue Begriffe wachsen automatisch in die Liste
- Anonym teilen: Mitspieler sehen keinen Namen, der Coach immer
- Upvotes mit einstellbarer Schwelle; ab Schwelle Status „Beim Coach“
- Coach: Sterne, Notiz (privat oder für alle), Ins Training / Angeschaut / Ablehnen mit Grund
- Trainingsplan: Einheiten mit Datum, Ort, Übungen und Minuten; Entwurf oder veröffentlicht
- Bewertung nach dem Training (ab Trainingsbeginn), Durchschnitt für alle, Kommentare anonym für den Coach
- „✓ Gemacht“ für Übungen, persönliche Statistik (Tage, Wochen, Kategorien, Top 5)

**Solo-Modus**
- Eigene Sammlung ohne Coach, Kategorien nach Muskelgruppen, Sterne direkt auf der Karte, Favorit/Okay/Nicht meins, Sortierung, Statistik

**Einladen**
- QR-Code und Einladungslink (`…/hear-me-coach/?code=SPIELERCODE`) im Team-Bereich. Wer den Link öffnet, sieht den Mannschaftsnamen und gibt nur noch seinen Namen ein. Ohne gültigen Code vom Coach kommt niemand in eine Mannschaft.

**Mitglieder**
- Namen sind pro Mannschaft eindeutig. Ist ein Name vergeben, fragt die App „Bist du das?“ (dann mit Zugangscode anmelden) oder verlangt einen Zusatz wie Nachname, Initial oder Spitzname.
- Jeder kann seinen Anzeigenamen unter „Team → Mein Zugang“ ändern.
- Der Coach sieht unter „Team → Mitglieder“ alle Mitglieder mit Videos, Upvotes, Geräten und ob ein Zugangscode existiert. Gleiche Namen werden markiert. Doppelte Profile lassen sich zusammenführen (Videos, Upvotes, Bewertungen und angemeldete Geräte wandern mit), Mitglieder lassen sich entfernen.

**Konto und Geräte**
- Kein Passwort, keine E-Mail: Beim Beitreten gibt es einen persönlichen Zugangscode (`XXXX-XXXX-XXXX`), mit dem man sich auf jedem Gerät anmeldet. Das Speichern muss bestätigt werden. Mitglieder ohne gespeicherten Code werden in der App aufgefordert, einen zu sichern. Code erneuerbar, einzelne Geräte abmeldbar.

**Benachrichtigungen** (über die native App)
- Neues Video, Upvotes (gebündelt über 10 Minuten), Videos mit genug Upvotes (Coach, gebündelt), Video ins Training aufgenommen, neuer Trainingsplan, Erinnerung zur Bewertung nach dem Training, Ergebnis 24 Stunden später
- Jede Art einzeln abschaltbar, Nachtruhe 22–7 Uhr

## Aufbau

```
docs/                     Web-App (eine HTML-Datei, PWA mit Manifest, Service Worker, Share Target) – von GitHub Pages ausgeliefert
mobile/                   Native App (Expo SDK 58): WebView auf die Web-App + Teilen-Empfang + Push
  App.tsx                 Brücke zur Web-App (window.hmcNative.share / pushToken / open)
  app.json / app.config.js  App-Konfiguration, Teilen-Erweiterung, Icons
  plugins/                eigener Config-Plugin (Name der iOS-Teilen-Erweiterung)
  eas.json                Build-Profile (preview = APK, production = Stores)
supabase/migrations/      Datenbank-Schema und Funktionen in Reihenfolge 0001–0011
.github/workflows/        „App bauen“ (Expo-Cloud) und „Datenbank wach halten“ (alle 3 Tage)
SPEC.md                   Lastenheft
ANLEITUNG-APP.md          Konten anlegen, App bauen, verteilen
```

Die native App lädt die Web-App. Änderungen an der Web-App sind deshalb sofort auch in der App sichtbar. Nur Änderungen an nativen Teilen (Teilen-Empfang, Push, Icons, Name) brauchen einen neuen App-Build.

## Datenbank und Sicherheit

- Alle Tabellen sind für Clients gesperrt (Row Level Security ohne Policies). Zugriff nur über `SECURITY DEFINER`-Funktionen, die den persönlichen Schlüssel des Geräts prüfen (`member_token`, gespeichert als SHA-256).
- Zugangscodes und Teilen-Schlüssel werden nur als Hash gespeichert.
- Anonymität wird in der Datenbank durchgesetzt (`list_posts` liefert Spielern bei anonymen Beiträgen keinen Namen).
- Der Supabase-Schlüssel in der Web-App ist der öffentliche „publishable key“ und darf im Code stehen.

**Tabellen:** `team`, `member`, `member_token`, `post`, `upvote`, `coach_review`, `category`, `workout_log`, `training_session`, `session_item`, `session_rating`, `push_device`, `notify_pref`, `notification_outbox`

**API-Funktionen (RPC):**
| Bereich | Funktionen |
|---|---|
| Konto | `team_preview`, `create_team`, `join_team`, `rename_me`, `login_with_code`, `new_login_code`, `logout`, `whoami`, `leave_team` |
| Pool | `list_posts`, `add_post`, `toggle_upvote`, `delete_post`, `set_post_category` |
| Coach | `list_members`, `merge_members`, `remove_member`, `review_post`, `rate_post`, `set_threshold`, `set_team`, `set_team_style`, `add_category`, `delete_category` |
| Training | `list_sessions`, `save_session`, `publish_session`, `delete_session`, `rate_session`, `log_workout`, `undo_workout`, `list_my_log` |
| Teilen per Schlüssel | `new_share_key`, `share_link` |
| Benachrichtigungen | `register_push`, `unregister_push`, `get_notify_prefs`, `set_notify_prefs` |

**Benachrichtigungen intern:** Trigger auf `post`, `upvote` und `training_session` schreiben in `notification_outbox`. Ein `pg_cron`-Job (`hmc-send-push`, jede Minute) erzeugt Erinnerungen und Ergebnisse, beachtet Einstellungen und Nachtruhe und schickt fällige Nachrichten per `pg_net` an den Expo-Push-Dienst.

## Daten bleiben erhalten

Web-App, Demo-freie Live-Version und native App nutzen **dieselbe Datenbank**. Mannschaften, Mitglieder, Videos, Upvotes, Trainingspläne und Bewertungen werden beim Wechsel in die App übernommen. Jedes Mitglied meldet sich in der App einmal mit seinem Zugangscode an. Datenbank-Änderungen werden nur als neue Migrationen ergänzt, bestehende Daten werden dabei nicht gelöscht.

**Hinweis zum kostenlosen Supabase-Tarif:** Projekte werden nach etwa einer Woche ohne Aktivität pausiert (Daten bleiben erhalten und lassen sich wiederherstellen), und es gibt keine automatischen Backups. Der Workflow „Datenbank wach halten“ fragt deshalb alle 3 Tage die Datenbank ab. Für den produktiven Betrieb mit vielen Mannschaften empfiehlt sich der Pro-Tarif (tägliche Backups, keine Pausen).

## Entwicklung

- Web-App: `docs/index.html` direkt bearbeiten, lokal mit `python3 -m http.server` im Ordner `docs/` testen. Ohne Verbindung zur Datenbank (oder mit `?demo`) startet eine Demo mit Beispieldaten und Personen-Umschalter.
- Datenbank: neue Migration als `supabase/migrations/00NN_name.sql` anlegen und im Supabase-Projekt anwenden.
- App: `cd mobile && npm ci && npx tsc --noEmit`. Builds laufen in der Expo-Cloud, siehe [ANLEITUNG-APP.md](ANLEITUNG-APP.md).
