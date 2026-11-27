# Hear Me Coach: Lastenheft (Prototyp / Beta)

Name: **Hear Me Coach** (Kurzform: Coach). Der Name ist noch nicht rechtlich geprüft (Marke DPMA/EUIPO, Domains hearmecoach.de/.com/.app, ggf. heremecoach).

**Idee:** Spieler finden Trainingsvideos bei Instagram, TikTok, YouTube oder Facebook und teilen den Link direkt aus der jeweiligen App an Hear Me Coach. Der Link landet im Pool der Mannschaft. Alle können sichten und upvoten. Ab einer Schwelle wird der Coach darauf aufmerksam, bewertet den Beitrag und nimmt ihn eventuell in seine Trainingsmethoden auf.

Alles, was hier nicht im Prototyp-Umfang steht, ist Phase 2 oder 3.

---

## 1. Phasen

| Phase | Inhalt |
|---|---|
| **1 Prototyp** | Links teilen (mehrere Wege), Pool, Upvote, Schwelle, anonym oder offen, Coach-Ansicht mit Bewertung und Notiz |
| **2** | Favoriten, Trainingseinheiten zusammenstellen und veröffentlichen, Nachbewertung des Trainings, Benachrichtigungen per E-Mail/Push |
| **3** | Eigene Videos hochladen, Transkript und Zusammenfassung, Bezahlmodell |

**Phase 1 speichert keine Videos.** Es werden nur Links, Titel und Vorschaubild gespeichert. Das hält Kosten, Speicher und Urheberrechtsrisiko niedrig.

## 2. Rollen

| Rolle | Rechte |
|---|---|
| Spieler | Link teilen (anonym oder offen), Pool sehen, upvoten, eigene Beiträge löschen |
| Coach | Alles wie Spieler, dazu: sieht immer, wer geteilt hat; Auswahl sehen; Beiträge bewerten, kommentieren, Notizen; in Trainingsmethoden übernehmen oder ablehnen |
| Admin | Mannschaft anlegen, Mitglieder einladen/entfernen, Schwelle einstellen (kann auch der Coach sein) |

## 3. Teilen: Wege in den Pool

Ziel: so wenige Schritte wie möglich. Jeder Weg legt denselben Eintrag an (Link, Mannschaft, Absender, anonym ja/nein).

1. **Teilen-Menü (Android):** Die PWA wird installiert („Zum Startbildschirm“) und erscheint dann im Teilen-Menü von Instagram, TikTok, YouTube, Facebook. Technik: Web Share Target. Ein Tipp: Teilen → Hear Me Coach → Fertig.
2. **Telegram-Bot:** Link an den Bot @HearMeCoachBot senden oder weiterleiten. Der Bot erkennt den Absender (einmalige Verknüpfung per Code) und legt den Beitrag an. Läuft auf Android und iOS, kostenlos, schnell umsetzbar.
3. **Link einfügen:** In der App oder Weboberfläche den kopierten Link einfügen. Funktioniert überall als Rückfallebene.
4. **WhatsApp:** Nicht im Prototyp. Die WhatsApp-Business-API braucht Anmeldung und ist kostenpflichtig. Später prüfen.
5. **iOS-Teilen-Menü:** Eine installierte PWA erscheint auf dem iPhone nicht im Teilen-Menü. Lösungen: Telegram-Bot (Phase 1), später native App per Capacitor mit Share Extension.

Hinweis beim Teilen: Eine Zielmannschaft wählen (Standard: die letzte), Titel und Kommentar optional („Warum sollten wir das machen?“), Schalter „anonym“.

## 4. Link-Vorschau

- Plattform erkennen (Instagram, TikTok, YouTube, Facebook, sonstige).
- Titel und Vorschaubild über oEmbed oder Open-Graph-Daten holen. Nur Vorschau und Link, kein Kopieren des Videos.
- Abspielen über die offizielle Einbettung der Plattform oder „In Instagram/TikTok öffnen“.
- **Risiko:** Instagram verlangt für oEmbed meist eine Meta-Entwickler-App. Als Rückfall zeigt die App eine Linkkarte mit Plattform-Symbol und Titel. Der aktuelle Stand der Plattformen wird beim Bau geprüft.
- Doppelte Links erkennen und zusammenführen (Link normalisieren, Tracking-Parameter entfernen).
- Nicht erreichbare oder private Beiträge: Linkkarte ohne Vorschau, Hinweis an den Absender.

## 5. Pool und Upvote

- Pool zeigt alle Beiträge der Mannschaft, sortiert nach Upvotes oder Datum. Filter: Plattform, Thema (optional), Status.
- **Upvote** (Daumen hoch), eine Stimme pro Nutzer und Beitrag, zurücknehmbar. Eigener Beitrag nicht upvotebar.
- Upvotes sind für Mitspieler nur als Zahl sichtbar. Wer abgestimmt hat, sieht nur der Coach.
- **Schwelle:** Ab N Upvotes (Standard 5, pro Mannschaft einstellbar) wechselt der Status auf „Relevant“. Der Coach bekommt dann einen Hinweis. Der Coach kann Beiträge auch ohne Schwelle manuell hochstufen.

## 6. Anonym oder offen

- Beim Teilen wählt der Absender „anonym“ oder „mit Namen“.
- Mitspieler sehen bei anonymen Beiträgen keinen Namen.
- **Der Coach sieht immer, wer geteilt hat.** Der Absender wird beim Teilen darauf hingewiesen („Der Coach sieht, von wem es kommt“). Das dient der Transparenz und dem Schutz vor Missbrauch.
- Der Admin kann Beiträge ausblenden oder löschen (Moderation).

## 7. Coach-Ansicht

- Liste „Relevant“ und „Neu“, sortiert nach Upvotes.
- Pro Beitrag: Vorschau, Link, Upvotes, Absender (immer sichtbar), Kommentar des Absenders.
- Aktionen: **Bewerten** (1 bis 5 Sterne), **Notiz** (privat oder für die Mannschaft sichtbar), **Status setzen**: Angeschaut, In Trainingsmethoden aufgenommen, Abgelehnt (mit kurzem Grund, optional sichtbar für den Absender).
- „In Trainingsmethoden aufgenommen“ legt den Beitrag in eine Methodensammlung der Mannschaft (Phase 1: einfache Liste mit Notiz, Phase 2: Trainingseinheiten).
- Der Absender erhält eine Rückmeldung zum Status seines Beitrags.

## 8. Datenmodell (Phase 1)

- `club` (id, name)
- `team` (id, club_id, name, altersklasse, schwelle_upvotes)
- `member` (user_id, team_id, rolle, einwilligung_at, einwilligung_eltern_at, telegram_id)
- `post` (id, team_id, absender_id, link_url, link_url_normalisiert, plattform, titel, vorschau_url, kommentar, anonym, status [neu|relevant|angeschaut|aufgenommen|abgelehnt], erstellt_at)
- `upvote` (post_id, user_id, erstellt_at), Primärschlüssel (post_id, user_id)
- `coach_review` (post_id, coach_id, sterne, notiz, notiz_sichtbar_team, grund_ablehnung, aktualisiert_at)
- `method` (id, team_id, post_id, titel, notiz, aufgenommen_at)

Phase 2 ergänzt: `favorite`, `training_session`, `session_item`, `session_rating`.
Phase 3 ergänzt: `media_file`, `transcript`.

Row-Level-Security: Zugriff nur für Mitglieder der Mannschaft. Absender-ID bei anonymen Beiträgen nur für Coach und Admin lesbar (über View oder Funktion, nicht über direkte Tabellenabfrage der Spieler).

## 9. Datenschutz und Recht

- Nur Links und Vorschau speichern, keine fremden Videos kopieren.
- Quelle immer sichtbar, Link führt zum Original.
- Minderjährige: Einwilligung der Erziehungsberechtigten für die Nutzung der App (Name, Bezug zur Mannschaft). Speichern mit Zeitstempel und Textversion.
- Anonymität gilt nur gegenüber Mitspielern, nicht gegenüber Coach und Admin. Darauf wird beim Teilen hingewiesen.
- Löschung: Mitglied kann eigene Beiträge und sein Konto löschen. Löschfrist für alte Beiträge einstellbar.
- Kein Tracking, keine Werbe-SDKs.
- Datenschutzerklärung und Nutzungsbedingungen vor dem Test mit echten Spielern. Rechtlich prüfen lassen, bevor Jugendliche teilnehmen.

## 10. Kosten und Preismodell

**Kosten Phase 1:** Es werden keine Videos gespeichert. Datenbank, Login und Vorschaubilder passen in der Regel in den kostenlosen oder günstigen Tarif von Supabase. Aktuelle Preise vor dem Start prüfen.

**Kosten Phase 3 (später):** Transkription und Zusammenfassung kosten pro 60-Sekunden-Clip etwa 0,5 Cent (Stand der Preise im November 2026: Transkription ca. 0,0045 $/Minute, Zusammenfassung mit Claude Haiku 5.5 ca. 0,10 $ pro Million Eingabe-Tokens). Alternativ selbst hosten auf dem vorhandenen DGX Spark. Eine Obergrenze pro Mannschaft ist nötig.

**Preismodell nach dem Vorbild von SpielerPlus/TeamPlus (Freemium):**
- Kostenlos: eine Mannschaft, Basisfunktionen, begrenzte Mitgliederzahl.
- Premium pro Mannschaft (Monat oder Jahr): mehr Mitglieder, Trainingseinheiten, Transkripte mit Kontingent.
- Vereinsrabatt: je mehr Mannschaften, desto günstiger pro Mannschaft.
- Optional: freiwilliger Spendenbutton, lokale Sponsoren als Banner.
- Keine Tracking-Werbung, keine Werbung in Bereichen mit Minderjährigen.
- Keine Bezahlfunktion, die Beiträge im Pool bevorteilt.

In Phase 1 ist alles kostenlos.

## 11. Technik

- Frontend: PWA (TypeScript, responsiv, Web Share Target, installierbar).
- Backend: Supabase (Postgres, Auth, RLS, Edge Functions), Region eu-central-1 (Frankfurt). Projekt noch nicht angelegt.
- Edge Function `fetch-preview`: Link normalisieren, Plattform erkennen, Vorschau holen.
- Telegram-Bot als Edge Function (Webhook).
- Später: Capacitor für Android-APK und iOS mit Share Extension.
- Oberfläche Deutsch, Code und Kommentare Englisch.

## 12. Akzeptanzkriterien Phase 1

1. Admin legt Verein und Mannschaft an und lädt drei Testnutzer per Link ein.
2. Ein Nutzer teilt einen TikTok-Link und einen Instagram-Link aus der jeweiligen App (Android, Teilen-Menü). Beide erscheinen im Pool, mit Vorschau oder Linkkarte.
3. Ein Nutzer sendet einen Link an den Telegram-Bot, der Beitrag erscheint im Pool.
4. Ein Link über „Link einfügen“ funktioniert ebenfalls. Ein doppelter Link wird erkannt.
5. Ein anonymer Beitrag zeigt Mitspielern keinen Namen, der Coach sieht den Absender.
6. Mitspieler upvoten. Bei Erreichen der Schwelle (im Test: 2) wechselt der Beitrag auf „Relevant“ und der Coach wird benachrichtigt.
7. Coach bewertet, schreibt eine Notiz und nimmt den Beitrag in die Trainingsmethoden auf. Der Absender sieht den Status.
8. Ein Spieler kann seinen Beitrag löschen, er ist danach für niemanden mehr sichtbar.
9. Ein Spieler einer fremden Mannschaft sieht nichts (RLS-Test).

## 13. Offene Fragen

- Erste Zielgruppe: Jugend oder Erwachsene?
- Reicht für die erste Testgruppe Android plus Telegram-Bot, oder sind iPhones dabei?
- Wo wird der Prototyp zuerst gehostet (Supabase plus statisches Hosting)?
- Namensprüfung „Hear Me Coach“.

## 14. Arbeitsanweisung für Claude Code

- Reihenfolge: Supabase-Projekt und Migrationen (Datenmodell, RLS) → Login und Mannschaft → Link teilen und Vorschau → Pool und Upvote → Coach-Ansicht → Telegram-Bot → Share Target.
- Kleine, überprüfbare Schritte. Nach jedem Schritt Akzeptanzkriterien prüfen.
- Anonymität nur über serverseitige Regeln (RLS, View), nie nur über die Oberfläche.
- Keine neuen Abhängigkeiten ohne Begründung.
- Vor kostenpflichtigen oder dauerhaften Aktionen fragen (Projekt anlegen, Migration anwenden, Daten löschen).

## 15. Ergänzungen (Stand Beta)

**Sportartneutral:** Der Coach wählt beim Anlegen die Sportart (Liste oder freie Eingabe), änderbar in den Einstellungen.

**Kategorien:** Jeder Beitrag bekommt optional eine Kategorie. Startliste für Mannschaften: Aufwärmen, Technik, Spielform, Taktik, Abschluss, Kondition, Ausklang. Wer beim Teilen eine neue Kategorie eintippt, fügt sie automatisch der Liste der Mannschaft hinzu (Groß-/Kleinschreibung wird zusammengeführt, max. 60). Der Coach kann Kategorien hinzufügen, entfernen und Beiträge umsortieren. Pool und Listen lassen sich nach Kategorie filtern.

**Solo-Modus („Ich trainiere allein“):** Eigene Sammlung ohne Coach und ohne Mitspieler (nicht beitretbar). Startkategorien: Aufwärmen, Brust, Rücken, Schultern, Arme, Beine, Core, Cardio, Dehnen. Funktionen: Videos speichern, Sterne direkt auf der Karte, Status Favorit / Okay / Nicht meins, Notiz, Sortierung (neueste, beste Bewertung, am häufigsten gemacht, am längsten nicht gemacht).

**Trainings-Protokoll und Statistik:** „✓ Gemacht“ trägt eine Übung mit Datum ein (zurücknehmbar). Im Solo-Modus bei allen Übungen, in Mannschaften bei Übungen, die der Coach ins Training aufgenommen hat. Statistik pro Person: Trainingstage, Übungen gesamt, Tage diese Woche, Wochen in Folge, Balken der letzten 12 Wochen, Verteilung nach Kategorie, Top 5, „länger nicht gemacht“.

**Zugang Beta:** Kein Passwort. Beitritt per Code, persönlicher Schlüssel im Browser. Alle Zugriffe laufen über Datenbank-Funktionen, die den Schlüssel prüfen.
