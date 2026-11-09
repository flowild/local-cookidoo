---
name: rezeptgarten-betrieb
description: Teste, deploye, betreibe oder diagnostiziere die vorhandene Rezeptgarten-Installation im Proxmox-LXC, einschließlich SSH und PWA.
---

# Rezeptgarten-Betrieb

Die bereitgestellte App-Version steht in `app/version.py` und kann über
`/api/health` geprüft werden. Versionsänderungen nach Prüfung und Deployment
mit den zugehörigen Änderungen committen und nach `origin/main` pushen.

Der Telegram-Nachrichtentest verwendet den systemd-Dienst `rezeptgarten-telegram`
auf dem Proxmox-Host. Er liest die verschlüsselte Bot-Konfiguration über `pct exec`
aus LXC 103, verarbeitet ausschließlich frische private Testnachrichten des
zugeordneten Client-Bots und speichert seinen Telegram-Offset unter
`/var/lib/rezeptgarten-telegram`. Die Bots brauchen Bot-zu-Bot-Freigabe und einen
eigenen Update-Kanal ohne parallele Webhooks oder weitere Verbraucher. Der Dienst
arbeitet auf dem Host als root, weil `pct exec` den Containerzugriff voraussetzt;
er nimmt keine Befehle entgegen. Keine Tokens oder Nachrichten protokollieren.

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

Relevante Änderungen an Betrieb, Tests und Deployment in diesem Skill und den
Projekthinweisen aktuell halten.

- Browser dürfen erfolgreiche Bildantworten einen Tag privat zwischenspeichern. `images/thumbnails` enthält regenerierbare 480-Pixel-Vorschauen; der Service Worker speichert weiterhin keine persönlichen API-Antworten.

- Das Deployment-Archiv enthält ausschließlich explizit erlaubte Quelldateien aus App, Tests, Skripten und Deployment; lokale Konfiguration, Daten und verborgene Dateien bleiben ausgeschlossen.

- Beim Einkaufswagen-Deployment wurden der bisherige Quellstand und eine konsistente SQLite-Sicherung vor dem Neustart unter `/var/backups/cookidoo-manager` abgelegt. Die neue Einkaufswagen-API, HTTPS, Service Worker sowie Desktop- und Handyansicht wurden lesend geprüft.
