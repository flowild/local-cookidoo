# Betrieb und Datenhaltung

## Bestehende Installation

Rezeptgarten läuft im Proxmox-LXC 103 (`cookidoo-manager`). Caddy nimmt im Heimnetz HTTP und HTTPS auf Port 80 und 443 an. Der systemd-Dienst `rezeptgarten` läuft als Benutzer `cookidoo` auf `127.0.0.1:8000`.

| Pfad im Container | Inhalt |
| --- | --- |
| `/opt/cookidoo-manager/source` | Bereitgestellter Quellcode |
| `/opt/cookidoo-manager/.venv` | Python-Laufzeit |
| `/var/lib/cookidoo-manager` | SQLite-Datenbank, Rezeptbilder, verschlüsselte Zugangsdaten, Schlüssel und sieben rotierende Datenbanksicherungen |

Die dokumentierte LAN-Adresse ist `192.168.184.30`. Für stabile Lesezeichen und PWA-Installationen die Adresse am Router reservieren. Bei einem Adresswechsel auch die Caddy-Konfiguration und den Zertifikatslink der Web-App prüfen. [Caddy-Konfiguration](../deploy/Caddyfile)

Für HTTPS das öffentliche Zertifikat unter Windows im Zertifikatsspeicher „Vertrauenswürdige Stammzertifizierungsstellen“ des aktuellen Benutzers importieren. Unter Android in den Sicherheitseinstellungen als CA-Zertifikat installieren. Der Service Worker speichert die öffentliche App-Hülle. Persönliche API-Antworten werden darüber nicht offline verfügbar. [Zertifikatsdownload im Heimnetz](http://192.168.184.30/zertifikat)

## Deployment und Sicherung

Aus dem Projektstamm überträgt `python scripts/deploy.py` den Quellcode mit dem eingerichteten SSH-Zugang unter `.local/proxmox/access/` und führt die Backendtests aus. Nach Backendänderungen den Dienst mit `systemctl restart rezeptgarten` im Container neu starten und `/api/health` prüfen. Die Option `--install` richtet zusätzlich die Dienste und Caddy ein. APKs werden separat veröffentlicht. [Betriebsanleitung](../.agents/skills/rezeptgarten-betrieb/SKILL.md) · [Android-Veröffentlichung](android/FLUTTER-PORTIERUNG.md)

Für die Wiederherstellung von Sammlung und Kontozugang das gesamte Datenverzeichnis einschließlich Bildern, `vault.key` und `cookidoo.enc` geschützt sichern. Git und Deployment-Archive schließen lokale Zugangsdaten, Datenbanken und Sicherungen aus. Schreibende Anfragen der Web-App müssen vom selben Origin stammen.

## Cookidoo-Abgleich

Der Sammlungsabgleich liest persönliche Listen, gespeicherte Kollektionen, die Merkliste und eigene Kreationen ein. Mehrfach zugeordnete Rezepte teilen sich ihre Details. Bereits geladene Details mit Bild werden bis zu 14 Tage wiederverwendet. Bilder lädt der Server per HTTPS von zugelassenen `tmecosys.com`-Hosts und speichert sie als WebP mit bis zu 960 Pixeln. Dabei übermittelt er keine Cookidoo-Zugangsdaten. Unreferenzierte Bilder können im lokalen Cache verbleiben.

Alle Listenseiten werden eingelesen, bevor der Server den neuen Listenstand in einer SQLite-Transaktion speichert. Ein Fehler beim Listenabruf oder der Anmeldung erhält die bisherige Sammlung. Fehlen einzelne Rezeptdetails, bleiben die verfügbaren Listeneinträge und zuvor gespeicherten Felder erhalten.

Die undatierte Wochenablage, lokale Listen und der Einkaufswagen liegen in Rezeptgarten. Wochenänderungen werden nach fünf Minuten Ruhezeit übertragen und bei Cookidoo bestätigt. Im Einkaufswagen startet „An Cookidoo übertragen“ die Übertragung. Ein ungeklärtes Ergebnis bleibt zur manuellen Prüfung sichtbar. Auch persönliche Notizen und ausgewählte Änderungen an Cookidoo-Listen schreibt die App über den gemeinsamen Cookidoo-Client.

Die in `requirements.txt` festgelegte Version von `cookidoo-api` übernimmt Token-Erneuerung und seitenweise Abrufe. Die Merkliste verwendet dafür die interne Anfragefunktion der Bibliothek. Die nichtöffentlichen Cookidoo-Schnittstellen können sich ändern. Automatisierte Tests verwenden simulierte Antworten. Für bestimmte Rezeptdetails benötigt das verbundene Konto ein aktives Abonnement. [Abhängigkeiten](../requirements.txt) · [Lizenzhinweise](../THIRD-PARTY-NOTICES.txt)
