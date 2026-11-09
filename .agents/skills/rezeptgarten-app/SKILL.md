---
name: rezeptgarten-app
description: Entwickle oder prüfe Rezeptgarten-Funktionen für Rezepte, lokale Listen, Vorrat, Suche, Darstellung und PWA im Projekt local-cookidoo.
---

# Rezeptgarten entwickeln

- Die App-Version wird zentral als `APP_VERSION` in `app/version.py` gepflegt und
  nach SemVer bei relevanten App-Änderungen erhöht. App und Health-Endpunkt zeigen
  denselben Stand. Nach Prüfung und Deployment Versionsänderungen mit den zugehörigen
  Änderungen committen und nach `origin/main` pushen; keine fremden Änderungen
  überschreiben und keinen Force-Push verwenden. Die PWA-Cacheversion bleibt separat.

- Telegram-Einstellungen verwalten ein verschlüsseltes Server-Token und ein nur im
  jeweiligen Browser unverschlüsselt gespeichertes Client-Token. Eine explizite
  Kopplung im Heimnetz und ein Nachrichtentest mit zufälliger Kennung erlauben die
  bestätigte Bot-Kommunikation. Der Test funktioniert nach Kopplung auch ohne Heimnetz
  mit Internet. Beide Bots benötigen Bot-zu-Bot-Freigabe und dürfen keine weiteren
  Update-Verbraucher oder Webhooks haben. Tokens und Nachrichten nicht protokollieren.
- Ohne Heimnetz lässt sich der Einkaufswagen nach erneuter Bot-Kopplung über Telegram
  lesend laden. AES-256-GCM verschlüsselt die kontogebundene Momentaufnahme zwischen
  Container und Browser. Ein Kontowechsel erfordert erneute Kopplung. Telegram-Metadaten
  bleiben sichtbar; persönliche API-Antworten nicht im Service Worker speichern.
- App-Start und Einkaufswagenabruf warten maximal 2,5 Sekunden auf den Heimnetz-Server.
  Telegram-Anfragen werden direkt gesendet; ältere Antworten werden anhand ihrer
  Anfragekennung verworfen. Für schreibende API-Anfragen gilt dieses Zeitlimit nicht.
  Unterstützte Browser fordern die komprimierte Momentaufnahme an; ältere Browser
  verwenden das bisherige Format. Komprimierung erfolgt vor der Verschlüsselung.

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

- In „Meine Woche“ stehen sieben Tage auf Desktop ohne horizontales Scrollen in einer Reihe; auf dem Handy bleibt diese seitlich scrollbar und rastet mittig auf einem Tag ein. Der zuletzt angezeigte Wochentag bleibt im Browser nach Neuladen und Wochenwechsel erhalten. Pfeile wechseln die angezeigte Woche, „Diese Woche“ springt zur aktuellen Woche; Rezeptbilder und Links sind in den Tageskacheln sichtbar.

- Wochen- und Ablagerezepte verwenden das Design der Rezeptlisten: Bild und ein Bereich für den vollständig umgebrochenen Namen sowie den verfügbaren Schwierigkeitsgrad. Die sieben Tage bleiben auf Desktop nebeneinander; fehlende Angaben werden bei Bedarf im Hintergrund ergänzt.

- In „Meine Woche“ lassen sich Kacheln mit der Maus zwischen Tagen und Ablage ziehen; auf Touchgeräten aktiviert langes Berühren die Auswahl zum Verschieben; kurzes Tippen und Scrollen bleiben möglich. Unter den Rezepten gibt es keine Griffleiste oder Zielauswahl. Das X auf einem Tagesrezept verschiebt es in die Ablage. Die Ansicht aktualisiert sich sofort; nach fünf Minuten ohne weitere Änderung folgt der Kalenderabgleich. Vorgemerkte Änderungen bleiben auch nach Schließen oder Neuladen der App erhalten.

- Auf dem Handy markiert etwa 500 ms langes Halten ein Rezept oder einen Platzhalter; sofortiges Wischen über Kacheln scrollt normal. Bei markierter Kachel steuern vertikale Wischbewegungen ab 90 Pixeln die Aktion statt zu scrollen. Die Markierung bleibt auch nach Loslassen erhalten und endet nach einer Aktion oder durch Tippen. Danach entfernt ein Wisch nach oben ein Tagesrezept und ein Wisch nach unten verschiebt es in die Ablage. In der Ablage sortiert ein Wisch nach oben in den eingerasteten Tag ein; nach unten entfernt er das Rezept. Rezeptentfernungen bieten Rückgängig an. Dieselben Wischrichtungen gelten für einzelne Platzhalter in Tagen und Ablage; ihre Entfernung erfolgt wie beim Papierkorb unmittelbar ohne Rückgängig-Funktion. Langes Drücken auf Rezepten öffnet auf Touchgeräten kein Browser-Kontextmenü. Das native Browser-Ziehen der Wochenkacheln und Bilder ist für Touch deaktiviert, damit es die Haltegeste nicht übernimmt; Mausziehen bleibt verfügbar.

- Persönliche Rezeptnotizen sind über die Rezeptdetails erreichbar; die Wochenansicht zeigt bei vorhandener Notiz ein Symbol sowie Dauer und Portionen auf dem Bild; die Portionen stehen unten rechts. Das Feld lädt den Cookidoo-Stand und speichert bei Enter oder Fokusverlust; Umschalt+Enter erzeugt einen Zeilenumbruch. Bei Fehlern und Konflikten bleibt der Text erhalten.

- Wochenrezepte öffnen immer in der internen Detailansicht, auch wenn sie nicht lokal gespeichert sind. Ihre Daten werden bei Bedarf von Cookidoo geladen; ein externer Link erscheint nur als „In Cookidoo öffnen“.

- Rezeptvorschauen zeigen links oben vorhandene Notizen und rechts oben einen Knopf für die lokale Ablage der aktuellen Berliner Kalenderwoche. In „Meine Woche“ verschiebt dort stattdessen ein X Tagesrezepte in die Ablage der angezeigten Woche, und ein Papierkorb entfernt Ablagerezepte mit Rückgängig. Liegt ein Tagesrezept bereits in der Ablage, bleibt der Ablageeintrag erhalten und der Tageseintrag wird rückgängig machbar entfernt. Der Notizstatus wird für sichtbare Vorschauen im Hintergrund geladen und nach Änderungen aktualisiert.

- Nicht zugeordnete Katalogrezepte aus angesehenen Wochen werden nach Prüfung in einer eigenen Cookidoo-Liste gesammelt; eigene Kreationen bleiben in „Meine Kreationen“.

- Rezeptdetails zeigen Listen-Pillen über dem Titel und vorhandene Cookidoo-Notizen direkt an; das Notizfeld ist direkt bearbeitbar und erlaubt auch das Hinzufügen neuer Notizen. Zutaten sind standardmäßig aufgeklappt, die Zubereitung eingeklappt; beide Bereiche sind unabhängig bedienbar. Verfügbarkeitsfarben bleiben an den Zutaten erkennbar.

- Bildkacheln verwenden lokal erzeugte WebP-Vorschauen bis 480 Pixel, die Detailansicht das Bild bis 960 Pixel. Erfolgreiche Bildantworten sind einen Tag privat im Browser cachebar; andere persönliche API-Antworten und der Service-Worker-Cache bleiben davon ausgeschlossen.

- „In den Einkaufswagen“ übernimmt Rezepte ab dem heutigen Berliner Datum aus der angezeigten Woche sowie die Wochenablage in den lokalen Einkaufswagen. Vorgemerkte Verschiebungen werden berücksichtigt; spätere Wochenänderungen ändern die Übernahme nicht automatisch.

- „Mein Einkaufswagen“ liegt zwischen Woche und Vorrat. Rezeptaktionen und Wocheneinkauf speichern kontobezogene Schnappschüsse lokal; Zutaten können als vorhanden markiert und weitere Artikel hinzugefügt werden. Der Vorrat belegt die Markierung vor. Übertragung zu Cookidoo erfolgt nur auf ausdrücklichen Knopfdruck. Unsichere Ergebnisse bleiben sichtbar und werden erst nach ausdrücklicher Prüfung erneut freigegeben.

- Das Einkaufswagensymbol in der Kopfzeile öffnet den lokalen Wagen. Die kleine Zahl zeigt die kontobezogene Anzahl der enthaltenen Rezepte, auch nach Änderungen und einem Kontowechsel; Zusatzartikel werden nicht mitgezählt.

- Die Zutaten im Einkaufswagen sind kompakte Zeilen mit Checkbox, Mengenangabe und dezentem Rezeptnamen. Abgehakte Zutaten stehen unmittelbar nach dem Ändern unter den noch benötigten; gleiche Zutaten werden innerhalb ihres jeweiligen Zustands gruppiert. Auf Desktop können mehrere Spalten erscheinen, auf dem Handy eine. Checkboxen dürfen nicht die allgemeine volle Eingabebreite erben.

- Unter der Woche gibt es eine lokale, kontobezogene Ablage ohne festen Tag. Das X verschiebt ein Tagesrezept dorthin; der Papierkorb entfernt ein Ablagerezept mit Rückgängig. Die Ablage gehört zur angezeigten Woche und zum Wocheneinkauf.

- Der manuelle Synchronisieren-Knopf gibt wartende Wochenänderungen sofort frei; nach der Sammlungssynchronisierung verarbeitet sie der bestehende Kalender-Worker. Fehlgeschlagene oder unklare Schreibvorgänge werden nicht automatisch wiederholt.

- Unter der Wochenablage sind lokale Listen aufklappbar; ihre Rezepte lassen sich per Plus in der Ablage der angezeigten Woche speichern. Ein zusätzlicher Ablageknopf erscheint dort nicht.

- Beim Entfernen aus der Wochenplanung oder Ablage bietet ein schwebender Hinweis fünf Sekunden lang Rückgängig an. Der Vorratsabgleich erkennt Stärke und Speisestärke als gleichwertig.

- „Bio-Vanille“ wird beim Zutaten- und Vorratsabgleich als Vanilleextrakt erkannt. Vanillezucker, Vanilleschoten und andere Vanilleprodukte bleiben getrennt.

- Ein Fortschrittskreis zeigt die verbleibenden fünf Sekunden zum Rückgängigmachen; bei reduzierter Bewegung aktualisiert er sich in Sekundenschritten.

- Nach einem fehlgeschlagenen Wochenwechsel bleiben Listenrezepte gesperrt, bis die ausgewählte Woche geladen wurde; niemals die vorherige Woche still weiterverwenden.

- Rezepte im Einkaufswagen erscheinen als responsive Bildkacheln nebeneinander; der Papierkorb oben rechts entfernt das Rezept. Dauer und Portionsangaben stehen, soweit verfügbar, auf dem Bild und beim Darüberfahren bewegt sich das Bild leicht. Ältere Einkaufswageneinträge ergänzen fehlende Rezeptangaben beim Anzeigen aus der lokalen Sammlung. Abweichende Übertragungsstatus und Hinweise bleiben sichtbar; der Status „Bereit“ und der Wochenknopf entfallen in diesen Kacheln.

- Einkaufszutaten erscheinen nach Warenbereichen gruppiert. Vorhandene Vorratszuordnungen haben Vorrang, weitere Zutaten erhalten eine passende Standardgruppe oder „Sonstiges“. Wasser wird weder bei benötigten noch bei vorhandenen Zutaten angezeigt; gespeicherte Einkaufsdaten bleiben erhalten.

- Einkaufszutaten zeigen neben dem Häkchen ein kleines Symbol passend zur Zutat oder zum Warenbereich, wie im Vorrat.

- Zutaten in Rezeptdetails zeigen dieselben kleinen Symbole wie im Einkaufswagen und behalten die Vorratskennzeichnung.

- Wasser wird appweit in Zutatenansichten, Einkaufswagen, Vorrat und Zutaten-Auswahl ausgeblendet; Rezeptdaten und Zubereitung bleiben erhalten. Andere Zutaten wie Kokoswasser bleiben sichtbar.

- Auf dem Handy stehen sechs Hauptbereiche in einer unteren Navigationszeile; die Einstellungen sind über das Zahnrad in der Kopfzeile erreichbar.

- Bei eigenen Kreationen steht die App-Notiz am Ende der Cookidoo-Tipps ab „Notiz:“. Das gezielte Cookidoo-PATCH ändert nur das Tippfeld; vor dem Schreiben werden Notiz und Tipps auf Konflikte geprüft, danach Antwort und übrige Rezeptfelder bestätigt. Mehrdeutige Markierungen und unbestätigte Schreibvorgänge werden gemeldet. Ein Test an einer isolierten Rezeptkopie am 02.11.2026 bestätigte den unveränderten Rezeptinhalt und das Bild; die Testkopie wurde gelöscht.

- Rezeptdetails zeigen vorhandene Cookidoo-Tipps in einem zunächst eingeklappten Bereich unter der Zubereitung. Katalog-Zusatzinformationen und Hinweise eigener Kreationen werden beim Synchronisieren gespeichert; fehlende Daten älterer Rezepte werden bei Bedarf nachgeladen.

- Lokale Rezeptlisten und Vorratskategorien können nach ausdrücklicher Bestätigung gelöscht werden. Beim Löschen einer Vorratskategorie werden deren Vorratseinträge mit gelöscht; bei lokalen Listen entfallen nur die Listenzuordnungen.

- Spaghetti, Nudeln und Pasta gelten beim Zutaten- und Vorratsabgleich als gleichwertig; gespeicherte Einkaufswagenzutaten werden bei der Anzeige anhand der aktuellen Regeln gruppiert.

Unter der Wochenablage stehen sechs feste Platzhalter einschließlich „Resteessen“ in einer einklappbaren Liste über den lokalen Listen. Über das Plus kommen sie auch mehrfach in die kontobezogene Ablage der angezeigten Woche und können dort einzeln entfernt werden. Ein X verschiebt Tagesplatzhalter zurück in die Ablage. Platzhalter können mit der Maus oder durch langes Berühren aus Liste und Ablage auf Wochentage und zwischen Tagen gezogen werden. Ihre Position wird kontobezogen und wochenweise gespeichert. Sie bleiben lokal und gelangen weder in Cookidoo noch in den Einkaufswagen.
