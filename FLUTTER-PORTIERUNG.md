# Rezeptgarten als native Android-App

Ziel ist eine signierte, native Flutter-APK mit dem vollständigen Funktionsumfang, dem Erscheinungsbild und der Bedienung der Rezeptgarten-Web-App. Die APK wird auf dem bestehenden Rezeptgarten-Container gespeichert und von dort heruntergeladen. Die reguläre APK soll sich über denselben Weg aktualisieren lassen.

Rezeptgarten **0.15.0, Build 11** ist der zuletzt geprüfte Testbuild auf LXC 103. Der [Testdownload](https://192.168.184.30/android/test/) und der [reguläre Download](https://192.168.184.30/android/) sind getrennte Kanäle. Die noch offenen Abnahmepunkte stehen am Ende dieses Dokuments.

## Architektur

- Die Android-App entsteht mit nativen Flutter-Widgets in [android-app/](android-app/). Die mobile Web-App ist die Vorlage für Design und Verhalten. Die Web-App bleibt parallel erreichbar und als Chrome-PWA installierbar.
- Beide Clients verwenden dieselben Rezeptgarten-APIs und denselben Datenbestand im bestehenden Proxmox-LXC 103. SQLite, Bilder, Konten, Cookidoo-Zugangsdaten, Synchronisierung und Kalender-Warteschlange bleiben auf dem Server. Der bestehende Cookidoo-Client und sein Lock werden weiterhin gemeinsam genutzt.
- Ein zentraler API-Client verbindet Flutter mit `https://192.168.184.30`. Für diesen Endpunkt vertraut er dem öffentlichen Rezeptgarten-CA-Zertifikat und prüft Zertifikatskette und Host. Schreibanfragen setzen den passenden `Origin` für die bestehende Same-Origin-Prüfung. Der Zugang im Heimnetz bleibt ohne Passwort.
- Beim Start und beim Öffnen des Einkaufswagens wartet die App höchstens 2,5 Sekunden auf die Erreichbarkeit des Heimnetzservers. Schreibanfragen erhalten dieses Zeitlimit nicht. Bei unklaren Schreibergebnissen prüft die App den Serverstand, bevor sie eine Wiederholung anbietet.

## Vollständiger Funktionsumfang

| Bereich | In der APK umzusetzen |
| --- | --- |
| Übersicht und Navigation | Täglich wechselndes Zufallsrezept mit manueller Neuauswahl. Kopfzeile mit Suche, Verbindungsstatus, Synchronisierung, Einkaufswagen-Zähler und Einstellungszahnrad. Sechs Hauptbereiche in der unteren Navigation. |
| Rezeptlisten und Suche | Cookidoo-Listen, Kollektionen, Merkliste, eigene Kreationen und lokale Listen. Lokale Listen anlegen, nach Bestätigung löschen und Rezepte zuordnen. Rezeptversionen gruppieren und auswählen. Suche nach Titeln und Zutaten einschließlich Aliasen, mehrere Zutatenfilter sowie Filter für Portionen und Dauer. Sortierung, ausgegraute Treffer und Titeltreffer vor reinen Zutatentreffern wie im Web. |
| Rezeptdetails | Bilder, zugeordnete Listen, Dauer, Portionen und Schwierigkeitsgrad. Zutaten mit Vorratsstatus und Symbolen, Zubereitung und Tipps mit denselben anfänglichen Klappzuständen. Persönliche Notizen für Katalogrezepte und eigene Kreationen mit sichtbarer Konfliktbehandlung. Aktionen für Wochenablage, Planung, Einkaufswagen und „In Cookidoo öffnen“. |
| Meine Woche | Berliner Kalenderwoche mit Pfeilen und „Diese Woche“, einrastende Tagesansicht und gemerkter Wochentag. Tagesrezepte, lokale Ablage, sechs feste Platzhalter und aufklappbare lokale Listen. Langes Drücken und Wischen, kurzes Tippen und normales Scrollen wie mobil im Web. Rückgängig bei Rezeptentfernungen für fünf Sekunden. Vorgemerkte Verschiebungen, bestätigter Kalenderabgleich und sichtbare Fehler. Einkauf ab heute einschließlich Ablage als Momentaufnahme übernehmen. |
| Mein Einkaufswagen | Kontobezogene Rezeptkarten, Zusatzartikel und bearbeitbare Häkchen. Kompakte Zeilen mit Mengen, Rezeptnamen und Zutatensymbolen. Sortierung nach offenen und abgehakten Einträgen und Gruppierung nach Warenbereichen. Vorratsabgleich und ausgeblendetes Wasser wie im Web. Einträge entfernen oder Wagen leeren. Ausdrücklicher Cookidoo-Transfer mit bestätigten und ungeklärten Ergebnissen sowie manueller Klärung. |
| Mein Vorrat | Alphabetische Zutaten, Rezeptvorschläge und einklappbare Kategorien. Kategorien anlegen, sortieren und nach Bestätigung löschen. Vorratseinträge hinzufügen, bearbeiten und entfernen. Dieselben Zutaten-Aliasse, Symbole und Regeln zum Ausblenden von Wasser. |
| Einstellungen | Cookidoo-Konto verbinden und trennen, Synchronisierungsintervall und Status, manuelle Synchronisierung, JSON-Export, Google-API-Schlüssel, Dunkelmodus und Akzentfarbe. Telegram-Einrichtung und Verbindungstest. Der Installationsbereich zeigt die installierte Version, lädt Updates im eigenen Kanal und öffnet den Android-Installer direkt. |
| Telegram unterwegs | Verschlüsselte Wochen- und Einkaufswagenansicht, Wochenwechsel, lokale Einkaufs-Häkchen und deren Rücksetzung. Blauer Papierflieger und ausgegraute Navigation wie im Web. Bei Rückkehr ins Heimnetz wieder direkt laden. |

Für die Umsetzung dient der bei Projektstart geprüfte Webstand als Referenz. Die Tabelle beschreibt das Ziel für alle Bereiche. Vor der Freigabe werden auch seit Projektstart hinzugekommene Webfunktionen anhand des dann aktuellen Webstands abgeglichen. Die fachlichen Details zu Kalender, Notizen, Einkaufswagen, Telegram und Datenhaltung stehen in [AGENTS.md](AGENTS.md).

## Design und Bedienung

- Farben, Schriftgrößen, Abstände, Karten, Dialoge, Statusanzeigen, Rezeptbilder und Symbole aus der Web-App übernehmen. Die vorhandenen Zutaten- und Platzhaltersymbole werden mit der APK ausgeliefert. Dunkelmodus und benutzerdefinierte Akzentfarben gelten auch für Dialoge, Navigation und Rückmeldungen.
- Auf schmalen Displays die mobile Anordnung abbilden. Auf breiteren Android-Displays dient die breite Webansicht als Vorlage. Android-Systemleisten und große Systemeinstellungen für Schriftgröße bei der Anordnung berücksichtigen.
- Vergleichsaufnahmen von APK und PWA mit demselben isolierten Testdatenstand erstellen. Normalzustände, leere Ansichten, lange Rezeptnamen, Lade- und Fehlerzustände, Hell- und Dunkelmodus sowie Telegram-Ansichten prüfen.
- Wochenwechsel, langes Drücken, Wischen, Rückgängig, Einkaufs-Häkchen und Android-Zurück-Navigation auf einem echten Gerät prüfen.

## Telegram

Die APK verwendet das bestehende Bot-zu-Bot-Protokoll für den lesenden Zugriff außerhalb des Heimnetzes. Sie speichert Client-Bot-Token und Kopplungsschlüssel im geschützten Android-Speicher. Der Server-Bot bleibt serverseitig konfiguriert. Beide Clients benötigen getrennte Client-Bots und getrennte Schlüssel, damit ihre Update-Abfragen unabhängig laufen.

Der Server speichert eine kontogebundene Kopplung für den Browser und eine für
Android. Die vorhandene Browserkopplung bleibt lesbar. Der Telegram-Dienst auf
dem Proxmox-Host ordnet Anfragen und verschlüsselte Antworten der jeweiligen
Kopplung zu. Android kann seine Kopplung im Heimnetz einrichten und per
Nachrichtentest prüfen. Der Abruf und die Anzeige von Wochen- und
Einkaufswagen-Momentaufnahmen in der APK folgen noch.

Die App prüft Absender, Anfragekennung und Vollständigkeit jeder Antwort sowie die Authentizität der verschlüsselten Momentaufnahme. Sie übernimmt die bestehende optionale Komprimierung und die lokal gespeicherten Einkaufs-Häkchen je Kopplung. Bei fehlendem Heimnetz erfolgt der Zugriff rein lesend. Bilder und Notizinhalte werden über Telegram nicht übertragen.

## APK-Veröffentlichung auf LXC 103

Die vorhandene Flutter- und Android-Toolchain aus Ubuntu 24.04 unter WSL ist das Vorbild. Der Rechner baut und signiert die APK. Der Container speichert und verteilt die geprüfte Datei über Caddy. Als Einstieg dient ein projektspezifisches Skript unter `scripts/Android-APK-veroeffentlichen.ps1`.

1. **Bauen.** Toolchain und Abhängigkeiten prüfen, Flutter-Analyse und Tests ausführen und eine signierte Release-APK erzeugen. Die Zielarchitektur beim ersten Build gegen das Zielgerät prüfen. Paket-ID vor der ersten Verteilung festlegen und beibehalten. `versionName` aus `APP_VERSION` ableiten und einen mit jeder Veröffentlichung steigenden Android-`versionCode` vergeben. Den eigenen Release-Schlüssel außerhalb von Git geschützt speichern und separat sichern.
2. **Lokal prüfen.** APK-Signatur und erwarteten Signaturfingerabdruck sowie Paket-ID, Versionswerte, native Architektur, Größe und SHA‑256 prüfen.
3. **Übertragen.** Per SSH mit Hostschlüsselprüfung in einen temporären, über Caddy unerreichbaren Bereich des LXC hochladen. Ziel und temporären Bereich auf demselben Dateisystem anlegen. Auf dem LXC Größe und SHA‑256 mit dem lokalen Build vergleichen.
4. **Veröffentlichen.** Die geprüfte Datei unter einem unveränderlichen, versionierten Namen in `/var/lib/rezeptgarten-downloads/` freigeben. Erst danach die Downloadseite und das Update-Manifest `latest.json` jeweils atomar ersetzen. Parallele Veröffentlichungen serialisieren, damit eine ältere Ausgabe die aktuelle Version nicht überschreibt. Bei einem Upload- oder Prüffehler bleibt die bisherige Version verfügbar und die gebaute APK lokal erhalten.
5. **Download prüfen.** Caddy stellt eine Downloadseite und das Update-Manifest unter `/android/` bzw. `/android/test/` bereit. Das Skript prüft das Manifest und den veröffentlichten APK-Download über HTTPS. Für einen erstmaligen Browserdownload muss das Gerät der Rezeptgarten-CA vertrauen.

Ab Version 0.15.0 startet „APK herunterladen und installieren“ in den Android-
Einstellungen den Download im eigenen Kanal. Die App nutzt die mitgelieferte
Rezeptgarten-CA, unterstützt die erneute Installation desselben Builds und
lehnt ältere Builds ab. Sie prüft
Dateigröße, SHA-256, Paket-ID und Versionsdaten und übergibt die private
Cachedatei an den Android-Installer. Bei der ersten Aktualisierung kann Android
eine Freigabe für diese Installationsquelle verlangen. Nach der Freigabe und
Rückkehr zur App öffnet sich der Installer, in dem der Nutzer das Update bestätigt.

## Umsetzung und Freigabe

1. Toolchain unter WSL prüfen, Flutter-Projekt und gemeinsame UI-Komponenten anlegen und Snapshots der Weboberfläche mit Testdaten als Vorlage erfassen.
2. Einen vollständigen Heimnetzablauf auf Android prüfen. „Meine Woche“ öffnen, Rezepte in den Wagen übernehmen, eine Zutat abhaken und nach einem erneuten Laden den gespeicherten Stand in APK und PWA prüfen.
3. Die übrigen Ansichten und Einstellungen samt Fehlerbehandlung portieren. Telegram-Kopplungen für den Parallelbetrieb erweitern und den Wechsel zwischen Heimnetz und Telegram auf beiden Clients prüfen.
4. Den signierten Build- und Veröffentlichungsablauf erproben. Android-Neuinstallation und anschließendes Update über den Container-Download prüfen. Daten und Einstellungen müssen beim Update erhalten bleiben. Einen abgebrochenen Upload prüfen und bestätigen, dass der vorherige Download erreichbar bleibt.
5. Vor der regulären Freigabe die vollständige Funktionsliste und den visuellen Vergleich abnehmen. Die Kernabläufe auf demselben Gerät und Netz mit der mobilen PWA vergleichen. Zeit bis zur ersten bedienbaren Ansicht, bis zum geladenen Inhalt und bis zur bestätigten Aktion separat messen. Heimnetz und Telegram getrennt erfassen.
6. Relevante App- und Betriebsänderungen nach den bestehenden Projektregeln versionieren, dokumentieren, mit isolierten Daten testen und auf die bestehende Instanz deployen. Bereitstellung prüfen und die Versionsänderung anschließend committen und nach `origin/main` pushen.

## Erster Teststand

Der native Android-Teststand verwendet die bestehende API für die
Wochenansicht und die Übernahme in den Einkaufswagen. Der Android-Einkaufswagen
zeigt Warenbereiche, gruppierte Zutaten, Symbole und Häkchen. Dort können
Zusatzartikel hinzugefügt, Einträge entfernt, der Wagen geleert und die
Übertragung an Cookidoo ausdrücklich ausgelöst werden. Ungeklärte Übertragungen
können nach Prüfung in Cookidoo bestätigt oder wieder freigegeben werden.
Rezepte lassen sich auch über ihre Detailansicht hinzufügen. Dort zeigt die APK
Rezeptversionen, Listenzuordnungen, Zutaten mit Vorratsstatus, Zubereitung und
Tipps. Persönliche Notizen werden beim Abschluss der Eingabe oder beim
Verlassen gespeichert. Bei einem Cookidoo-Konflikt bleibt der Entwurf im Feld.
„Heute kochen“ meldet, ob Cookidoo die Planung verifizieren konnte. Die
Rezeptbibliothek unterstützt paginierte Titel- und Zutatensuche,
Mehrfach-Zutatenfilter, Portionen, Gesamtzeit, Sortierung und ausgegraute
Listeneinträge außerhalb der Filter. Lokale Listen lassen sich anlegen, löschen
und um weitere Rezepte ergänzen. Das Zufallsrezept kann manuell neu gewählt
werden. „Mein Vorrat“ unterstützt Zutatensuche, Rezeptvorschläge, das Hinzufügen,
Bearbeiten und Entfernen von Zutaten sowie einklappbare Kategorien. Kategorien
lassen sich anlegen, mit dem Griff sortieren und nach Bestätigung mit ihren
Einträgen löschen. „Meine Woche“ zeigt vorgemerkte Änderungen, unterstützt
das Verschieben per Maus sowie durch Halten und Wischen, die Wochenablage,
Platzhalter, die Übernahme aus lokalen Listen und fünf Sekunden Rückgängig
bei Rezeptentfernungen. Auf schmalen Displays rasten die Tage ein. Die
Übersicht zeigt Sammlungsstatistik und Rezeptvorschauen. Android bietet
Einstellungen für Cookidoo, Synchronisierung, Google-API-Schlüssel, Dunkelmodus
und Akzentfarbe. Der JSON-Export verwendet die Android-Dateiauswahl. In den
Einstellungen steht die installierte Version mit einem Update-Button für den
passenden Downloadkanal. Die Tabelle oben beschreibt die Anforderungen für die vollständige
Portierung einschließlich Telegram.

Testbuilds verwenden `de.rezeptgarten.rezeptgarten.test` und die separate
Downloadseite `https://192.168.184.30/android/test/`. Das folgende Beispiel
baut und veröffentlicht den ersten Testbuild aus der Projektwurzel. Für weitere
Veröffentlichungen eine höhere Buildnummer als auf der Downloadseite wählen.

```powershell
.\scripts\Android-APK-veroeffentlichen.ps1 -BuildNumber 1 -Upload
```

Ohne `-Upload` bleibt die APK lokal unter
`android-app/build/app/outputs/flutter-apk/`. Der erste Build bezieht die
öffentliche CA mit geprüftem SSH-Hostschlüssel vom Container. Der Build läuft
in einem temporären Verzeichnis im WSL-Dateisystem. Nach einem reinen
Uploadfehler prüft und veröffentlicht `-UseExistingBuild -Upload` die
vorhandene, zuvor gebaute APK mit derselben Buildnummer.

Der reguläre Veröffentlichungskanal verwendet die Paket-ID
`de.rezeptgarten.rezeptgarten`. Er setzt `-Release`, eine private
`android-app/android/release-signing.properties` mit `storeFile`,
`storePassword`, `keyAlias` und `keyPassword` sowie den erwarteten
Zertifikatfingerabdruck als `-SignerSha256` voraus.

Die Datei aus dem Nachbarprojekt unter
`C:/Github/Telegram2Homeassistant/FLUTTER-PORTIERUNG.md` dient als Referenz für
die lokale Toolchain und den Aufbau des Build-Ablaufs. Für Rezeptgarten
gelten die in diesem Dokument beschriebenen Paket-IDs, der eigene LXC-Download
und das bestehende Rezeptgarten-Bot-Protokoll. Die lokale WSL-Toolchain wurde
mit Flutter 3.50.0 und Dart 3.14.0 erkannt.

Build 11 von Rezeptgarten 0.15.0 wurde auf LXC 103 veröffentlicht. Die APK-Signatur
stimmt mit Build 10 überein. Paketdaten, ARM64-Architektur, Update-Manifest und
SHA-256 des HTTPS-Downloads wurden geprüft. Die
Flutter-Tests decken mit isolierten Testdaten die Übernahme der Woche, das
Speichern eines Einkaufs-Häkchens, Zusatzartikel, Übertragung und manuelle
Klärung, Rezeptdetails mit Notizkonflikten, Suche mit Mehrfachfiltern und die
Verwaltung lokaler Listen und des Vorrats ab. Der Wochentest prüft Wischen,
Rückgängig, Platzhalter und die Sperre beim fehlgeschlagenen Wochenwechsel.
Der Einstellungstest prüft die Übergabe der Konto- und Synchronisierungsdaten,
der lokalen Darstellung und der JSON-Bytes an ihre jeweiligen Schnittstellen.
Ein Widgettest prüft, dass der Download-Button den nativen Kanal anspricht
und den laufenden Abruf anzeigt. Die Abnahme des Installers auf dem Gerät
steht noch aus.
Der Telegram-Test verwendet simulierte Bot-Antworten. Er prüft die getrennte
Android-Kopplung und verwirft fremde, alte und falsch zugeordnete Nachrichten.

## Offene Arbeiten vor der regulären Freigabe

- **Telegram unterwegs fertigstellen.** Woche und Einkaufswagen als
  authentifizierte, verschlüsselte Momentaufnahmen abrufen und anzeigen.
  Wochenwechsel, lokale Häkchen pro Kopplung sowie den Wechsel ins und aus
  dem Heimnetz auf Android prüfen.
- **Funktionsumfang und Design abgleichen.** Jede Zeile der Funktionsliste gegen
  die aktuelle mobile PWA prüfen und fehlende Funktionen, Schnellaktionen und
  Bedienzustände ergänzen. Die Ansichten mit identischen Testdaten nebeneinander
  prüfen und sichtbare Abweichungen bei Layout, Typografie, Symbolen und Gesten
  korrigieren.
- **Auf ARM64-Gerät abnehmen.** Test-APK über HTTPS vom LXC herunterladen,
  installieren und die Kernabläufe im Heimnetz und über Telegram durchspielen.
  Start, Laden und Aktionsbestätigung mit der PWA auf demselben Gerät vergleichen.
- **Release und Update erproben.** Stabile Release-Signatur bereitstellen,
  Veröffentlichung und Download im regulären Kanal prüfen und anschließend
  ein Update mit höherem `versionCode` installieren. Dabei den Erhalt lokaler
  Einstellungen und der Telegram-Kopplung sowie den vorherigen Download bei
  abgebrochenem Upload prüfen.
