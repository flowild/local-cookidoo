# Rezeptgarten / local-cookidoo

## Auftrag und aktueller Stand

Wir bauen für den Nutzer eine private Cookidoo-Rezeptverwaltung, die im eigenen
Proxmox-LXC läuft. Die Web-App muss am Desktop und am Handy gut bedienbar sein und
sich über Chrome als PWA installieren lassen. Die Unterhaltung mit dem Nutzer ist
auf Deutsch. Arbeite in diesem Projekt; das frühere mqtt2PC-Projekt ist eine
andere Anwendung und soll für Cookidoo-Arbeit nicht mehr geändert werden.

Die aktuelle Version heißt **Rezeptgarten**. Sie übernimmt persönliche Rezeptlisten,
gespeicherte Cookidoo-Kollektionen und die **Merkliste** in SQLite, zeigt die darin
enthaltenen Rezepte und lädt deren echte Bilder in den lokalen Bildspeicher.
Suche, Listenansichten, eine Rezept-Detailansicht, JSON-Export und manuelle sowie
automatische Synchronisierung sind implementiert. Der letzte erfolgreiche
Live-Abgleich ergab **eine Merkliste mit 31 Rezepten und 31 Bildern**; das ist eine
Momentaufnahme, keine feste Datenvorgabe. Zutaten sind schon in `ingredients_json`
gespeichert; ihre nutzerfreundliche Anzeige ist der nächste gewünschte Ausbau.
Bidirektionale Cookidoo-Bearbeitung wurde als späteres Ziel besprochen, ist in
dieser ersten Version aber noch nicht implementiert.

## Workspace und private Dateien

- Projektwurzel: `D:\Github\local-cookidoo`. Das vorhandene `.git` wurde erhalten.
- `app/`: FastAPI-Backend, SQLite, Authentifizierung, Cookidoo-Sync und statische UI.
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
- `.qa-venv/`: lokale Python-Testumgebung mit Playwright; nutzt vorhandenes Edge.
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
  sieben rotierende SQLite-Sicherungen, `cookidoo.enc` und `vault.key`.
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

## Authentifizierung, HTTPS und PWA

Die lokale App hat ein eigenes Passwort, unabhängig vom Cookidoo-Konto.
Die vom Nutzer ausdrücklich gewünschte Mindestlänge ist **8 Zeichen**; Browser-
und Serverprüfung müssen übereinstimmen. Passwörter werden mit scrypt gehasht,
Sitzungstokens gehasht in SQLite gespeichert. Cookies sind produktiv Secure,
HttpOnly und SameSite Strict; schreibende API-Anfragen benötigen denselben Origin.

Die Ersteinrichtung ist bereits erfolgt. Ein neuer Einmalcode oder ein neuer
Administrator ist für Routinearbeiten nicht nötig. Bestehende Passwörter nicht
zurücksetzen, um Tests durchzuführen.

Chrome-PWA-Installation benötigt vertrauenswürdiges HTTPS. Der Nutzer hat keine
vorhandene Domain/keinen HTTPS-Reverse-Proxy und hat lokales HTTPS samt öffentlichem
CA-Zertifikat im Workspace ausdrücklich angefordert. Die CA muss pro Endgerät
manuell vertraut werden. Ihre globale Installation auf weiteren Rechnern nicht
ungefragt vornehmen. Zertifikat-Download: `http://192.168.184.30/zertifikat`.
Der Service Worker speichert nur die öffentliche App-Hülle; keine persönlichen
API-Antworten. Ohne Verbindung zum Server gibt es eine klare Verbindungsmeldung.
Bei statischen Änderungen kann ein Neuladen der Seite nötig sein.

## Prüfungen und weitere Arbeit

- Backendtests: `python -m unittest discover -s tests -v`, auf dem Server mit
  `/opt/cookidoo-manager/.venv/bin/python` aus `/opt/cookidoo-manager/source`.
  Zuletzt **10 Tests bestanden**, darunter Bookmark-Paginierung, sichere Anmeldung,
  atomarer Import, Bildnormalisierung, Datenschutz und Erhalt bei Netzwerkfehlern.
- Die 8-Zeichen-Grenze wurde separat in einer temporären Datenbank geprüft:
  sieben Zeichen abgewiesen, acht akzeptiert und anschließender Login erfolgreich.
- Desktop- und Mobil-Browserprüfung sowie PWA-Installierbarkeit wurden mit dem
  vorhandenen Edge geprüft; Chromium meldete keine Installationshindernisse.
- Lokale QA-Befehle über `.qa-venv/Scripts/python.exe` bzw. `python -m pip` ausführen.
  Der Browsercheck `tests/browser_check.py` erwartet eine **getrennte**, vorbereitete
  QA-Instanz im Container auf Loopback-Port 8901 und nutzt einen SSH-Tunnel.
  Diese Testinstanz und ihre künstlichen Daten wurden anschließend entfernt.
  Nicht die produktive Datenbank zum Befüllen mit Testrezepten oder zum Einrichten
  eines Testkontos verwenden. Bilder in `test-results/` können Fixtures darstellen.
- Den echten Cookidoo-Import nicht nur mit leeren Fake-Listen testen. Live waren
  die Merkliste und alle 31 Rezeptbilder erfolgreich lesbar.
- Nächster gewünschter Funktionsschritt: Zutaten in der Rezeptansicht darstellen.
  Die bestehende Datenstruktur und das mobile Layout dafür weiterverwenden.
