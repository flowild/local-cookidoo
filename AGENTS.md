# Rezeptgarten / local-cookidoo

## Diese Datei aktuell halten

Bei jeder relevanten Änderung an Funktionen, Betrieb, Sicherheit, Tests oder
Deployment diese Datei prüfen und im selben Arbeitsgang aktualisieren. Veraltete
Aussagen ersetzen statt widersprüchliche Ergänzungen anzuhängen. Momentaufnahmen
als solche kennzeichnen; keine Zugangsdaten oder persönlichen Rezeptdaten aufnehmen.

## Auftrag und aktueller Stand

Wir bauen für den Nutzer eine private Cookidoo-Rezeptverwaltung, die im eigenen
Proxmox-LXC läuft. Die Web-App muss am Desktop und am Handy gut bedienbar sein und
sich über Chrome als PWA installieren lassen. Die Unterhaltung mit dem Nutzer ist
auf Deutsch. Arbeite in diesem Projekt; das frühere mqtt2PC-Projekt ist eine
andere Anwendung und soll für Cookidoo-Arbeit nicht mehr geändert werden.

**Rezeptgarten** synchronisiert Cookidoo-Listen, Kollektionen, Merkliste und eigene
Kreationen in SQLite und speichert echte Rezeptbilder lokal. Die App bietet Suche,
Rezeptdetails, JSON-Export sowie manuelle und automatische Synchronisierung.

- Cookidoo-Listen und selbst angelegte lokale Rezeptlisten werden getrennt gezeigt;
  lokale Listen werden nicht mit Cookidoo synchronisiert. Rezepte lassen sich in
  lokalen Listen hinzufügen und öffnen. Zugeordnete Rezeptversionen werden gemeinsam
  angezeigt und können in der Detailansicht ausgewählt werden.
- In Rezeptlisten gibt es Sortierung und Filter für Zutaten, Portionen und Gesamtzeit.
  Nicht passende Rezepte bleiben ausgegraut sichtbar; das gilt auch für die Liste
  weiterer hinzufügbarer Rezepte. Die Zutatenfilter unterstützen Mehrfachauswahl.
- Die Suche im Header durchsucht Rezepttitel und Zutaten einschließlich bekannter
  Zutaten-Aliasse; Titeltreffer erscheinen vor reinen Zutatentreffern. Gewählte
  Sortierung, Listenfilter und gruppierte Rezeptversionen bleiben berücksichtigt.
- „Mein Vorrat“ verwaltet Zutaten in Kategorien mit Icons, alphabetischen Einträgen,
  einklappbaren und per Griff sortierbaren Kategorien sowie Vorschlägen aus den
  gespeicherten Rezeptzutaten. Die Rezeptansicht markiert verfügbare Zutaten. Die
  Abgleichregeln in `app/ingredients.py` berücksichtigen u. a. Synonyme, englische
  Begriffe, passende Speiseöle und Wasser. Mengen werden noch nicht abgeglichen.
- Die Übersicht zeigt ein täglich wechselndes Zufallsrezept und eine Schaltfläche für
  eine neue Auswahl. Dunkelmodus und Akzentfarbe gelten browserbezogen.
- In den Einstellungen kann ein Google-API-Schlüssel gesetzt, ersetzt und entfernt
  werden. Er wird getrennt vom Cookidoo-Token verschlüsselt in `google-api-key.enc`
  gespeichert und über die API nicht wieder ausgegeben; der Status enthält nur, ob
  ein Schlüssel hinterlegt ist. Der Server kann ihn für spätere Funktionen mit
  `vault.key` entschlüsseln. Noch ist keine Google-Funktion angebunden.
- „Heute kochen“ plant die ausgewählte Version für das heutige Berliner Datum in
  Cookidoo ein und prüft den Kalendereintrag anschließend erneut. „Zur Einkaufsliste
  hinzufügen“ schreibt in die Cookidoo-Einkaufsliste und markiert als vorhanden
  erkannte Zutaten. Eigene Kreationen verwenden die passenden separaten Methoden.
  Ein teilweiser Fehler bei der Markierung muss dem Nutzer klar angezeigt werden.
  Die Aktionen sind gezielte Schreibzugriffe, keine allgemeine bidirektionale
  Synchronisierung aller Daten; Rezeptgarten hat derzeit keine eigene Einkaufslistenansicht.

## Workspace und private Dateien

- Projektwurzel in der aktuellen Umgebung: `C:\Github\local-cookidoo`; ein früherer
  Workspace lag unter `D:\Github\local-cookidoo`. Das vorhandene `.git` wurde erhalten.
- `app/`: FastAPI-Backend, SQLite, Cookidoo-Sync, Zutatenabgleich und statische UI.
- `app/static/`: responsive HTML/CSS/JavaScript-Oberfläche, Manifest, Service Worker,
  originale Bowl/Leaf-App-Icons. Kein Node-Build erforderlich.
- `deploy/`: systemd-Dienst, Caddy-Konfiguration und Installation im Container.
- `scripts/deploy.py`: SSH-Übertragung und Backendtests; `--install` richtet auch
  Dienste/Caddy ein und startet sie neu.
- `tests/`: Backend-Regressionstests und Browserprüfung.
- `certificates/Rezeptgarten-CA.crt`: öffentliches lokales CA-Zertifikat; ergänzende
  Metadaten stehen in `certificate-info.json`. Der Nutzer wollte diese Dateien
  ausdrücklich im Workspace haben.
- `.local/proxmox/`: Container-Metadaten, historische Provisionierungshelfer und
  `access/` mit SSH-Schlüssel, `known_hosts` und dem alten Einrichtungslink.
- `.qa-venv/`: historische lokale Python-Testumgebung; ihr Interpreterpfad war in
  der aktuellen Windows-Umgebung zuletzt nicht mehr gültig und muss ggf. repariert
  werden. Edge ist für Browserprüfungen vorhanden.
- `test-results/`: Screenshots/Browserartefakte, teilweise mit künstlichen Testdaten.
- `.local/migration.json`: Integritätsnachweis der lokalen Verschiebung.

`.local/`, `.qa-venv/`, Datenbanken, Token-Dateien, Zertifikatsartefakte und
Testergebnisse sind von Git ausgeschlossen. Insbesondere hat der private
SSH-Schlüssel keinen `.key`-Suffix: Sein Schutz beruht auf dem Ausschluss des
gesamten `.local/`-Verzeichnisses und den beibehaltenen Windows-Zugriffsrechten.
Deploy-Archive müssen `.local/`, `.git/`, virtuelle Umgebungen, persönliche Daten,
Zertifikatsartefakte und Screenshots auslassen. Keine Schlüssel oder Tokens in
Quellcode, Logs, Antworten oder Git aufnehmen. Keine privaten CA-Schlüssel vom
Server in den Workspace kopieren. Der alte Einrichtungslink enthält einen
bereits verwendeten Einmalcode und ist kein regulärer Login-Link.

## Laufende Installation

- Proxmox-Host: `192.168.184.2`, Knoten `pve`; Proxmox beim Aufbau 9.1.4.
- LXC: **103**, Hostname `cookidoo-manager`, unprivilegiert, Nesting aktiviert.
  Der Nutzer hat Nesting ausdrücklich genehmigt, um Debian-Mount-Dienste zu beheben.
- Ressourcen: 2 CPU-Kerne, 2 GiB RAM, 512 MiB Swap, 16 GiB auf `local-lvm`.
- App-Adresse: **https://192.168.184.30**.
- LAN-Bridge `vmbr0`; IPv4 kommt derzeit per DHCP. MAC `BC:24:11:96:6F:AA`.
  Eine Router-Reservierung wurde empfohlen, nicht durch uns eingerichtet.
- App-Quellcode: `/opt/cookidoo-manager/source`.
- Python-Umgebung: `/opt/cookidoo-manager/.venv`; Python 3.13.
- Dienstbenutzer: `cookidoo`; systemd-Dienst `rezeptgarten`.
- Backend hört nur auf `127.0.0.1:8000`; Caddy bedient die LAN-IPv4 auf 80/443.
- Caddy-Dienst: `caddy`, interne lokale CA, automatische TLS-Erneuerung.
- Produktive Daten: `/var/lib/cookidoo-manager`: `library.sqlite3`, Bilder,
  sieben rotierende SQLite-Sicherungen, `cookidoo.enc`, bei Bedarf
  `google-api-key.enc` und `vault.key`.
- Separates vorbereitetes Backup-Verzeichnis: `/var/backups/cookidoo-manager`.
- Zeitzone: `Europe/Berlin`.

Die Verschiebung betraf lokale Workspace-Dateien. Produktive Daten und Dienste
bleiben im Container. Für Sicherungen der vollständigen Anwendung reicht ein
JSON-Export oder eine einzelne SQLite-Datei nicht: Bilder, Schlüssel und
verschlüsselte Sitzung gehören zur privaten Sicherung des Datenverzeichnisses.

## SSH statt Proxmox-Token

Der Proxmox-API-Token wurde nur zum Erstellen des Containers benötigt. Der Nutzer
durfte ihn danach entfernen. Für normale App-Arbeit ist **kein Proxmox-Token nötig**.
Die historischen Provisionierungsskripte nicht auf den existierenden Container
loslassen und keine weitere Instanz erzeugen.

Aus der Projektwurzel funktioniert der Zugang mit dem vorhandenen Schlüssel:

```powershell
ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=.local/proxmox/access/known_hosts -i .local/proxmox/access/id_ed25519 root@192.168.184.30
```

Die privaten Dateien können wegen ihrer Windows-ACL nur mit dem Benutzerzugriff
lesbar sein, unter dem sie erstellt wurden; ihre Berechtigungen nicht pauschal
öffnen. Netzwerk-/Dateisystem-Eskalationen der Ausführungsumgebung sind getrennt
von den Linux-/SSH-Berechtigungen zu behandeln. Fingerabdruck-Prüfung beibehalten.
Für mehrzeilige SSH-Eingaben binäre UTF-8-Eingabe mit Python `subprocess.run`
verwenden: Eine PowerShell-Textpipeline führte zuvor zu einem zusätzlichen CR und
einem irreführenden Shell-Fehler am Ende eines ansonsten erfolgreichen Skripts.

`python scripts/deploy.py` überträgt den Quellcode und führt Backendtests aus;
es startet den vorhandenen App-Dienst allein noch nicht neu. Bei Backendänderungen
danach `systemctl restart rezeptgarten` ausführen und den Zustand prüfen.
`python scripts/deploy.py --install` ist die vollständige Installation mit
Paketinstallation und Dienst-Neustarts. Für kleine Änderungen passende gezielte
Übertragung/Prüfung verwenden. Bestehende Daten und Konten erhalten.

## Cookidoo-Anbindung: wichtige Erkenntnisse

`cookidoo-api==0.19.0` ist fest gepinnt. Die aktuelle `cookidoo-migrate`-Integration
hat teilweise ältere Cookie-/Konstanten-Imports und wird nicht unverändert
eingebunden. Lizenzhinweise für cookidoo-api stehen in `THIRD-PARTY-NOTICES.txt`.

- Das vorhandene Konto ist für Deutschland (`cookidoo.de`, `de-DE`) verbunden.
  Zugangsdaten nur für die eingerichtete/autorisierten Zieladresse verwenden.
  Ein probeweiser Abruf bei `cookidoo.international` wurde von der automatischen
  Freigabeprüfung als nicht autorisierte Weitergabe von Sitzungstokens abgelehnt.
  Dieser Abruf war zur Lösung nicht erforderlich und wurde nicht ausgeführt.
- Die Merkliste ist ein **separater Endpunkt**. Null persönliche/verwaltete Listen
  bedeutet nicht, dass das Konto keine gespeicherten Rezepte enthält. Dies war
  der erste Live-Importfehler; ein Regressionstest deckt ihn jetzt ab.
- `count_custom_collections()` und `count_managed_collections()` liefern
  `(totalElements, totalPages)`; alle Seiten lesen.
- Der Bookmark-Adapter in `SyncService.bookmarks()` nutzt den privaten, aber
  Token-Refresh-fähigen `_request_json`-Helfer der gepinnten Bibliothek für
  `organize/{language}/api/bookmark`. Alle Seiten lesen und Rezept-IDs deduplizieren.
- Listeneinträge haben keine Bilder. `get_recipe_details(id)` liefert Details,
  Bild-URLs, Zeiten in Sekunden und Zutaten. Bilder werden von erlaubten
  HTTPS-Assethosts ohne Cookidoo-Authorization heruntergeladen, zu WebP bis
  960 Pixeln normalisiert und lokal gespeichert. Keine erfundenen Rezeptbilder.
- Login verwendet das Cookidoo-Passwort nur vorübergehend. Nach erfolgreichem
  Login wird auch `cfg.password` geleert. OAuth-Tokens sind mit Fernet verschlüsselt;
  bei **jeder** Erneuerung speichern, weil Refresh-Tokens rotieren.
- Nicht mehrere unabhängige Clients mit denselben rotierenden Tokens parallel
  betreiben. Für notwendige separate Diagnose die App kontrolliert pausieren und
  anschließend mit dem aktuellen Tokenstand neu starten, oder ihren bestehenden
  Sync über die lokale API nutzen. Keine Tokens oder Kontopasswörter ausgeben.
- Ein vollständiger Listen-Snapshot wird atomar gespeichert. Fehler beim Laden
  müssen die bisherige Sammlung erhalten. Einzelne nicht verfügbare Rezeptdetails
  dürfen Listeneinträge nicht verschwinden lassen.
- Cookidoo-Aktionen nutzen den vorhandenen Client und denselben Lock wie der Sync.
  IDs eigener Kreationen tragen intern den Präfix `creation:`, der für Cookidoo
  entfernt wird. Kalender und Einkaufsliste nur auf ausdrückliche Nutzeraktion
  beschreiben; bei Tests isolierte Daten und Mocks verwenden. Ein lesender Live-Abruf
  bestätigte am 31.10.2026 einen von Rezeptgarten eingetragenen Kalendertag; die
  Anzeige in der Cookidoo-App kann dennoch ein Aktualisieren erfordern.

## Lokaler Zugriff, HTTPS und PWA

Der Nutzer hat das Passwort für den lokalen App-Zugang ausdrücklich entfernen
lassen. Rezeptgarten ist im lokalen Netz ohne App-Anmeldung erreichbar; das
Cookidoo-Konto bleibt davon unabhängig. Schreibende API-Anfragen benötigen denselben
Origin. Eine lokale Passwortpflicht oder Ersteinrichtung nicht ungefragt wieder
einführen. Historische Authentifizierungshilfen und Tabellen können noch existieren.

Chrome-PWA-Installation benötigt vertrauenswürdiges HTTPS. Der Nutzer hat keine
vorhandene Domain/keinen HTTPS-Reverse-Proxy und hat lokales HTTPS samt öffentlichem
CA-Zertifikat im Workspace ausdrücklich angefordert. Die CA muss pro Endgerät
manuell vertraut werden. Ihre globale Installation auf weiteren Rechnern nicht
ungefragt vornehmen. Zertifikat-Download: `http://192.168.184.30/zertifikat`.
Der Service Worker speichert nur die öffentliche App-Hülle; keine persönlichen
API-Antworten. Ohne Verbindung zum Server gibt es eine klare Verbindungsmeldung.
Bei statischen Änderungen kann ein Neuladen der Seite nötig sein.
Bei Änderungen an versionierten statischen Dateien auch die zugehörigen URLs in
`index.html` und `sw.js` sowie die Service-Worker-Cacheversion konsistent erhöhen.
Statusmeldungen müssen auch über geöffneten modalen Dialogen sichtbar bleiben.

## Prüfungen und weitere Arbeit

- Backendtests: `python -m unittest discover -s tests -v`, auf dem Server mit
  `/opt/cookidoo-manager/.venv/bin/python` aus `/opt/cookidoo-manager/source`.
  Zuletzt **39 Tests bestanden**, darunter Sync, Zutatenabgleich, lokale Listen,
  Cookidoo-Aktionen und Erhalt bei Netzwerkfehlern. Für Prüfungen auf dem Server
  eine isolierte Kopie des Quellcodes und temporäre Testdaten verwenden.
- Desktop- und Mobil-Browserprüfung sowie PWA-Installierbarkeit wurden mit dem
  vorhandenen Edge geprüft; Chromium meldete keine Installationshindernisse.
- Der Browsercheck `tests/browser_check.py` erwartet eine **getrennte**, vorbereitete
  QA-Instanz im Container auf Loopback-Port 8901 und nutzt einen SSH-Tunnel.
  Diese Testinstanz und ihre künstlichen Daten wurden anschließend entfernt.
  Nicht die produktive Datenbank zum Befüllen mit Testrezepten oder zum Einrichten
  eines Testkontos verwenden. Bilder in `test-results/` können Fixtures darstellen.
- Den echten Cookidoo-Import nicht nur anhand leerer Fake-Listen beurteilen. Ein
  früherer Live-Abgleich mit Merkliste und 31 Bildern ist nur eine Momentaufnahme.
