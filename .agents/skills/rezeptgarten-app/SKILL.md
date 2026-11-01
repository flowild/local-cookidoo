---
name: rezeptgarten-app
description: Entwickle oder prüfe Rezeptgarten-Funktionen für Rezepte, lokale Listen, Vorrat, Suche, Darstellung und PWA im Projekt local-cookidoo.
---

# Rezeptgarten entwickeln

Die App synchronisiert Cookidoo-Listen, Kollektionen, Merkliste und eigene Kreationen
nach SQLite; Bilder werden lokal gespeichert. Das responsive Frontend in `app/static/`
hat keinen Node-Build. Detailansichten, JSON-Export und automatische sowie manuelle
Synchronisierung sind vorhanden.

- Lokale Listen bleiben von Cookidoo-Listen getrennt und werden nicht mit Cookidoo
  synchronisiert. Zugeordnete Versionen eines Rezepts werden zusammengefasst und
  können in der Detailansicht ausgewählt werden.
- Rezeptlisten können nach Zutaten, Portionen und Gesamtzeit gefiltert und sortiert
  werden. Nicht passende Rezepte bleiben ausgegraut sichtbar, auch bei weiteren
  hinzufügbaren Rezepten. Zutatenfilter unterstützen mehrere Einträge.
- Die Headersuche durchsucht Rezepttitel und Zutaten einschließlich bekannter Aliasse;
  Titeltreffer stehen vor reinen Zutatentreffern. Sortierung, Listenfilter und
  gruppierte Versionen bleiben berücksichtigt.
- „Mein Vorrat“ hat alphabetische Zutaten, Vorschläge aus Rezepten und einklappbare,
  per Griff sortierbare Kategorien. `app/ingredients.py` enthält den Abgleich von
  Synonymen, englischen Begriffen, Speiseölen und Wasser. Mengen werden nicht
  verglichen. Verfügbarkeit erscheint in den Rezeptdetails.
- Die Übersicht zeigt ein täglich wechselndes Zufallsrezept mit manueller Neuauswahl.
  Dunkelmodus und Akzentfarbe gelten pro Browser. Meldungen müssen auch über geöffneten
  modalen Dialogen sichtbar sein.
- Der Nutzer hat die lokale App-Anmeldung ausdrücklich entfernt. Nicht ungefragt
  wieder einführen; schreibende API-Anfragen erfordern denselben Origin.
- Der in den Einstellungen hinterlegbare Google-API-Schlüssel liegt separat vom
  Cookidoo-Token verschlüsselt in `google-api-key.enc`; die API gibt nur seinen
  Vorhandenseinsstatus aus. Der Server kann ihn mit `vault.key` entschlüsseln.
  Noch ist keine Google-Funktion angebunden. Kein Geheimnis ausgeben oder loggen.
- Bei Änderungen versionierter statischer Dateien URLs in `index.html` und `sw.js`
  und die Service-Worker-Cacheversion zusammen aktualisieren. Nur die öffentliche
  App-Hülle darf in den Service-Worker-Cache; keine persönlichen API-Antworten.

Backendtests: `python -m unittest discover -s tests -v`; produktive Daten nicht mit
Fixtures befüllen. Für Server- und Browserprüfungen den Skill `rezeptgarten-betrieb`
verwenden. Relevante Änderungen an Funktionen und Regeln in diesem Skill und in
`AGENTS.md` aktuell halten.

- „Meine Woche“ zeigt die aktuelle Berliner Kalenderwoche von Montag bis Sonntag; beim Öffnen und Wochenwechsel werden die Einträge direkt aus Cookidoo geladen und vorgemerkte Verschiebungen angezeigt. Ohne Verbindung bleiben die Tage mit einem Fehlerhinweis sichtbar.

- In „Meine Woche“ stehen sieben Tage auf Desktop ohne horizontales Scrollen in einer Reihe; auf dem Handy bleibt diese seitlich scrollbar. Pfeile wechseln die angezeigte Woche, „Diese Woche“ springt zur aktuellen Woche; Rezeptbilder und Links sind in den Tageskacheln sichtbar.

- Rezepte in „Meine Woche“ lassen sich am Bild per Maus oder Touch sowie über die am unteren Ende der Tageskarte ausgerichtete Tagesauswahl verschieben. Die Ansicht aktualisiert sich sofort; nach fünf Minuten ohne weitere Änderung folgt der Abgleich. Vorgemerkte Verschiebungen liegen dauerhaft auf dem Server und bleiben auch nach Schließen oder Neuladen der App erhalten.

- Persönliche Rezeptnotizen sind über die Rezeptdetails erreichbar; die Wochenansicht zeigt bei vorhandener Notiz ein Symbol sowie Dauer und Portionen auf dem Bild; die Portionen stehen unten rechts. Das Feld lädt den Cookidoo-Stand und speichert bei Enter oder Fokusverlust; Umschalt+Enter erzeugt einen Zeilenumbruch. Bei Fehlern und Konflikten bleibt der Text erhalten.

- Wochenrezepte öffnen immer in der internen Detailansicht, auch wenn sie nicht lokal gespeichert sind. Ihre Daten werden bei Bedarf von Cookidoo geladen; ein externer Link erscheint nur als „In Cookidoo öffnen“.

- Nicht zugeordnete Katalogrezepte aus angesehenen Wochen werden nach Prüfung in einer eigenen Cookidoo-Liste gesammelt; eigene Kreationen bleiben in „Meine Kreationen“.

- Rezeptdetails zeigen Listen-Pillen über dem Titel und vorhandene Cookidoo-Notizen direkt an; das Notizfeld ist direkt bearbeitbar und erlaubt auch das Hinzufügen neuer Notizen. Zutaten sind standardmäßig aufgeklappt, die Zubereitung eingeklappt; beide Bereiche sind unabhängig bedienbar. Verfügbarkeitsfarben bleiben an den Zutaten erkennbar.

- Bildkacheln verwenden lokal erzeugte WebP-Vorschauen bis 480 Pixel, die Detailansicht das Bild bis 960 Pixel. Erfolgreiche Bildantworten sind einen Tag privat im Browser cachebar; andere persönliche API-Antworten und der Service-Worker-Cache bleiben davon ausgeschlossen.

- „In den Einkaufswagen“ überträgt nur Rezepte ab dem heutigen Berliner Datum aus der angezeigten Woche. Vorgemerkte Verschiebungen werden berücksichtigt; Zutaten im lokalen Vorrat werden in Cookidoo als vorhanden markiert.

- Unter der Woche gibt es eine lokale, kontobezogene Ablage ohne festen Tag. Rezepte lassen sich per Bild oder Tagesauswahl zwischen Tagen und Ablage bewegen; beim Ziehen wird der Kopfbereich als Papierkorb eingeblendet. Die Ablage gehört zur angezeigten Woche und zum Wocheneinkauf.

- Beim Ziehen folgt eine Vorschau mit Rezeptbild und -name dem Zeiger beziehungsweise Finger.

- Der manuelle Synchronisieren-Knopf gibt wartende Wochenänderungen sofort frei; nach der Sammlungssynchronisierung verarbeitet sie der bestehende Kalender-Worker. Fehlgeschlagene oder unklare Schreibvorgänge werden nicht automatisch wiederholt.

- Unter der Wochenablage sind lokale Listen aufklappbar; ihre Rezepte lassen sich per Plus in der Ablage der angezeigten Woche speichern.

- Beim Entfernen aus der Wochenplanung oder Ablage bietet ein schwebender Hinweis fünf Sekunden lang Rückgängig an. Der Vorratsabgleich erkennt Stärke und Speisestärke als gleichwertig.

- Ein Fortschrittskreis zeigt die verbleibenden fünf Sekunden zum Rückgängigmachen; bei reduzierter Bewegung aktualisiert er sich in Sekundenschritten.

- Nach einem fehlgeschlagenen Wochenwechsel bleiben Listenrezepte gesperrt, bis die ausgewählte Woche geladen wurde; niemals die vorherige Woche still weiterverwenden.
