# Plauderecke online stellen

Du brauchst etwa 20 Minuten und zwei kostenlose Konten: **Supabase** (Datenbank, Speicher, Live-Chat) und **GitHub** (stellt die Website ins Internet). Eine Kreditkarte brauchst du nicht.

In diesem Ordner liegen:

- `index.html`: die Website
- `setup.sql`: richtet die Datenbank ein

## Teil 1: Supabase einrichten

1. Öffne **supabase.com**, tippe auf **Start your project** und registriere dich.
2. Tippe auf **New project**.
   - Name: `plauderecke`
   - Datenbank-Passwort: irgendein sicheres Passwort, gut aufheben
   - Region: **Central EU (Frankfurt)**

   Tippe dann auf **Create new project** und warte 1 bis 2 Minuten.
3. Links im Menü: **SQL Editor**. Kopiere den ganzen Text aus `setup.sql`, füge ihn ein und tippe auf **Run**. Kommt eine Warnung, bestätige mit **Run this query**. Unten erscheint dann eine Zeile „Plauderecke ist eingerichtet“ mit **tabellen 3** und **speicher 1**.
4. Links: **Authentication**, dann **Sign In / Providers**. Schalte **Allow anonymous sign-ins** ein und tippe auf **Save changes**. Damit können deine Freunde ohne eigenes Konto mitmachen.
5. Links: **Project Settings** (Zahnrad). Dort brauchst du zwei Werte:
   - Unter **Data API**: die **Project URL**, zum Beispiel `https://abcdefgh.supabase.co`
   - Unter **API Keys**: den **Publishable key** (beginnt mit `sb_publishable_`) oder unter „Legacy API Keys“ den **anon public** Key (beginnt mit `eyJ`)

   Den **secret** bzw. **service_role** Key nie verwenden. Der darf alles.

## Teil 2: Website online stellen

**Mit GitHub (geht auch auf dem Handy):**

1. Öffne **github.com** und registriere dich.
2. Oben rechts auf **+** und dann **New repository**. Name: `plauderecke`, **Public** wählen, **Create repository** tippen.
3. Auf der neuen Seite **uploading an existing file** antippen, `index.html` auswählen und unten **Commit changes** tippen.
4. Im Repository: **Settings**, dann links **Pages**. Bei „Source“ **Deploy from a branch** wählen, bei „Branch“ **main** und **/ (root)**, dann **Save**.
5. Nach 1 bis 2 Minuten steht oben auf der Pages-Seite deine Adresse: `https://DEINNAME.github.io/plauderecke/`

**Am Computer geht es auch so:** **app.netlify.com/drop** öffnen und den Ordner mit `index.html` ins Fenster ziehen. Lege ein kostenloses Netlify-Konto an, damit die Seite bleibt.

## Teil 3: Loslegen

1. Öffne deine Adresse, trag Project URL und Key ein und tippe auf **Verbinden**.
2. Gib deinen Namen ein und erstelle eine Gruppe.
3. Öffne die Gruppe, tippe oben auf **Einladen** (Person mit +) und dann auf **Link teilen** oder **Kopieren**. Schick den Link zum Beispiel per WhatsApp. Deine Freunde öffnen ihn, geben ihren Namen ein und sind drin.

Tipp: Im Browser-Menü **Zum Home-Bildschirm** wählen. Dann sieht Plauderecke aus wie eine App.

## So funktioniert's

- **Chat-Liste wie bei Snapchat:** Unten die Leiste mit Chats, Kamera und Profil. Bei jeder Gruppe steht, was zuletzt passiert ist (zum Beispiel „Neues Foto · 5 Min.“ oder „Geöffnet“) und wie viele Tage am Stück ihr geschrieben habt (🔥). ⌛ heißt: Heute hat noch nicht jeder geschrieben, sonst ist die Flamme morgen weg.
  - **Chat gedrückt halten:** Anheften 📌, als gelesen markieren, Snap schicken, Freunde einladen.
  - **Gelber Knopf unten rechts oder Person mit +:** Neue Gruppe machen oder mit einem eingefügten Link beitreten.
- **Kamera:** Tippen für ein Foto, gedrückt halten für ein Video (bis 30 Sekunden). Danach mit **T** oder einem Tipp aufs Bild Text draufschreiben, dann **Senden an** und Gruppen auswählen. Das Kamera-Symbol neben einer Gruppe schickt den Snap direkt dorthin.
- **Nachricht gedrückt halten** (am Computer: Rechtsklick oder ⋯): Reagieren mit Emoji, **Antworten**, Text kopieren, Löschen. Zweimal schnell tippen = ❤️.
- **Gelesen:** Unter deiner letzten Nachricht steht „Zugestellt“ oder „Gesehen von …“. Beim Öffnen einer Gruppe zeigt eine rote Linie, wo die neuen Nachrichten anfangen.
- **Ältere Nachrichten:** Im Chat ganz nach oben scrollen.
- **Sprachnachricht:** Den gelben Mikrofon-Knopf gedrückt halten und sprechen. Beim Loslassen wird sie gesendet.
  - **Nach links wischen:** Die Aufnahme wird gelöscht.
  - **Nach oben wischen:** Die Aufnahme läuft ohne Festhalten weiter. Zum Senden auf den Knopf tippen.
  - Beim ersten Mal fragt der Browser nach dem Mikrofon. Erlauben.
- **Fotos und Videos:** Über die Knöpfe links neben dem Textfeld. Große Videos werden vorher verkleinert. Dabei die Seite offen lassen.
- **Sticker:** Den Sticker-Knopf neben dem Textfeld antippen, dann „+ Neuer Sticker“ und ein Foto wählen oder machen.
  - **✂️ Hintergrund weg:** Schneidet die Person aus. Das klappt bei Fotos von Menschen. Beim ersten Mal lädt es ein paar Sekunden.
  - Form (Eckig, Kreis, Herz, Stern), weißer Rand und Text sind frei wählbar. Mit dem Finger verschieben, mit zwei Fingern zoomen.
  - „Senden“ schickt ihn sofort, „Speichern“ legt ihn nur unter „Meine Sticker“ ab. Sticker von Freunden: groß antippen, dann „Zu meinen Stickern“.
- **Profilbild:** In der Chat-Liste oben links auf deinen Kreis tippen. Tippt man im Chat auf ein Profilbild, wird es groß angezeigt.
- **Mehrere Gruppen:** Jede Gruppe hat ihren eigenen Einladungslink.

## Benachrichtigungen einrichten

Damit Handys Bescheid bekommen, wenn jemand schreibt, auch wenn Plauderecke zu ist:

1. Im Supabase **SQL Editor** den ganzen Text aus `push.sql` einfügen und **Run** tippen. Unten erscheint dann „Benachrichtigungen sind eingerichtet“.
2. In Supabase **Edge Functions** öffnen, **Deploy a new function** und dann **Via Editor** wählen.
   - Name: genau `notify`
   - Den Beispiel-Code löschen und den ganzen Text aus `supabase/functions/notify/index.ts` einfügen
   - **Deploy function** tippen
   - Hinweis: Die Adresse der Funktion steht in `index.html` und `push.sql` (bei dir: `swift-task`). Heißt deine Funktion anders, dort anpassen.
3. Bei der Funktion `notify` unter **Settings** die Option **Verify JWT with legacy secret** ausschalten und speichern. Die Funktion prüft selbst, ob ein Aufruf von deiner Datenbank kommt.
4. Auf der Website auf **Einschalten** tippen (oder auf die Glocke oben in der Chat-Liste) und erlauben. Das macht jeder auf seinem eigenen Handy.

Auf dem iPhone gehen Benachrichtigungen nur, wenn Plauderecke über Teilen › **Zum Home-Bildschirm** hinzugefügt und von dort geöffnet wird.

## Admin (Ersteller)

1. Im Supabase **SQL Editor** den ganzen Text aus `admin.sql` einfügen und **Run** tippen.
2. Unten erscheint **dein_admin_link**. Diesen Link öffnen, und zwar in dem Browser bzw. der App, mit der du Plauderecke benutzt. Den Link nie weitergeben!
3. Danach hast du eine 👑 und kannst:
   - unten auf einen Namen tippen und die Person aus der Gruppe entfernen
   - jede Nachricht löschen
   - unter **Einladen** einen neuen Einladungslink machen (der alte geht dann nicht mehr)
   - eine Gruppe für alle löschen

Wer `setup.sql` später nochmal ausführt, sollte danach auch `admin.sql` und `update.sql` nochmal ausführen.

## Update: Profilbilder, Gelesen, Reaktionen, Flammen

1. Im Supabase **SQL Editor** den ganzen Text aus `update.sql` einfügen und **Run** tippen. Unten steht dann **Update fertig!** und überall eine 1.
2. Fertig. Ohne dieses Update läuft die Website auch, nur ohne Profilbilder, „Gesehen“, Reaktionen und Flammen.

## Login mit Benutzername und Passwort

1. Im Supabase **SQL Editor** den ganzen Text aus `login.sql` einfügen und **Run** tippen. Unten steht dann **Login ist bereit!**
2. Wer Plauderecke schon benutzt, wählt beim nächsten Öffnen einmal Benutzername und Passwort. Gruppen, Nachrichten und Admin bleiben.
3. Neue Leute brauchen nur Benutzername und Passwort. Einmal eingeloggt, bleibt das Handy eingeloggt.
4. Auf einem neuen Handy: **Ich habe schon einen Account** und einloggen.
5. Im Profil gibt es **Abmelden** und **Account löschen** (löscht alles von dir, der Benutzername ist danach wieder frei).

Es wird keine E-Mail gebraucht und nie eine verschickt. Ein vergessenes Passwort kann man deshalb nicht zurücksetzen, also gut merken.

## Gut zu wissen

- Supabase gratis: 1 GB für Fotos, Videos und Sprachnachrichten, einzelne Dateien bis 50 MB. Für eine Freundesgruppe reicht das lange.
- Benutzt eine Woche lang niemand den Chat, pausiert Supabase das kostenlose Projekt. Dann im Supabase-Dashboard auf **Restore project** tippen.
- Wer den Einladungslink hat, kann beitreten. Schick ihn nur an Leute, die dabei sein sollen.
- Wer die Browserdaten löscht oder ein neues Handy nimmt, öffnet einfach den Einladungslink nochmal.
- Die Nachrichten aus dem alten claude.ai-Chat kommen nicht mit.
