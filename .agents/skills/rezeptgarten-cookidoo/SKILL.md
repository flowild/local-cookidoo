---
name: rezeptgarten-cookidoo
description: Entwickle oder diagnostiziere die Cookidoo-Anbindung von Rezeptgarten, einschließlich Synchronisierung, Rezeptdetails, Kalender und Einkaufsliste.
---

# Cookidoo-Anbindung

- Die Telegram-Wochenansicht nutzt den bestehenden Kalenderclient und Lock im
  laufenden App-Dienst. Die verschlüsselte, kontogebundene Momentaufnahme enthält
  Tage, vorgemerkte Verschiebungen, lokale Platzhalter und Ablage ohne Bild- oder
  Notizinhalte. Fehler und unklare Warteschlangenzustände bleiben sichtbar.

`cookidoo-api==0.19.0` ist fest gepinnt. Die cookidoo-migrate-Integration hat teils
ältere Imports und wird nicht unverändert eingebunden. Lizenzhinweise stehen in
`THIRD-PARTY-NOTICES.txt`. Das eingerichtete Konto verwendet `cookidoo.de` und
`de-DE`; Zugangsdaten nur an die eingerichtete autorisierte Zieladresse senden.

- Die Merkliste ist ein separater Endpunkt: null persönliche Listen bedeutet nicht,
  dass keine gespeicherten Rezepte vorhanden sind. `SyncService.bookmarks()` nutzt
  den tokenfähigen `_request_json`-Helfer für `organize/{language}/api/bookmark`;
  alle Seiten lesen und Rezept-IDs deduplizieren. Bei Custom- und Managed-Listen
  liefern die Count-Methoden `(totalElements, totalPages)`.
- Listeneinträge haben keine Bilder. `get_recipe_details(id)` liefert Details,
  Zutaten und Bild-URLs; Bilder von erlaubten HTTPS-Assethosts ohne Cookidoo-Auth
  herunterladen und lokal als WebP bis 960 Pixel speichern. Keine Bilder erfinden.
- Das Passwort nur vorübergehend verwenden und nach Login auch `cfg.password`
  leeren. OAuth-Tokens werden verschlüsselt gespeichert; jeden Refresh persistieren,
  da Refresh-Tokens rotieren. Keine Tokens oder Passwörter ausgeben.
- Niemals unabhängige Clients mit denselben rotierenden Tokens parallel betreiben.
  Für separate Diagnose die App kontrolliert pausieren und anschließend mit dem
  aktuellen Tokenstand neu starten oder ihren bestehenden Client verwenden.
- Ein vollständiger Listen-Snapshot ist atomar. Fehler beim Laden erhalten die alte
  Sammlung; einzelne fehlende Rezeptdetails dürfen Einträge nicht verschwinden lassen.
- `recipe_action` verwendet den bestehenden Client und denselben Lock wie der Sync.
  Interne IDs eigener Kreationen beginnen mit `creation:`; für Cookidoo den Präfix
  entfernen und die Methoden für eigene Kreationen verwenden.
- „Heute kochen“ schreibt das ausgewählte Rezept für das heutige Datum in Berlin in
  den Cookidoo-Kalender und liest zur Bestätigung den Kalender erneut. Rezepte und
  Zusatzartikel werden zunächst lokal im kontobezogenen Einkaufswagen gesammelt.
  Erst ein ausdrücklicher Knopfdruck überträgt sie nach Cookidoo. Es gibt keine
  allgemeine bidirektionale Synchronisierung.
- Kalender und Einkaufsliste nur im Rahmen der Nutzeranweisung beschreiben; Tests
  verwenden isolierte Daten und Mocks. Die Darstellung in der Cookidoo-App kann eine
  Aktualisierung erfordern. Den echten Import nicht nur mit leeren Fakes beurteilen.

Bei relevanten Änderungen diesen Skill und die Projekthinweise aktuell halten.

- „Meine Woche“ liest die aktuelle Woche direkt über denselben Client und Lock aus Cookidoo. Leere Tage werden ergänzt; lokale Rezepte sind anklickbar, eigene Kreationen werden bei Bedarf nachgeladen. Verschiebungen in derselben Woche werden auf dem Server vorgemerkt und fünf Minuten nach der letzten Änderung über den gemeinsamen Client und Lock an Cookidoo übertragen, auch bei geschlossener App. Erst nach Bestätigung am Zieltag wird am Ursprung entfernt; unklare Teilergebnisse melden und die Woche erneut laden.

- Für die Wochenwahl wird der Montag der ausgewählten Woche an Cookidoo übergeben. Nicht lokal vorhandene Wochenrezepte öffnen intern und laden Details über den bestehenden Cookidoo-Client und Lock, bevor der reguläre Listenabgleich sie lokal übernimmt. Nur „In Cookidoo öffnen“ führt nach außen; Bilder nutzen den bestehenden abgesicherten Bild-Cache.

- Persönliche Notizen von Katalogrezepten werden live über `recipe-notes/{language}/recipes` und den bestehenden Client mit dessen Lock gelesen und geschrieben. Notizen eigener Kreationen verwenden stattdessen das Tippfeld wie unten beschrieben. Die Fassung wird vor dem Schreiben verglichen und das Ergebnis erneut gelesen; Notizinhalte nicht loggen. Notizen gehören zum Rezept, nicht zum Kalendertag.

- Beim Öffnen einer Woche werden nicht zugeordnete Katalogrezepte anhand eines vollständigen Cookidoo-Listensnapshots erneut geprüft und in der eigens angelegten Cookidoo-Liste „Rezeptgarten – Wochenrezepte ohne Liste“ gesammelt. Eigene Kreationen bleiben in „Meine Kreationen“. Die Listen-ID wird kontobezogen gespeichert; Erstellung und Hinzufügen bestätigen, Fehler nicht still behandeln, danach Sammlung synchronisieren.

- Die Wochenansicht lädt den Notizstatus im Hintergrund mit dem gemeinsamen Cookidoo-Client; die Status-API liefert nur das Vorhandensein, keine Notizinhalte. Fehlende Dauer, Portionen oder Schwierigkeitsgrade werden bei Bedarf aus den Rezeptdetails ergänzt; ältere Ablageeinträge nutzen vorhandene lokale Rezeptdaten.

- Rezeptvorschauen laden den bloßen Notizstatus sichtbarer Rezepte in kleinen Gruppen über denselben Client und Lock. `notes_only` vermeidet unnötige Rezeptdetailanfragen. Das Wochensymbol fügt ein serverseitig geprüftes Rezept lokal zur Ablage der aktuellen Berliner Woche hinzu; nicht lokal vorhandene Rezepte werden zuvor über Cookidoo geprüft. Der Vorgang schreibt keinen Kalendereintrag.

- Noch nicht lokal vorhandene Bilder aus der Wochenansicht werden erst auf Bildanfrage heruntergeladen, damit langsame Bildserver die Wochenantwort nicht blockieren. Parallele Anfragen für dasselbe Bild teilen sich den Download; nur erlaubte HTTPS-Assethosts werden angesprochen.

- Die serverseitige Wochenwarteschlange ist kontobezogen und übersteht Neustarts. Ein unterbrochener oder unbestätigter Schreibvorgang wird nicht automatisch wiederholt; der Nutzer muss Cookidoo prüfen und die verbleibenden Vormerkungen ausdrücklich verwerfen.

- Der Wocheneinkauf ermittelt unter dem gemeinsamen Client-Lock Rezepte ab heute bis Sonntag der ausgewählten Woche, einschließlich serverseitig vorgemerkter Verschiebungen und der Wochenablage, und speichert Schnappschüsse lokal. Erst der separate Transfer schreibt nach Cookidoo; bereits dort vorhandene Rezepte bleiben unverändert. Bestätigte lokale Zutatenmarkierungen werden übertragen und geprüft. Teilerfolge und unklare Schreibvorgänge bleiben dauerhaft sichtbar und werden nicht blind wiederholt.

- Die taglose Wochenablage wird lokal und kontobezogen gespeichert, da sie keinem Cookidoo-Kalendertag entspricht. Hinzufügen und Entfernen aus Cookidoo erfolgen über die bestehende fünfminütige Warteschlange; auch diese Änderungen werden bestätigt und unklare Ergebnisse nicht blind wiederholt.

- Das X an einem Tagesrezept verschiebt es in die Ablage der angezeigten Woche. Existiert dort bereits dasselbe Rezept, wird der Ablageeintrag atomar erhalten und die Kalenderentfernung mit Rückgängig vorgemerkt. Der Papierkorb eines Ablagerezepts entfernt es lokal mit Rückgängig.

- Der manuelle Synchronisieren-Knopf gibt wartende Wochenänderungen sofort frei; nach der Sammlungssynchronisierung verarbeitet sie der bestehende Kalender-Worker. Fehlgeschlagene oder unklare Schreibvorgänge werden nicht automatisch wiederholt.

- Rückgängig entfernt eine vorgemerkte Kalenderlöschung atomar aus der Warteschlange oder stellt ein Rezept in der Ablage wieder her. Bei manuellem Synchronisieren bleibt das Rückgängig-Zeitfenster geschützt; bereits laufende oder unbestätigte Vorgänge werden nicht blind zurückgesetzt.

- Vormerkungen eines anderen Kontos können nicht verworfen werden. Zutatenmarkierungen im Einkaufswagen werden beim ausdrücklichen Transfer anhand der Cookidoo-Antwort bestätigt.

- Bei eigenen Kreationen steht die App-Notiz am Ende der Cookidoo-Tipps ab „Notiz:“. Das gezielte Cookidoo-PATCH ändert nur das Tippfeld; vor dem Schreiben werden Notiz und Tipps auf Konflikte geprüft, danach Antwort und übrige Rezeptfelder bestätigt. Mehrdeutige Markierungen und unbestätigte Schreibvorgänge werden gemeldet. Ein Test an einer isolierten Rezeptkopie am 02.11.2026 bestätigte den unveränderten Rezeptinhalt und das Bild; die Testkopie wurde gelöscht.

- Rezeptdetails zeigen vorhandene Cookidoo-Tipps in einem zunächst eingeklappten Bereich unter der Zubereitung. Katalog-Zusatzinformationen und Hinweise eigener Kreationen werden beim Synchronisieren gespeichert; fehlende Daten älterer Rezepte werden bei Bedarf nachgeladen.
