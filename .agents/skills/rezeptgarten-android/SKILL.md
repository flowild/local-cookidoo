---
name: rezeptgarten-android
description: Entwickle, prüfe und veröffentliche die native Rezeptgarten-App in android-app mit Flutter, Android-Installer und APK-Downloads auf LXC 103.
---

# Rezeptgarten für Android

Telegram-API-ID und API-Hash werden verschlüsselt auf dem Server gespeichert. Die Web-Einstellungen schalten den HTTPS-Abruf im Heimnetz für neue Android-Apps frei. Android bietet die Übernahme bei der Einrichtung an.

Die Lupe öffnet die separate Suche mit der auf der Übersicht gewählten Quelle und einem Lokal-/Cookidoo-Schalter. Im Telegram-Modus ist die Cookidoo-Suche gesperrt. Das Zufallsrezept kann auch im Telegram-Modus aus Cookidoo stammen. Katalogdetails sind lesend, Katalogbilder werden im Heimnetz geladen.

Die Android-Versionsnummer in den Einstellungen öffnet den mitgelieferten Änderungsverlauf assets/changelog.txt. Relevante Änderungen ergänzen ihn. Beim Öffnen und Wiederöffnen im Heimnetz prüft die App automatisch auf APK-Updates. Ein neuer Build zeigt die Downloadaktion neben der Suche. Sie teilt ihren Zustand mit der manuellen Prüfung in den Einstellungen.

- Nutze [FLUTTER-PORTIERUNG.md](../../../docs/android/FLUTTER-PORTIERUNG.md) für Umfang,
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
- Auf Start steht die Quellenwahl für das Zufallsrezept rechts neben „Dein Rezeptmix“. Bei knapper Breite brechen Schalter und Beschriftung gemeinsam um. „Deine Sammlung“ folgt direkt auf das Zufallsrezept.
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
  Die Wochenleiste zeigt die ISO-Kalenderwoche als Text zwischen umrandeten
  Wochenpfeilen. Eine kurze Linie markiert die laufende Woche. „Heute“
  steht neben den Pfeilen. Danach folgt der Drehknopf für Hoch- und Querformat,
  und der Einkaufswagen schließt die Zeile bündig am rechten Inhaltsrand ab.
  Die App startet im Hochformat und behält die manuell gewählte Ausrichtung
  auch beim Drehen des Geräts und beim Tabwechsel bei. Die
  aktuelle Berliner Woche und der heutige Tageskopf sind hervorgehoben.
  „Heute“ wählt in beiden Modi den heutigen Tag der aktuellen Woche im
  Kalender aus.
  Im Querformat nutzt die Woche kompakte Tagesspalten mit festen Tagesköpfen
  und eigenen vertikalen Listen. Bei großer Schrift bleiben die Spalten lesbar
  und lassen sich seitlich scrollen. „Heute“ holt seinen Tag ins Sichtfeld.
  Ablage, Platzhalter und lokale Listen sind unter den Spalten erreichbar.
  Ein Eintrag öffnet die Tagesauswahl für die gemeinsame Wochenwarteschlange
  oder die lokale Platzhalterablage. Die Hochformatgesten bleiben verfügbar.
  Wischhinweise erscheinen während der Geste. Einkaufs-Häkchen brauchen
  keinen dauerhaft sichtbaren Erklärungstext.
- Hauptansichten beim Tabwechsel bedarfsgerecht erhalten und Hintergrundarbeit
  auf den sichtbaren Tab begrenzen. Beim erneuten Laden sichtbarer Listen,
  Vorratskategorien oder Wocheninhalte ihre Position beibehalten. Bei Änderungen der Kontoverbindung und
  bei einem Wechsel des Verbindungsmodus private Ansichtsdaten und den
  Bildcache im Arbeitsspeicher leeren.
  Identische Android-Netzmeldungen im bestätigten Heimnetz überspringen.
  Bei der Rückkehr zur App die Verbindung im Hintergrund prüfen und den
  Sammlungsabgleich einmal anstoßen. Die lokale Ansicht bleibt dabei bedienbar.
  Titel, Suche und datenunabhängige Aktionen sofort anzeigen und die einzelnen
  Antworten in die sichtbare Ansicht einsetzen. Start zeigt Sammlung und
  Rezeptantworten unabhängig. Im Kalender darf der Warteschlangenstatus
  die Anzeige der Termine nicht blockieren. Änderungen am Kalender brauchen
  den bestätigten Stand. Beim Laden keine falschen leeren Ergebnisse anzeigen.
- Bilder getrennt nach Vorschau und Original laden. Gleichzeitige Bildabrufe
  bündeln, die Cachefreigabe des Servers beachten und den Speicher begrenzen.
  Die Dekodierungsgröße an die physische Anzeigebreite anpassen. Freigegebene
  Bilder kontobezogen im privaten Verzeichnis ohne Backups speichern.
  Vorschaubilder der Sammlung beim Öffnen im Heimnetz und nach dem
  Sammlungsabgleich im Hintergrund laden. Unterwegs vorhandene Dateien
  verwenden. Fehlende Dateien behalten bis zum Heimnetzabruf den Platzhalter.
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
  beim Scrollen aufbauen. Das Eingabeblatt für Zusatzartikel schlägt beim Tippen
  passende Vorratsartikel mit Symbol vor und akzeptiert freie Eingaben.
  Der Cookidoo-Transfer steht als Symbol mit Tooltip neben dem Wagentitel.
  Rezepte erscheinen mit derselben runden Vorschau wie in den Wochenlisten.
  Im Vorrat Zutaten durch Antippen bearbeiten und Kategorieaktionen bündeln.
  Vorratskategorien starten eingeklappt. Der Zustand bleibt beim Tabwechsel
  und erneuten Laden innerhalb der App-Sitzung erhalten. Die Suche öffnet Treffer.
  „Zutat hinzufügen“ nutzt die volle Inhaltsbreite mit den üblichen Seitenabständen.
  Zutaten, Kategorien und lokale Listen verwenden dasselbe Symbolfeld beim
  Anlegen und Bearbeiten. Die Auswahl umfasst Lebensmittel, Haushalt und
  Rezeptlisten. Bei lokalen Listen steht der Editor in der Verwaltung. Das
  gewählte Listensymbol erscheint auch in der Woche und in Rezeptdetails.
  Warenbereiche im Einkaufswagen zeigen auch über Telegram ein Symbol am
  Gruppentitel. Verwende das Serversymbol oder für ältere Antworten und
  Testdaten das passende Standardsymbol. Gewählte Vorratssymbole haben Vorrang.
  Kategorie- und Zutatenzeilen verwenden eine feste Symbolspalte und eine
  gemeinsame linke Textkante. Menüs und Aufklappsymbole stehen rechts.
- Einkaufs-Häkchen sofort sichtbar ändern und im Hintergrund speichern.
  Bis zur Bestätigung die Zeile an ihrer Position halten und weitere Zutaten
  bedienbar lassen. Den Serverstand bei Konflikten übernehmen und den
  Cookidoo-Transfer erst nach den ausstehenden Änderungen freigeben.
- Listentitel sind aufklappbar und durchsuchbar. Kräftige Schrift und ein eigener
  Hintergrund unterscheiden sie von den zweispaltigen Rezeptkarten.
  Langes Drücken auf einen Titel startet das Verschieben. Die Titel wackeln
  bei aktiven Animationen und zeigen einen Griff. Android speichert die
  Reihenfolge nach Listen-ID in den Geräteeinstellungen.
  Importierte Cookidoo-Listen zeigen neben dem Titel „Zu Cookidoo“ und öffnen
  die vom Server gelieferte HTTPS-Adresse über den vorhandenen Android-Linkkanal.
  Lokale Listen werden über das Bearbeiten-Symbol verwaltet. Sortierung und Filter sind in
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
  kompakter Karten mit Bild über dem Titel. Verwende für Platzhalter in Tagen,
  Ablage und Auswahlliste die Bilder der Web-App. Das Skript
  `scripts/generate_week_placeholder_assets.py` erzeugt daraus die in der APK
  gebündelten WebP-Dateien. Platzhalter- und Listengruppen haben dieselben Kopfzeilen und Abstände. In geöffneten Wochenlisten zeigen Rezeptpillen ein Vorschaubild und ein Plus für die Ablage.
  Einträge werden mit der vertikalen Wischgeste entfernt.
- Rezeptdetails zeigen kontrastreiche Vorratspunkte. Die Schaltfläche über
  „Diese Woche kochen“ fügt das Rezept über die gemeinsame Kalender-API zur Ablage der
  aktuellen Berliner Kalenderwoche hinzu. Aktionsschaltflächen zeigen ein
  passendes Symbol und den Text als zentrierte Gruppe.
  „Diese Woche kochen“ bietet mehrere Termine von heute bis Sonntag zur Auswahl.
  „Zu lokalen Listen hinzufügen“ steht zwischen Einkaufswagen und Cookidoo-Link.
  Die Aktion öffnet ein scrollbares Fenster von unten,
  lädt darin die lokalen Listen und aktualisiert nach Serverbestätigung die
  Auswahl und die Listenzuordnungen über dem Rezepttitel.
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
  und lädt nach Abschluss die Ansicht neu. Der Fortschritt des manuellen
  Abgleichs erscheint in der heruntergezogenen Ansicht. Im Telegram-Modus
  löst die Geste denselben Abgleich aus. Es gibt keinen
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
  Server stehen nach Telegram-Benutzeranmeldung und bestätigter Kopplung
  dieselben sechs Hauptansichten und Bearbeitungsfunktionen bereit.
  Konto- und Kopplungsverwaltung sowie APK-Updates bleiben im Heimnetz.
  Die Einstellungen zeigen „WLAN-Erkennung einrichten“ bei fehlender genauer
  Berechtigung. Telegram braucht Anmeldung und Kopplung. Sobald beides vorliegt,
  öffnet die Statuszeile die Verwaltung.
  Beide Modi verwenden die serverseitigen Einkaufs-Häkchen. Häkchen aus dem
  früheren Telegram-Modus bleiben in dessen Gerätespeicher.
  Wochenwechsel mit Kalenderdaten
  berechnen und über die Berliner Zeitumstellung hinweg prüfen. TDLib verwendet
  die eingegebene eigene Telegram-API-ID und den API-Hash. Der Android-Keystore schützt Zugangsdaten und
  Geräteschlüssel, die TDLib-Sitzung liegt im Backup-ausgeschlossenen Bereich.
  Keine Zugangsdaten, Sitzungen oder Nachrichten in Git und Logs aufnehmen.
  Im Rezeptgarten-Bot-Chat bei eingehenden und erfolgreich gesendeten
  Nachrichten sofort TDLibs Lesemarkierung anfordern. Fehler dabei dürfen
  den Rezeptabruf nicht unterbrechen. Den Absender eingehender Nachrichten
  und die Chat-ID vor der Anforderung prüfen.
  Bei einer späteren Umstellung des Android-Ziel-SDK auf 37 oder höher die
  Laufzeitberechtigung `ACCESS_LOCAL_NETWORK` ergänzen und prüfen.
- Der reguläre Release-Schlüssel liegt außerhalb von Git unter `.local/release-signing/`. Die lokale Datei `android-app/android/release-signing.properties` enthält die Build-Konfiguration. Für Updates beide geschützt erhalten.
- Künftige Veröffentlichungen verwenden standardmäßig ausschließlich den regulären Release-Kanal.
- Build und Veröffentlichung aus der Projektwurzel mit
  `scripts/Android-APK-veroeffentlichen.ps1`. Der WSL-Build prüft Flutter,
  führt die Widgettests aus und baut ARM64. Verwende eine steigende
  Buildnummer je Kanal und eine stabile Signatur. Test-App und Release
  haben unterschiedliche Paket-IDs und Downloadpfade. Auf dem Gerät heißen
  beide „Rezeptmix“. Der Launcher verwendet ab Android 8 das adaptive
  `ic_launcher` mit fast schwarzem Hintergrund und einer separaten Form für
  Themensymbole. Android färbt Themensymbole nach dem Geräte-Design ein.
  Ältere Launcher und die Kopfzeile verwenden die mit
  `scripts/generate_icons.py` aus dem PWA-Icon erzeugten PNGs.
  Das Veröffentlichungsskript lädt neue
  Builds standardmäßig auf LXC 103 und prüft HTTPS-Download und `latest.json`.
  Bei einem Uploadfehler mit `-UseExistingBuild` und derselben Buildnummer
  erneut veröffentlichen. Für ausdrücklich lokale Builds gilt `-Upload:$false`.
- Die manuelle Updateprüfung in den Einstellungen vergleicht den installierten
  `versionCode` mit `latest.json` des eigenen Kanals. Bei einem neueren Build
  wechselt derselbe Knopf zum Download und zur Installation. Die APK wird vor
  der Übergabe an den Android-Installer geprüft. Prüfe den veröffentlichten
  Kanal sowie Download, Quellenfreigabe und Installationsbestätigung, soweit
  eine vom Nutzer zugelassene Android-Laufzeit zur Verfügung steht.
