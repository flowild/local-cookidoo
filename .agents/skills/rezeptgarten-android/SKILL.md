---
name: rezeptgarten-android
description: Entwickle, prüfe und veröffentliche die native Rezeptgarten-App in android-app mit Flutter, Android-Installer und APK-Downloads auf LXC 103.
---

# Rezeptgarten für Android

- Nutze [FLUTTER-PORTIERUNG.md](../../../FLUTTER-PORTIERUNG.md) für Umfang,
  Design und offene Abnahme. Die mobile PWA ist die Vorlage für fachliche Abläufe
  und Gesten. Android verwendet Material 3 Expressive mit dem gemeinsamen Theme
  in `expressive_theme.dart`. Prüfe helle und dunkle Rollenfarben, Akzentfarben,
  kompakte Navigation und Seitenleiste, große Schrift und reduzierte Bewegung.
  Verwende dieselben isolierten Testdaten wie die PWA.
- Standardfarben für Hintergrund, Karte, Text und Akzent an die Hell- und
  Dunkelwerte in `app/static/style.css` anlehnen.
- Verwende `AppSpacing` für Seiten- und Kartenränder, Abschnitte sowie Abstände
  zwischen zusammengehörigen Bedienelementen. Verbundene Schalter und Abzeichen
  verwenden die kompakten Werte. Listenkarten erhalten ihren Abstand im Layout.
- Prüfe zusammengehörige Aktionen auf gemeinsame Spaltenkanten. Die vier Direktzugriffe in „Deine Sammlung“ belegen je nach Platz eine, zwei oder vier Spalten. Vergleiche die Anordnung bei 332 dp mit normaler und großer Schrift. Reine Textpillen dürfen kompakt sein, antippbare Elemente brauchen auch bei kleiner sichtbarer Fläche ein 48-dp-Tippziel.
- Bildbadges für Zeit und Portionen liegen in getrennten unteren Ecken.
  Die visuelle Kartenaktion bleibt innerhalb der Bildecke und behält ihr
  48-dp-Tippziel. Prüfe auch schmale Tagesspalten und größere Schrift.
- Gleich breite Rezeptkarten reservieren zwei Titelzeilen und eine Zeile
  für die Schwierigkeit. Kürze überlange Kartentitel mit Auslassungszeichen.
  Die vollständigen Titel stehen in den Rezeptdetails.
- Beim Wischen wie in der mobilen PWA die markierte Wochenkachel mitführen und
  die geplante Aktion vor dem Loslassen anzeigen. Wochenkacheln nach 250 ms
  markieren und aufwärts ab 140 dp, abwärts ab 90 dp ausführen.
  Bei reduzierter Bewegung bleibt die textliche Vorschau sichtbar.
  Die Wochenansichten zeigen die ISO-Kalenderwoche an der Navigation. Die
  aktuelle Berliner Woche und der heutige Tageskopf sind hervorgehoben.
  „Heute“ zeigt den heutigen Tag der aktuellen Woche. Im Heimnetz wird der
  Tag im Kalender ausgewählt, im Telegram-Modus scrollt die Liste zu ihm.
  Wischhinweise erscheinen während der Geste. Einkaufs-Häkchen brauchen
  keinen dauerhaft sichtbaren Erklärungstext.
- Hauptansichten beim Tabwechsel bedarfsgerecht erhalten und Hintergrundarbeit
  auf den sichtbaren Tab begrenzen. Beim erneuten Laden sichtbarer Listen,
  Vorratskategorien oder Wocheninhalte ihre Position beibehalten. Bei Änderungen der Kontoverbindung und
  beim Verlassen des Heimnetzmodus private Ansichtsdaten und Bildcache leeren.
- Bilder getrennt nach Vorschau und Original laden. Gleichzeitige Bildabrufe
  bündeln, die Cachefreigabe des Servers beachten und den Speicher begrenzen.
  Die Dekodierungsgröße an die physische Anzeigebreite anpassen.
- Prüfe beim Öffnen und Schließen eines Rezepts die Anzahl der Abrufe. Reines Lesen
  erhält Woche, Trefferseiten und Scrollposition. Langsame Wochenmedien und
  Notizsymbole dürfen die Navigation nicht aufhalten. Eine geladene Notiz bleibt
  während der Tipps- und Listenabfrage bearbeitbar. Nach bestätigtem Hinzufügen
  eines Rezepts im Detail den Zähler über den Serverstatus abgleichen.
- Telegram und Heimnetz verwenden dieselbe sichtbare Datumsdarstellung.
  Einkaufszutaten in beiden Modi beim Scrollen aufbauen.
- Prüfe die sechs Navigationsziele bei etwa 332 dp und mit großer Schrift.
  Auf Handys öffnen Rezeptfilter als Bottom Sheet und behalten dieselben
  Eingaben und Aktionen wie im größeren Fenster. Auf schmalen Rezeptlisten
  bleiben kompakte Karten bei normaler Schrift gut lesbar.
- Im Einkaufswagen offene Zutaten vor abgehakten Zutaten und Rezeptkarten
  anzeigen. Die ganze Zutatenzeile ist antippbar. Lange Listen schrittweise
  beim Scrollen aufbauen. Zusatzartikel über das Eingabeblatt erfassen.
  Im Vorrat Zutaten durch Antippen bearbeiten und Kategorieaktionen bündeln.
- Beim Bestätigen von Einkaufs-Häkchen die Höhe vor den vorhandenen Einträgen
  konstant halten und Warenbereiche aus der Serverantwort verwenden.
- Listentitel sind aufklappbar und durchsuchbar. Kräftige Schrift und ein eigener
  Hintergrund unterscheiden sie von den zweispaltigen Rezeptkarten. Lokale
  Listen werden über das Bearbeiten-Symbol verwaltet. Sortierung und Filter sind in
  der globalen Rezeptansicht zusammen mit der Suche erreichbar.
- Rahmen umfassen Bild, Titel und Schwierigkeit aller Rezeptvorschauen.
  Übersicht, Bibliothek und Listen teilen sich das adaptive Raster. Rezeptlisten
  und Vorratskategorien zeigen dieselben getönten aufklappbaren Kopfzeilen.
  Die Listenbearbeitung zeigt vorhandene und hinzufügbare Rezepte unter
  „Alle Rezepte“ mit einer gemeinsamen Suche. Ein Plus in der oberen rechten
  Bildecke fügt Rezepte hinzu. Der Papierkorb rechts neben „In dieser Liste“ aktiviert das X an
  vorhandenen Karten. Sie wackeln außer bei reduzierter Bewegung. Das Häkchen
  beendet den Modus. Außerhalb davon öffnet die Karte die Rezeptdetails.
- Horizontales Wischen im Hauptinhalt wechselt zum benachbarten Eintrag der
  Navigation. Der horizontale `PageView` rastet mit Flutters Seitenphysik ein.
  Die Navigationsmarkierung wechselt beim Überqueren der Seitenmitte.
  Bei schnellen Richtungswechseln erst nach dem Einrasten den Zielbereich
  aktivieren und vorgemerkte Aktualisierungen ausführen. Die Test-APK wird
  im Flutter-Profilmodus mit der Paket-ID und Signatur des Testkanals gebaut.
  Prüfe schnelle Wische in beide Richtungen auch beim Loslassen kurz vor dem
  Ziel. Die Seite soll bis zum Ziel in Wischrichtung laufen.
  Geladene Tabs bleiben beim Wechsel bestehen und laden bei Datenänderungen
  oder auf Anforderung erneut. Tabtasten verwenden denselben `PageController`.
  Bei reduzierter Bewegung
  wechselt die Ansicht direkt. Der
  horizontale Tageswechsel und das seitliche Scrollen der Wochenablage in
  „Meine Woche“ haben in ihren Bereichen Vorrang. Die Ablage zeigt eine Reihe
  kompakter Karten mit Rezeptbild oder Platzhaltersymbol über dem Titel. Platzhalter- und Listengruppen haben dieselben Kopfzeilen und Abstände. In geöffneten Wochenlisten zeigen Rezeptpillen ein Vorschaubild und ein Plus für die Ablage.
  Einträge werden mit der vertikalen Wischgeste entfernt.
- Rezeptdetails zeigen kontrastreiche Vorratspunkte. Die Schaltfläche über
  „Heute kochen“ fügt das Rezept über die gemeinsame Kalender-API zur Ablage der
  aktuellen Berliner Kalenderwoche hinzu. Aktionsschaltflächen zeigen ein
  passendes Symbol und den Text als zentrierte Gruppe.
- Der Schalter „Debug-Modus“ ist auch offline in den Einstellungen verfügbar.
  Die Debug-Rezepte verwenden unterschiedliche mitgelieferte Vorschaubilder.
  Der Modus verwendet `DebugRezeptgartenApi` mit Beispieldaten für die normalen
  Ansichten und hält Änderungen bis zum Ende der App-Sitzung im Speicher. Die
  Auswahl des Modus bleibt über Neustarts erhalten. Im Debug-Modus bleiben
  Heimnetz, Telegram und die native Updateprüfung inaktiv. Prüfe Umschalten in
  beide Richtungen.
- Beide Clients nutzen die gemeinsamen Rezeptgarten-APIs, Cookidoo-Konten
  und Daten im bestehenden LXC. Der Android-API-Client vertraut der gebündelten
  Rezeptgarten-CA und setzt bei Schreibanfragen den passenden Origin. Beim
  Start und beim Einkaufswagen gilt die 2,5-Sekunden-Frist für den
  Erreichbarkeitscheck. Schreibvorgänge folgen der gemeinsamen
  Bestätigungs- und Konfliktbehandlung.
- Bei Öffnen und Rückkehr in die Android-App startet im Heimnetz ein
  Sammlungsabgleich; Herunterziehen einer Ansicht startet ihn ebenfalls
  und lädt nach Abschluss die Ansicht neu. Im Telegram-Modus lädt die
  Geste nur die verschlüsselte Momentaufnahme neu. Es gibt keinen
  zeitgesteuerten Sammlungsabgleich und keine Intervall-Einstellung.
- Android-Systemdienste erst nach dem Anhängen der Activity initialisieren.
  Den App-Start bei Änderungen am nativen Einstieg zusätzlich auf einer
  isolierten Android-Laufzeit prüfen, sofern eine verfügbar ist.
- Die APK enthält weder Bot-zu-Bot-Kommunikation noch Gemini oder eine
  Google-API-Schlüsselverwaltung. Die browserseitigen Integrationen gehören
  nicht mehr zur Web-App. Der Server-Bot dient der Benutzerkopplung. Änderungen an den gemeinsamen APIs mit dem Betriebs- und
  gegebenenfalls dem Cookidoo-Skill abgleichen.
- Android erkennt `ThomasWlan` mit Standortberechtigung und prüft den Server
  über die gebündelte CA. Fordere beim Wechsel von ungefährer zu genauer
  Standortfreigabe beide Standortberechtigungen gemeinsam erneut an.
  Außerhalb des Heimnetzes sowie bei nicht erreichbarem
  Server stehen Woche und Einkaufswagen nach Telegram-Benutzeranmeldung und
  bestätigter Kopplung lesend bereit. Der Einkaufswagen speichert Häkchen
  geräte- und kopplungsbezogen. Gespeicherte Häkchen vor Änderungen laden und
  erneutes Laden bei Speicherfehlern anbieten. Wochenwechsel mit Kalenderdaten
  berechnen und über die Berliner Zeitumstellung hinweg prüfen. TDLib verwendet
  die eingegebene eigene Telegram-API-ID und den API-Hash. Der Android-Keystore schützt Zugangsdaten und
  Geräteschlüssel, die TDLib-Sitzung liegt im Backup-ausgeschlossenen Bereich.
  Keine Zugangsdaten, Sitzungen oder Nachrichten in Git und Logs aufnehmen.
  Bei einer späteren Umstellung des Android-Ziel-SDK auf 37 oder höher die
  Laufzeitberechtigung `ACCESS_LOCAL_NETWORK` ergänzen und prüfen.
- Build und Veröffentlichung aus der Projektwurzel mit
  `scripts/Android-APK-veroeffentlichen.ps1`. Der WSL-Build prüft Flutter,
  führt die Widgettests aus und baut ARM64. Verwende eine steigende
  Buildnummer je Kanal und eine stabile Signatur. Test-App und Release
  haben unterschiedliche Paket-IDs und Downloadpfade. Das Skript lädt neue
  Builds standardmäßig auf LXC 103 und prüft HTTPS-Download und `latest.json`.
  Bei einem Uploadfehler mit `-UseExistingBuild` und derselben Buildnummer
  erneut veröffentlichen. Für ausdrücklich lokale Builds gilt `-Upload:$false`.
- Die manuelle Updateprüfung in den Einstellungen vergleicht den installierten
  `versionCode` mit `latest.json` des eigenen Kanals. Bei einem neueren Build
  wechselt derselbe Knopf zum Download und zur Installation. Die APK wird vor
  der Übergabe an den Android-Installer geprüft. Prüfe den veröffentlichten
  Kanal sowie Download, Quellenfreigabe und Installationsbestätigung, soweit
  eine vom Nutzer zugelassene Android-Laufzeit zur Verfügung steht.
