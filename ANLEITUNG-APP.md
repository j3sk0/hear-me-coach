# Anleitung: Hear Me Coach als echte App

Die App ist fertig programmiert (`mobile/`). Damit sie auf die Handys kommt, braucht es einmalig drei Konten und ein paar Einstellungen. Ein Mac ist nicht nötig, gebaut wird in der Expo-Cloud.

**Kosten:** Expo kostenlos · Google Play einmalig 25 $ · Apple Developer Program 99 $ pro Jahr · Firebase (für Android-Push) kostenlos

---

## 1. Expo-Konto und Zugangsschlüssel für GitHub

1. Auf https://expo.dev ein kostenloses Konto anlegen.
2. Auf expo.dev: **Account settings → Access tokens → Create token**. Name z. B. `github`. Den Token kopieren.
3. Auf GitHub im Repo `hear-me-coach`: **Settings → Secrets and variables → Actions → New repository secret**
   - Name: `EXPO_TOKEN`
   - Wert: der kopierte Token
   
   Den Token nirgends sonst hinterlegen oder in den Chat schreiben.

## 2. Expo-Projekt anlegen

1. Auf expo.dev: **Projects → Create a project**, Name **hear-me-coach** (Slug genau so).
2. Die angezeigte **Project ID** (Format `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) an Claude geben. Sie wird in `mobile/app.json` unter `expo.extra.eas.projectId` eingetragen. Die ID ist kein Geheimnis.

## 3. Android

### 3a. Push-Benachrichtigungen (Firebase)
1. https://console.firebase.google.com → **Projekt hinzufügen**, Name z. B. *Hear Me Coach* (Google Analytics kann aus bleiben).
2. **Android-App hinzufügen**, Paketname: `com.j3sk0.hearmecoach`.
3. **google-services.json** herunterladen und an Claude geben (oder selbst nach `mobile/` legen). Diese Datei darf ins Repo.
4. In Firebase: **Projekteinstellungen → Dienstkonten → Neuen privaten Schlüssel generieren**. Das ist eine geheime JSON-Datei. **Nicht** in den Chat und nicht ins Repo!
5. Auf expo.dev: Projekt **hear-me-coach → Credentials → Android → com.j3sk0.hearmecoach → FCM V1 service account key → Upload** und die Datei aus Schritt 4 hochladen.

### 3b. Sofort testen ohne Play Store (APK)
1. Auf GitHub: **Actions → App bauen → Run workflow**, Plattform **android**, Profil **preview**.
2. Nach ca. 15–20 Minuten steht auf expo.dev unter **Builds** ein Download-Link (auch als QR-Code).
3. Auf dem Android-Handy öffnen und installieren. Android fragt einmal, ob Installationen aus dieser Quelle erlaubt sind.

### 3c. Play Store
1. Konto in der **Google Play Console** anlegen (25 $, Identitätsprüfung dauert einige Tage).
2. App anlegen: Name *Hear Me Coach*, Paketname `com.j3sk0.hearmecoach`.
3. Build für den Store: **Actions → App bauen**, Plattform **android**, Profil **production**. Die erste `.aab`-Datei von expo.dev herunterladen und in der Play Console unter **Testen → Geschlossener Test** hochladen. Google verlangt, dass die erste Version von Hand hochgeladen wird.
4. **Wichtig für neue private Konten:** Vor der Veröffentlichung im Store muss ein geschlossener Test mit **mindestens 12 Testern über 14 Tage** laufen. Die Mannschaft trägt sich mit ihrer Google-Mail-Adresse als Tester ein und installiert die App über den Test-Link aus dem Play Store.
5. Für automatisches Hochladen späterer Versionen: in der Play Console ein Dienstkonto mit Release-Rechten anlegen und dessen Schlüssel auf expo.dev unter **Credentials → Android → Google Service Account** hochladen. Danach beim Workflow „Automatisch senden“ anhaken.

## 4. iPhone

1. **Apple Developer Program** beitreten: https://developer.apple.com/programs/ (99 $/Jahr, Freischaltung oft 1–2 Tage).
2. **Einmalig am PC** (Windows reicht), damit Expo die Apple-Zertifikate anlegen kann:
   1. Node.js installieren (https://nodejs.org, LTS).
   2. In der Eingabeaufforderung:
      ```
      git clone https://github.com/j3sk0/hear-me-coach.git
      cd hear-me-coach\mobile
      npm ci
      npx eas-cli login
      npx eas-cli build --platform ios --profile production
      ```
   3. Bei den Fragen mit der Apple-ID anmelden. Alles von Expo erzeugen lassen, auch den **Push-Notifications-Key** (mit „Ja“ bestätigen).
   4. Nach dem Build: `npx eas-cli submit --platform ios --latest`. Die App landet in **App Store Connect → TestFlight**.
3. **Tester einladen:** In App Store Connect unter **TestFlight** eine **externe Gruppe** anlegen, den **öffentlichen Link** einschalten und in die Mannschaftsgruppe schicken. Die erste externe Version prüft Apple kurz (meist innerhalb eines Tages). Die Tester installieren zuerst die App „TestFlight“ und dann Hear Me Coach.
4. Spätere iOS-Builds gehen auch über **Actions → App bauen** (Plattform ios, Profil production, „Automatisch senden“).

**Hinweis:** Für den öffentlichen App Store prüft Apple strenger. Apps, die hauptsächlich eine Webseite anzeigen, werden manchmal abgelehnt (Richtlinie 4.2). Für TestFlight ist das kein Problem. Mit Teilen-Erweiterung und Push hat die App echte native Funktionen. Falls Apple ablehnt, lassen sich weitere Teile nativ umsetzen.

## 5. So funktioniert es danach

- **Teilen:** In TikTok, Instagram oder YouTube auf **Teilen** tippen und **Hear Me Coach** wählen. Auf dem iPhone steht die App eventuell erst unter **Mehr**, dort lässt sie sich nach vorne ziehen. Die App öffnet sich mit dem Link im Formular.
- **Anmelden:** Mit Mannschafts-Code beitreten oder mit dem persönlichen Zugangscode aus der Web-App anmelden. Die Anmeldung bleibt in der App gespeichert.
- **Benachrichtigungen:** Nach der ersten Anmeldung fragt die App nach der Erlaubnis. Unter **Team → Benachrichtigungen** lässt sich jede Art einzeln abschalten.
- **Updates:** Änderungen an der Web-App (`docs/`) sind sofort in der App sichtbar, ohne neuen Build.
