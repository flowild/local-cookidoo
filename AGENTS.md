# Rezeptgarten / local-cookidoo

Private Cookidoo-Rezeptverwaltung im eigenen Proxmox-LXC. Antworte auf Deutsch und
arbeite in diesem Projekt; das frühere mqtt2PC-Projekt ist eine andere Anwendung.
Die Web-App muss auf Desktop und Handy gut bedienbar und als Chrome-PWA installierbar
bleiben. Die lokale App ist auf Nutzerwunsch ohne Passwort erreichbar; schreibende
API-Anfragen erfordern denselben Origin. Keine Passwortpflicht ungefragt einführen.

## Projektskills

Lies den passenden Skill bei entsprechender Arbeit; kombiniere sie bei Bedarf:

- [rezeptgarten-app](.agents/skills/rezeptgarten-app/SKILL.md): Rezepte, lokale
  Listen, Vorrat, Suche, Frontend, Einstellungen und PWA.
- [rezeptgarten-cookidoo](.agents/skills/rezeptgarten-cookidoo/SKILL.md): Cookidoo-
  Sync, Rezeptdetails, Konto, Kalender und Einkaufsliste.
- [rezeptgarten-betrieb](.agents/skills/rezeptgarten-betrieb/SKILL.md): bestehende
  Serverinstanz, SSH, Deployment, Testumgebungen und lokales HTTPS.

## Vertrauliche Daten

`.local/`, `.qa-venv/`, Datenbanken, Token-Dateien, Zertifikatsartefakte und
Testergebnisse sind von Git ausgeschlossen. Der SSH-Schlüssel hat keinen `.key`-
Suffix: Sein Schutz beruht auf dem Ausschluss des gesamten `.local/`-Verzeichnisses
und den Windows-ACLs. Keine Schlüssel, Tokens oder Passwörter in Quellcode, Logs,
Antworten oder Git aufnehmen; keine privaten CA-Schlüssel vom Server kopieren.
Produktive Daten und Konten erhalten und Tests mit isolierten Daten ausführen.
Zugangsdaten nur an die eingerichtete und autorisierte Cookidoo-Zieladresse senden.

## Aktuell halten

Bei relevanten Änderungen an Funktionen, Betrieb, Sicherheit, Tests oder Deployment
AGENTS.md und die betroffenen Projektskills im selben Arbeitsgang prüfen und
aktualisieren. Veraltete Aussagen ersetzen, Momentaufnahmen kennzeichnen und keine
Zugangsdaten oder persönlichen Rezeptdaten dokumentieren.

## Meine Woche

Die Wochenansicht liest die gewählte Berliner Kalenderwoche direkt aus Cookidoo;
Pfeile wechseln die Woche, „Diese Woche“ springt zurück zur aktuellen Woche;
Bilder werden lokal zwischengespeichert. Verschiebungen erscheinen sofort, werden
serverseitig vorgemerkt und nach fünf Minuten Ruhezeit über den gemeinsamen
Cookidoo-Client übertragen, auch wenn der Browser geschlossen ist.
Das Ziel muss bestätigt sein, bevor der Ursprung entfernt wird; unklare Ergebnisse
und nicht übertragene Folgeänderungen müssen sichtbar gemeldet werden.
„In den Einkaufswagen“ übernimmt Rezepte ab heute innerhalb der gewählten Woche
einschließlich vorgemerkter Verschiebungen und der taglosen Ablage in den lokalen
Einkaufswagen. Die Übernahme ist eine Momentaufnahme; spätere Wochenänderungen ändern
den Wagen nicht automatisch.
Wochenrezepte öffnen intern; fehlen sie in der lokalen Sammlung, lädt die App ihre
Details bei Bedarf aus Cookidoo.
Nicht zugeordnete Cookidoo-Katalogrezepte aus angesehenen Wochen werden nach einer
erneuten Prüfung in der eigenen Cookidoo-Liste „Rezeptgarten – Wochenrezepte ohne
Liste“ gesammelt; danach wird die lokale Sammlung synchronisiert. Eigene Kreationen
bleiben in „Meine Kreationen“.

Persönliche Rezeptnotizen werden direkt aus Cookidoo geladen und dort gespeichert.
Vor dem Schreiben wird die zuletzt geladene Fassung mit Cookidoo verglichen;
bei Konflikten darf der ungespeicherte Text nicht still verworfen werden.
In der Wochenansicht zeigt ein Symbol auf dem Rezeptbild vorhandene Notizen an;
Gesamtzeit und Portionen stehen ebenfalls auf dem Bild. Die Notizbearbeitung
erfolgt über die Rezeptdetailansicht.
Die Rezeptdetailansicht zeigt zugeordnete Listen über dem Titel und vorhandene
Notizen direkt an. Notizen werden im Feld mit Enter oder beim Verlassen gespeichert;
Umschalt+Enter fügt einen Zeilenumbruch ein. Zutaten sind zunächst aufgeklappt,
die Zubereitung eingeklappt.

Rezeptbilder liegen lokal als WebP bis 960 Pixel; Kacheln erhalten bei Bedarf
erzeugte Vorschauen bis 480 Pixel. Erfolgreiche Bildantworten dürfen einen Tag im
privaten Browsercache liegen, aber nicht im Service-Worker-Cache. Andere persönliche
API-Antworten bleiben `no-store`. Nicht lokal vorhandene Wochenbilder werden erst
bei ihrer Bildanfrage heruntergeladen und blockieren nicht die Wochenansicht.

Unter jeder Woche liegt eine lokale, kontobezogene Ablage für Rezepte ohne festen
Tag. Beim Ziehen wird der Kopfbereich zum Papierkorb für das Entfernen aus der Woche. Änderungen
an Cookidoo-Kalendereinträgen werden über die bestehende Warteschlange nach fünf
Minuten übertragen und bestätigt. Die Ablage selbst existiert nur in Rezeptgarten;
ihre Rezepte gehören beim Wocheneinkauf zur ausgewählten Woche.
Beim Ziehen folgt eine Vorschau mit Rezeptbild und -name dem Zeiger beziehungsweise Finger.
Der manuelle Synchronisieren-Knopf gibt wartende Wochenänderungen sofort zum
Abgleich frei; der Kalenderabgleich folgt nach der laufenden Sammlungssynchronisierung.
Fehlerhafte oder unklare Warteschlangeneinträge werden dabei nicht erneut ausgeführt.
Unter der Wochenablage zeigen aufklappbare lokale Listen ihre Rezepte. Das Plus
speichert ein ausgewähltes Listenrezept in der Ablage der angezeigten Woche.
Nach dem Entfernen aus der Woche kann der Nutzer die Änderung fünf Sekunden lang
rückgängig machen; ein Kreis zeigt die verbleibende Zeit. Vorgemerkte Cookidoo-
Löschungen müssen beim Rückgängigmachen sicher entfallen.
„Stärke“ und „Speisestärke“ gelten beim Vorratsabgleich als gleichwertig.
Fehlgeschlagene Wochenabfragen dürfen keine Einträge in einer zuvor angezeigten
Woche verändern. Vorgemerkte Änderungen eines anderen Kontos dürfen nicht verworfen
werden. Vorratsmarkierungen auf der Einkaufsliste müssen bestätigt werden.

## Mein Einkaufswagen

Der kontobezogene lokale Einkaufswagen liegt zwischen „Meine Woche“ und „Mein Vorrat“.
Alle Hinzufügen-Knöpfe schreiben lokal; ausschließlich „An Cookidoo übertragen“
schreibt nach Cookidoo. Rezeptversionen und Zutaten werden als Schnappschuss gespeichert,
Zusatzartikel und Vorhanden-Markierungen sind lokal bearbeitbar. Der Vorrat belegt
die Markierungen vor. Bereits in Cookidoo enthaltene Rezepte bleiben unverändert.
Der Transfer verwendet den gemeinsamen Cookidoo-Client und Lock, bestätigt Erfolge,
speichert ungeklärte Ergebnisse dauerhaft und wiederholt sie nicht automatisch.
Nach Prüfung in Cookidoo kann der Nutzer ungeklärte Einträge ausdrücklich auf vorhanden
oder erneut übertragbar setzen. Lokale Daten bleiben bis zum ausdrücklichen Entfernen
oder Leeren erhalten; die SQLite-Sicherung und der Export enthalten den Wagen.
