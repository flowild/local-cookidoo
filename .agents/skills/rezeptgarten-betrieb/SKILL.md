---
name: rezeptgarten-betrieb
description: Teste, deploye, betreibe oder diagnostiziere die vorhandene Rezeptgarten-Installation im Proxmox-LXC, einschließlich SSH und PWA.
---

# Rezeptgarten-Betrieb

Die bereitgestellte App-Version steht in `app/version.py` und kann über
`/api/health` geprüft werden. Versionsänderungen nach Prüfung und Deployment
mit den zugehörigen Änderungen committen und nach `origin/main` pushen.

Der Dienst `rezeptgarten-telegram` auf dem Proxmox-Host liest das verschlüsselte
Server-Bot-Token über `pct exec` aus LXC 103 und verarbeitet ausschließlich frische
private Anfragen des bestätigten Android-Telegram-Benutzerkontos. Eine kurzlebige
Kennung bestätigt die im Heimnetz gestartete Kopplung. Vor jeder Antwort wird die
Kopplung erneut geprüft. Einkaufswagen und Woche werden kontogebunden im Container
gelesen und vor der Weitergabe mit AES-256-GCM verschlüsselt. Der Telegram-Offset
liegt unter `/var/lib/rezeptgarten-telegram`. Keine Tokens, Schlüssel oder Nachrichten
protokollieren. Bridge-Änderungen auf dem Host unter
`/opt/rezeptgarten-telegram/telegram_bridge.py` bereitstellen und den Dienst neu
starten. Der Server entfernt beim Start alte Bot-Kopplungen und behält eine bereits
bestätigte Android-Benutzerkopplung.

Die bestehende private Instanz läuft unter `https://192.168.184.30` im unprivilegierten
LXC 103 `cookidoo-manager`, Zeitzone `Europe/Berlin`. Backend: `/opt/cookidoo-manager/source`,
Python: `/opt/cookidoo-manager/.venv`, systemd-Dienst `rezeptgarten`, Nutzer
`cookidoo`, Backend nur auf `127.0.0.1:8000`; Caddy bedient HTTP/HTTPS.
Proxmox-Host `192.168.184.2`, Knoten `pve`. Keinen neuen Container erstellen und
historische Provisionierungsskripte nicht auf den bestehenden Container anwenden.

Produktive Daten liegen unter `/var/lib/cookidoo-manager`: SQLite, Bilder,
rotierende SQLite-Sicherungen, `cookidoo.enc`, gegebenenfalls `google-api-key.enc`
und `vault.key`. Ein vollständiges privates Backup muss auch Bilder, Schlüssel und
verschlüsselte Sitzung enthalten. Die vorbereitete Backupablage ist
`/var/backups/cookidoo-manager`. Private CA-Schlüssel nie in den Workspace kopieren.

## Zugang und Deployment

Android-Testbuilds werden lokal mit `scripts/Android-APK-veroeffentlichen.ps1`
in WSL gebaut und bei `-Upload` auf dem bestehenden LXC 103 veröffentlicht.
Der Testkanal verwendet die ARM64-Profil-APK mit der bestehenden Testsignatur
und der Paket-ID `de.rezeptgarten.rezeptgarten.test`.
Caddy bedient die Testseite unter `/android/test/` und den regulären Download
unter `/android/`. Der Upload wird in `/var/lib/rezeptgarten-downloads/.incoming`
geprüft und erst danach freigegeben. Danach aktualisiert der Publisher
Downloadseite und `latest.json` je Kanal atomar. Das Build-Skript gleicht den
erneut per HTTPS geladenen APK-Hash sowie das Manifest mit dem lokalen Build
ab. APK-Downloads liegen getrennt von den produktiven Anwendungsdaten.
Android liest für die Updateprüfung nur `latest.json` des eigenen Kanals.
Maßgeblich ist der `versionCode`, auch bei gleicher sichtbarer Versionsnummer.

App-Änderungen nach der Prüfung grundsätzlich auf die bestehende Instanz übertragen
und die Bereitstellung prüfen, sofern der Nutzer nichts anderes vorgibt.

Proxmox-Token sind für Routinearbeiten nicht nötig. SSH aus der Projektwurzel:

```powershell
ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=.local/proxmox/access/known_hosts -i .local/proxmox/access/id_ed25519 root@192.168.184.30
```

Hostschlüsselprüfung beibehalten. Windows-ACLs nicht pauschal öffnen; falls notwendig,
eine temporäre Schlüsselkopie mit auf den ausführenden Benutzer beschränkter ACL
verwenden und anschließend entfernen. Netzwerk- und Dateisystembeschränkungen der
Ausführungsumgebung separat beachten. Mehrzeilige SSH-Eingaben als UTF-8-Bytes über
Python `subprocess.run` senden; PowerShell-Textpipelines können CR-Zeichen ergänzen.

`python scripts/deploy.py` überträgt Quellcode und führt Backendtests aus, startet
den Dienst aber nicht neu. Nach Backendänderungen `systemctl restart rezeptgarten`
und den Dienstzustand prüfen. `--install` installiert zusätzlich Dienste/Caddy und
startet sie neu. Für kleine Änderungen gezielt übertragen; Daten und Konten erhalten.
Deploy-Archive schließen `.local/`, `.git/`, virtuelle Umgebungen, persönliche
Daten, Zertifikatsartefakte und Testergebnisse aus.

## Tests, HTTPS und PWA

Backendtests in einer isolierten Quellkopie mit temporären Daten ausführen:
`/opt/cookidoo-manager/.venv/bin/python -m unittest discover -s tests -v`.
Beim Einkaufswagen-Deployment am 02.11.2026 bestanden 92 Tests in einer isolierten
Quellkopie. Am 03.11.2026 bestanden lokal unter Windows 113 Backendtests mit
isolierten Testdaten. Produktive Datenbanken niemals mit Testrezepten oder
Testkonten befüllen. `tests/browser_check.py` erwartet eine getrennte Testinstanz
auf Loopback-Port 8901 und einen SSH-Tunnel. Die historische `.qa-venv` verweist
in der aktuellen Windows-Umgebung auf einen nicht mehr vorhandenen Interpreter.

Chrome-PWA benötigt vertrauenswürdiges HTTPS. Das öffentliche lokale CA-Zertifikat
liegt im Workspace unter `certificates/Rezeptgarten-CA.crt`; Download:
`http://192.168.184.30/zertifikat`. Vertrauen muss je Gerät manuell eingerichtet
werden; keine globale CA-Installation auf anderen Rechnern ohne Auftrag. Service
Worker nur für öffentliche App-Hülle, niemals persönliche API-Antworten cachen.
Die App-Hülle wird beim Start aus dem Service-Worker-Cache geladen; nach Updates
muss das Gerät die neue Version im Heimnetz mindestens einmal geladen haben, bevor
sie offline verfügbar ist. Der Browser kann seinen Cache selbst entfernen.

Relevante Änderungen an Betrieb, Tests und Deployment in diesem Skill und den
Projekthinweisen aktuell halten.

- Browser dürfen erfolgreiche Bildantworten einen Tag privat zwischenspeichern. `images/thumbnails` enthält regenerierbare 480-Pixel-Vorschauen; der Service Worker speichert weiterhin keine persönlichen API-Antworten.

- Das Deployment-Archiv enthält ausschließlich explizit erlaubte Quelldateien aus App, Tests, Skripten und Deployment; lokale Konfiguration, Daten und verborgene Dateien bleiben ausgeschlossen.

- Beim Einkaufswagen-Deployment wurden der bisherige Quellstand und eine konsistente SQLite-Sicherung vor dem Neustart unter `/var/backups/cookidoo-manager` abgelegt. Die neue Einkaufswagen-API, HTTPS, Service Worker sowie Desktop- und Handyansicht wurden lesend geprüft.
