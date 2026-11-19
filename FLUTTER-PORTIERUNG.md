# Rezeptgarten als native Android-App

Ziel ist eine signierte, native Flutter-APK mit dem vollständigen Funktionsumfang, dem Erscheinungsbild und der Bedienung der Rezeptgarten-Web-App. Die APK wird auf dem bestehenden Rezeptgarten-Container gespeichert und von dort heruntergeladen. Die reguläre APK soll sich über denselben Weg aktualisieren lassen.

Rezeptgarten **0.18.0, Build 14** ist der zuletzt veröffentlichte Testbuild auf LXC 103. Der [Testdownload](https://192.168.184.30/android/test/) und der [reguläre Download](https://192.168.184.30/android/) sind getrennte Kanäle. Die noch offenen Abnahmepunkte stehen am Ende dieses Dokuments.

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
| Einstellungen | Cookidoo-Konto verbinden und trennen, Synchronisierungsintervall und Status, manuelle Synchronisierung, JSON-Export, Dunkelmodus und Akzentfarbe. Der Installationsbereich zeigt die installierte Version, prüft den eigenen Aktualisierungskanal, lädt die APK und öffnet den Android-Installer. |

Für die Umsetzung dient der bei Projektstart geprüfte Webstand als Referenz. Die Tabelle beschreibt das Ziel für alle Bereiche. Vor der Freigabe werden auch seit Projektstart hinzugekommene Webfunktionen anhand des dann aktuellen Webstands abgeglichen. Die fachlichen Details zu Kalender, Notizen, Einkaufswagen, Telegram und Datenhaltung stehen in [AGENTS.md](AGENTS.md).

## Design und Bedienung

- Farben, Schriftgrößen, Abstände, Karten, Dialoge, Statusanzeigen, Rezeptbilder und Symbole aus der Web-App übernehmen. Die vorhandenen Zutaten- und Platzhaltersymbole werden mit der APK ausgeliefert. Dunkelmodus und benutzerdefinierte Akzentfarben gelten auch für Dialoge, Navigation und Rückmeldungen.
- Auf schmalen Displays die mobile Anordnung abbilden. Auf breiteren Android-Displays dient die breite Webansicht als Vorlage. Android-Systemleisten und große Systemeinstellungen für Schriftgröße bei der Anordnung berücksichtigen.
- Vergleichsaufnahmen von APK und PWA mit demselben isolierten Testdatenstand erstellen. Normalzustände, leere Ansichten, lange Rezeptnamen, Lade- und Fehlerzustände sowie Hell- und Dunkelmodus prüfen.
- Wochenwechsel, langes Drücken, Wischen, Rückgängig, Einkaufs-Häkchen und Android-Zurück-Navigation auf einem echten Gerät prüfen.

## Externe Integrationen

Die Android-App verwendet die Rezeptgarten-API im Heimnetz und die Telegram-
Benutzeranmeldung für die lesenden Wochen- und Einkaufswagenansichten unterwegs.
Die Google-API-Schlüsselverwaltung für Gemini gehört zur Web-App. Die
Web-Funktionen sind in [AGENTS.md](AGENTS.md) beschrieben.

### ThomasWlan und Telegram-Zugriff

1. **Verbindung automatisch wählen.** Beim Start, bei Rückkehr in die App und
   bei Netzwechseln prüft Android die SSID des verbundenen WLANs. Bei exakt
   `ThomasWlan` prüft die App den vorhandenen HTTPS-Endpunkt mit der gebündelten
   Rezeptgarten-CA innerhalb von 2,5 Sekunden. Bei erfolgreicher Prüfung stehen
   die vollständigen lokalen Funktionen zur Verfügung. Bei einem anderen WLAN,
   Mobilfunk oder unbekannter SSID verwendet die App mit Internet und aktiver
   Kopplung Telegram. Bei einem Timeout oder Verbindungsfehler in `ThomasWlan`
   gilt derselbe Telegram-Rückfall für Lesezugriffe. Zertifikatsfehler werden
   sichtbar gemeldet. Fehlen die Voraussetzungen für beide Wege, zeigt die App
   „Offline“ mit dem konkreten Grund. Die Android-Berechtigung für die
   SSID-Erkennung wird im Vordergrund erklärt und angefragt; bei Ablehnung lässt
   sie sich über die Einstellungen nachholen. Die lokale Netzwerkberechtigung
   richtet sich nach Android- und Ziel-SDK-Version. Laufende Schreibvorgänge
   behalten ihre lokale Fehler- und Konfliktbehandlung. Antworten eines zuvor
   gewählten Transportwegs dürfen nach einem Wechsel die neue Ansicht nicht
   überschreiben.

2. **Telegram beim Start einrichten.** Fehlt die Telegram-App-ID (`api_id`) oder
   der API-Hash (`api_hash`), erscheint beim Start „Telegram einrichten“ mit
   Eingabefeldern und „Später“. „Später“ lässt die Heimnetzfunktionen direkt zu;
   beim nächsten Start fragt die App erneut. Die Werte stammen aus den
   [Telegram API development tools](https://my.telegram.org/). Nach dem Speichern
   führt TDLib durch die Telegram-Anmeldung mit Telefonnummer, Bestätigungscode
   und gegebenenfalls Zwei-Schritt-Passwort. Eine gültige Sitzung wird beim
   nächsten Start wiederverwendet. Die App erklärt vor der Anmeldung, wann sie
   automatisch Anfragen an den Rezeptgarten-Bot sendet. Einstellungen bieten
   Einrichten, Ändern, Verbindung testen und Trennen. API-Hash, Telegram-Sitzung
   und Geräteschlüssel werden lokal verschlüsselt mit Schlüsselschutz durch den
   Android Keystore gespeichert und von Backups ausgeschlossen. Zugangsdaten
   bleiben außerhalb von APK, Quellcode und Logs. Der Server-Bot-Token bleibt im
   Server-Vault. Siehe [TDLib](https://core.telegram.org/tdlib/getting-started),
   [Telegram-API-Bedingungen](https://core.telegram.org/api/terms) und
   [Android Keystore](https://developer.android.com/privacy-and-security/keystore).

3. **Gerät im Heimnetz koppeln.** Android koppelt die angemeldete Telegram-
   Benutzer-ID und einen zufälligen Geräteschlüssel über den bestehenden
   HTTPS-Weg mit dem aktuell gewählten Rezeptgarten-Konto. Eine kurzlebige
   Einmalkennung im privaten Dialog mit dem konfigurierten Server-Bot bestätigt
   den Telegram-Absender. Erst nach bestätigter Kopplung darf die Bridge frische,
   authentifizierte Android-Anfragen dieser Benutzer-ID annehmen. Eine eigene
   Android-Kopplung und ein eigener Nachrichtentyp erhalten die bestehenden
   Web-Bot-Kopplungen. Antworten verwenden die vorhandenen Wochen- und
   Einkaufswagen-Momentaufnahmen, AES-256-GCM und eindeutige Anfragekennungen.
   Die App prüft Bot-ID, Zuordnung, Vollständigkeit und Authentizität vor der
   Anzeige. Bei Kontowechsel ist eine erneute Kopplung erforderlich. Ein Gerät
   kann im Heimnetz serverseitig entkoppelt werden.

4. **Telegram-Funktionsumfang der ersten Version.** „Meine Woche“ mit
   Wochenwechsel, Tagesrezepten, Platzhaltern und Ablage sowie „Mein
   Einkaufswagen“ stehen als verschlüsselte Momentaufnahmen zur Verfügung.
   Einkaufs-Häkchen lassen sich auf dem Gerät ändern und zurücksetzen. Die
   Änderungen gelten nur für die jeweilige Kopplung auf dem Gerät. Weitere
   Serverfunktionen und Schreibaktionen sind verfügbar, sobald die lokale
   Verbindung zurückkehrt. Die Kopfzeile zeigt „Heimnetz“, „Telegram“ oder
   „Offline“. Bei Rückkehr ins Heimnetz lädt die aktuelle Ansicht den
   Serverstand neu.

5. **Alte Android-Bot-Absender bereinigen.** Vor der Umstellung die Nutzung des
   bisherigen Android-Bot-Kopplungsplatzes und seiner Konfiguration prüfen.
   Den alten Android-Pfad in `app/main.py`, `app/telegram_pairs.py`, der Bridge
   und den zugehörigen Tests nach Einführung der neuen Benutzerkopplung
   entfernen oder gezielt ersetzen. Vorhandene Android-Bot-Kopplungsdaten beim
   Wechsel auf die neue Kopplung kontrolliert entfernen und eine erneute
   Einrichtung anzeigen. Gemeinsame Bot-Funktionen für die Web-App und deren
   gespeicherte Kopplung bleiben erhalten. Tests prüfen alte Konfigurationen,
   die Umstellung und den parallelen Betrieb der Web-App. Veraltete Aussagen
   in `AGENTS.md` und den betroffenen Projektskills aktualisieren.

6. **Updateprüfung.** Beim Öffnen der Android-Einstellungen wird keine
   Updateprüfung ausgelöst. Die
   installierte Version, „Nach Updates suchen“ und der ausdrücklich gestartete
   APK-Download mit Installation bleiben verfügbar. Den Einstellungstest so
   prüfen, dass das Öffnen keinen Manifestabruf auslöst und die manuelle
   Prüfung weiterhin funktioniert.

7. **Prüfen und veröffentlichen.** Mit isolierten Daten zunächst Anmeldung,
   Kopplung und den bestehenden Web-Zugriff mit isolierten Daten prüfen.
   Automatisierte Tests decken Netzwechsel, nicht erreichbaren Heimnetzserver,
   Kontowechsel, unvollständige und veränderte Antworten ab. Eine Geräteabnahme
   mit ADB wurde vom Nutzer abgelehnt. Dann
   die kompatible Bridge auf dem Proxmox-Host und die signierte APK im Testkanal
   bereitstellen. Vor der regulären Freigabe Web-Kopplung, Testdownload und
   Upgrade einer vorhandenen Android-Installation abnehmen.

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

Von Version 0.16.0 bis 0.17.0 prüfte Android beim Öffnen der Einstellungen und
über „Nach Updates suchen“ das Manifest des eigenen Kanals. Ab 0.18.0 wird die
Prüfung über „Nach Updates suchen“ gestartet. Die Anzeige unterscheidet
einen verfügbaren neueren Build, einen aktuellen Stand und einen fehlgeschlagenen
Abruf. Die Prüfung lädt nur das Manifest über HTTPS. Die APK wird erst über
„APK herunterladen und installieren“ geladen.

## Umsetzung und Freigabe

1. Toolchain unter WSL prüfen, Flutter-Projekt und gemeinsame UI-Komponenten anlegen und Snapshots der Weboberfläche mit Testdaten als Vorlage erfassen.
2. Einen vollständigen Heimnetzablauf auf Android prüfen. „Meine Woche“ öffnen, Rezepte in den Wagen übernehmen, eine Zutat abhaken und nach einem erneuten Laden den gespeicherten Stand in APK und PWA prüfen.
3. Die übrigen Ansichten und Einstellungen samt Fehlerbehandlung portieren.
4. Den signierten Build- und Veröffentlichungsablauf erproben. Android-Neuinstallation und anschließendes Update über den Container-Download prüfen. Daten und Einstellungen müssen beim Update erhalten bleiben. Einen abgebrochenen Upload prüfen und bestätigen, dass der vorherige Download erreichbar bleibt.
5. Vor der regulären Freigabe die vollständige Funktionsliste und den visuellen Vergleich abnehmen. Die Kernabläufe auf demselben Gerät im Heimnetz mit der mobilen PWA vergleichen. Zeit bis zur ersten bedienbaren Ansicht, bis zum geladenen Inhalt und bis zur bestätigten Aktion separat messen.
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
Einstellungen für Cookidoo, Synchronisierung, Dunkelmodus
und Akzentfarbe. Der JSON-Export verwendet die Android-Dateiauswahl. In den
Einstellungen steht die installierte Version mit einem Update-Button für den
passenden Downloadkanal. Die Tabelle oben beschreibt die Anforderungen für die vollständige
Portierung.

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
gelten die in diesem Dokument beschriebenen Paket-IDs und der eigene LXC-Download.
Die lokale WSL-Toolchain wurde
mit Flutter 3.50.0 und Dart 3.14.0 erkannt.

Build 13 von Rezeptgarten 0.17.0 wurde auf LXC 103 veröffentlicht. Die APK-Signatur
stimmt mit Build 12 überein. Paketdaten, ARM64-Architektur, Update-Manifest und
SHA-256 des HTTPS-Downloads wurden geprüft. Die
Flutter-Tests decken mit isolierten Testdaten die Übernahme der Woche, das
Speichern eines Einkaufs-Häkchens, Zusatzartikel, Übertragung und manuelle
Klärung, Rezeptdetails mit Notizkonflikten, Suche mit Mehrfachfiltern und die
Verwaltung lokaler Listen und des Vorrats ab. Der Wochentest prüft Wischen,
Rückgängig, Platzhalter und die Sperre beim fehlgeschlagenen Wochenwechsel.
Der Einstellungstest prüft die Übergabe der Konto- und Synchronisierungsdaten,
der lokalen Darstellung und der JSON-Bytes an ihre jeweiligen Schnittstellen.
Ein Widgettest prüft Update-Hinweis, aktuellen Stand, fehlgeschlagene Prüfung
und die Übergabe des Downloads an Android. Der Einstellungstest prüft auch,
dass die Android-App selbst bei gesetzten Serverwerten keine Bot- und
Google-API-Einstellungen zeigt. Die Abnahme auf dem Gerät steht noch aus.

Build 14 von Rezeptgarten 0.18.0 enthält die Android-Telegram-Benutzeranmeldung,
die Heimnetzerkennung und die lesenden Wochen- und Einkaufswagenansichten. Die
Signatur entspricht dem bisherigen Testkanal. Analyse, 17 Flutter-Tests,
132 Backendtests auf dem Server, Paketdaten, ARM64-Architektur, Update-Manifest
und SHA-256 des HTTPS-Downloads wurden geprüft. Server und Telegram-Bridge sind
bereitgestellt. Eine Anmeldung und ein Netzwechsel auf einem Android-Gerät wurden
auf Nutzerwunsch nicht durchgeführt.

## Offene Arbeiten vor der regulären Freigabe

- **Funktionsumfang und Design abgleichen.** Jede Zeile der Funktionsliste gegen
  die aktuelle mobile PWA prüfen und fehlende Funktionen, Schnellaktionen und
  Bedienzustände ergänzen. Die Ansichten mit identischen Testdaten nebeneinander
  prüfen und sichtbare Abweichungen bei Layout, Typografie, Symbolen und Gesten
  korrigieren.
- **Auf ARM64-Gerät abnehmen.** Test-APK über HTTPS vom LXC herunterladen,
  installieren und die Kernabläufe im Heimnetz durchspielen.
  Start, Laden und Aktionsbestätigung mit der PWA auf demselben Gerät vergleichen.
- **Release und Update erproben.** Stabile Release-Signatur bereitstellen,
  Veröffentlichung und Download im regulären Kanal prüfen und anschließend
  ein Update mit höherem `versionCode` installieren. Dabei den Erhalt lokaler
  Einstellungen sowie den vorherigen Download bei
  abgebrochenem Upload prüfen.
