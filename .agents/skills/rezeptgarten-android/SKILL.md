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
- Verwende `AppSpacing` für Seiten- und Kartenränder, Abschnitte sowie Abstände
  zwischen zusammengehörigen Bedienelementen. Verbundene Schalter und Abzeichen
  verwenden die kompakten Werte. Listenkarten erhalten ihren Abstand im Layout.
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
  Wischhinweise erscheinen während der Geste. Einkaufs-Häkchen brauchen
  keinen dauerhaft sichtbaren Erklärungstext.
- Hauptansichten beim Tabwechsel bedarfsgerecht erhalten und Hintergrundarbeit
  auf den sichtbaren Tab begrenzen. Bei Änderungen der Kontoverbindung und
  beim Verlassen des Heimnetzmodus private Ansichtsdaten und Bildcache leeren.
- Bilder getrennt nach Vorschau und Original laden. Gleichzeitige Bildabrufe
  bündeln, die Cachefreigabe des Servers beachten und den Speicher begrenzen.
  Die Dekodierungsgröße an die physische Anzeigebreite anpassen.
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
- Listentitel sind aufklappbar und durchsuchbar. Sortierung und Filter sind in
  der globalen Rezeptansicht zusammen mit der Suche erreichbar.
- Der Schalter „Debug-Modus“ ist auch offline in den Einstellungen verfügbar.
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
  haben unterschiedliche Paket-IDs und Downloadpfade. Mit `-Upload` prüft
  das Skript den HTTPS-Download und sein `latest.json` auf LXC 103.
- Die manuelle Updateprüfung in den Einstellungen vergleicht den installierten
  `versionCode` mit `latest.json` des eigenen Kanals. Bei einem neueren Build
  wechselt derselbe Knopf zum Download und zur Installation. Die APK wird vor
  der Übergabe an den Android-Installer geprüft. Prüfe den veröffentlichten
  Kanal sowie Download, Quellenfreigabe und Installationsbestätigung, soweit
  eine vom Nutzer zugelassene Android-Laufzeit zur Verfügung steht.
