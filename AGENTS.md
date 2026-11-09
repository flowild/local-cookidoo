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

## Telegram

Die Einstellungen speichern ein Server-Bot-Token verschlüsselt auf dem Rezeptgarten-Server
und ein Client-Bot-Token unverschlüsselt im jeweiligen Browser. Sie zeigen nur an,
ob ein Token vorhanden ist. Mit „Bots verbinden“ wird der Client-Bot für den
Server-Bot zugelassen; ein ausdrücklich gestarteter Nachrichtentest erwartet eine
Bestätigung mit zufälliger Kennung. Beide Bots benötigen Bot-zu-Bot-Freigabe und
einen eigenen Update-Kanal ohne parallelen Webhook oder andere Verbraucher. Der
Server-Bot-Dienst läuft auf dem Proxmox-Host und verarbeitet nur frische private
Test-, Wochen- und Einkaufswagenanfragen des zugeordneten Bots. Dabei werden Telegram-Updates abgerufen
und bestätigt. Nach vorheriger Verbindung im Heimnetz ist der Test auch ohne Heimnetz
mit Internetzugang möglich. Bei nicht erreichbarem Server bleibt der Status des
Server-Tokens unbekannt; Browserdaten können vom Browser gelöscht werden. Keine
Tokens oder Nachrichten protokollieren.

Der Einkaufswagen kann ohne Heimnetz bei vorhandener Internetverbindung über Telegram
lesend geladen werden. Dafür Bots nach Einführung dieser Funktion im Heimnetz erneut
verbinden: Der Browser erstellt einen AES-256-GCM-Schlüssel, der serverseitig im Vault
liegt und im jeweiligen Browser gespeichert wird. Einkaufsdaten werden vor der Übertragung
verschlüsselt; Telegram sieht Metadaten. Der Wagen ist an das bei der Kopplung aktuelle
Konto gebunden, bei Kontowechsel ist eine erneute Kopplung nötig. Die Ansicht ist eine
Momentaufnahme und unterwegs nicht bearbeitbar. Telegram-Antworten tragen zufällige
Anfragekennungen; unvollständige oder nicht authentifizierte Antworten nicht anzeigen.
Im Telegram-Einkaufswagen stehen Checkboxen und Texte auch auf dem Handy linksbündig
in kompakten Zeilen; die Checkboxen zeigen den gespeicherten Stand an und sind lesend.
Zutaten und Zusatzartikel zeigen dieselben lokal in der App-Hülle enthaltenen Icons
wie die übrigen Ansichten. Über Telegram kommen lediglich die Angaben für die
Symbolauswahl, keine Icon-Bilddateien.
Beim Anzeigen der Telegram-Wochenansicht oder des Telegram-Einkaufswagens kennzeichnet
ein blaues Papierflieger-Symbol in der Kopfzeile den Telegram-Modus; nach erfolgreichem
Laden derselben Ansicht aus dem Heimnetz verschwindet es wieder.
Beim App-Start und Einkaufswagenabruf wird die Erreichbarkeit des Heimnetz-Servers
maximal 2,5 Sekunden abgewartet; Schreibvorgänge erhalten kein solches Zeitlimit.
Der Service Worker lädt die zuvor installierte öffentliche App-Hülle beim Neustart
direkt aus seinem Cache, damit ein nicht erreichbares Heimnetz den Start nicht blockiert.
Die App muss auf dem Gerät zuvor online geöffnet worden sein; der Browser kann seine
Speicherdaten löschen. Persönliche API-Antworten bleiben vom Cache ausgeschlossen.
Der Telegram-Abruf sendet die Anfrage unmittelbar und verarbeitet ältere Updates
nur zur Fortschaltung; angezeigt wird ausschließlich die zur Anfrage passende Antwort.
Geeignete Browser fordern die komprimierte Momentaufnahme an; diese wird vor der
Verschlüsselung komprimiert, um die Zahl der Telegram-Nachrichten zu verringern.
Ohne Heimnetz zeigt „Meine Woche“ über denselben verschlüsselten Kanal eine rein
lesende Wochenübersicht mit Tagesrezepten, lokalen Platzhaltern und Ablage. Pfeile
und „Diese Woche“ wechseln die Woche. Der Server liest Cookidoo über den gemeinsamen
Client und berücksichtigt vorgemerkte Verschiebungen; Fehler und unklare Warteschlangen
bleiben sichtbar. Es werden keine Bilder oder Notizinhalte übertragen. Zugriff ist an
das bei der Bot-Kopplung gewählte Konto gebunden.

## Vertrauliche Daten

`.local/`, `.qa-venv/`, Datenbanken, Token-Dateien, Zertifikatsartefakte und
Testergebnisse sind von Git ausgeschlossen. Der SSH-Schlüssel hat keinen `.key`-
Suffix: Sein Schutz beruht auf dem Ausschluss des gesamten `.local/`-Verzeichnisses
und den Windows-ACLs. Keine Schlüssel, Tokens oder Passwörter in Quellcode, Logs,
Antworten oder Git aufnehmen; keine privaten CA-Schlüssel vom Server kopieren.
Produktive Daten und Konten erhalten und Tests mit isolierten Daten ausführen.
Zugangsdaten nur an die eingerichtete und autorisierte Cookidoo-Zieladresse senden.

## Deployment

Änderungen an der App nach der Prüfung auf die bestehende Serverinstanz übertragen
und dort ihre Bereitstellung prüfen. Den Projektskill rezeptgarten-betrieb beachten;
Produktivdaten und Konten erhalten.

## Versionierung und Git

Die App-Version steht ausschließlich als `APP_VERSION` in `app/version.py` und
erscheint in der App sowie unter `/api/health`. Bei jeder relevanten App-Änderung
die Version nach SemVer erhöhen: Patch für Korrekturen, Minor für abwärtskompatible
Funktionen, Major für inkompatible Änderungen. Die Cacheversion des Service Workers
und die URLs statischer Dateien bleiben davon unabhängig und müssen bei Änderungen
der App-Hülle nach den PWA-Regeln aktualisiert werden. Nach Prüfung und Deployment
jede Versionsänderung samt zugehörigen Änderungen committen und nach `origin/main`
pushen. Vorhandene fremde Änderungen beachten, Remote-Änderungen erhalten und niemals
Force-Push verwenden. Zugangsdaten und persönliche Daten bleiben aus Git ausgeschlossen.

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

Persönliche Notizen von Katalogrezepten werden direkt aus Cookidoo geladen und dort
gespeichert. Bei eigenen Kreationen steht die App-Notiz am Ende der Cookidoo-Tipps
unter „Notiz:“; ein gezieltes PATCH ändert nur dieses Tippfeld. Vor dem Schreiben
werden die geladene Notiz und Tipps auf Konflikte geprüft, danach werden Ergebnis
und übrige Rezeptfelder erneut geprüft. Mehrdeutige Markierungen und unbestätigte
Schreibvorgänge müssen sichtbar bleiben. Notizinhalte nicht protokollieren.
Vor dem Schreiben wird die zuletzt geladene Fassung mit Cookidoo verglichen;
bei Konflikten darf der ungespeicherte Text nicht still verworfen werden.
In der Wochenansicht zeigt ein Symbol auf dem Rezeptbild vorhandene Notizen an;
Gesamtzeit und Portionen stehen ebenfalls auf dem Bild. Die Notizbearbeitung
erfolgt über die Rezeptdetailansicht.
Die Rezeptdetailansicht zeigt zugeordnete Listen über dem Titel und vorhandene
Notizen direkt an. Notizen werden im Feld mit Enter oder beim Verlassen gespeichert;
Umschalt+Enter fügt einen Zeilenumbruch ein. Zutaten sind zunächst aufgeklappt,
die Zubereitung eingeklappt. Vorhandene Cookidoo-Tipps stehen darunter in einem
eigenen zunächst eingeklappten Bereich. Hinweise eigener Kreationen und Tipps von
Katalogrezepten werden beim Synchronisieren gespeichert und für ältere Rezepte bei
Bedarf nachgeladen.
Rezeptkacheln in Woche und Ablage folgen dem Design der Rezeptliste und zeigen
vollständig umgebrochene Namen sowie den verfügbaren Schwierigkeitsgrad.

Rezeptbilder liegen lokal als WebP bis 960 Pixel; Kacheln erhalten bei Bedarf
erzeugte Vorschauen bis 480 Pixel. Erfolgreiche Bildantworten dürfen einen Tag im
privaten Browsercache liegen, aber nicht im Service-Worker-Cache. Andere persönliche
API-Antworten bleiben `no-store`. Nicht lokal vorhandene Wochenbilder werden erst
bei ihrer Bildanfrage heruntergeladen und blockieren nicht die Wochenansicht.

Unter jeder Woche liegt eine lokale, kontobezogene Ablage für Rezepte ohne festen
Tag. Änderungen an Cookidoo-Kalendereinträgen werden über die bestehende Warteschlange nach fünf
Minuten übertragen und bestätigt. Die Ablage selbst existiert nur in Rezeptgarten;
ihre Rezepte gehören beim Wocheneinkauf zur ausgewählten Woche.
Wochenkacheln lassen sich mit der Maus zwischen Tagen und Ablage ziehen; auf
Touchgeräten aktiviert langes Berühren die Auswahl zum Verschieben. Kurzes Tippen
und Scrollen bleiben möglich. Eine Griffleiste oder Zielauswahl gibt es nicht.
Mobile Tagesspalten bieten freie Fläche zum Scrollen.
Beim horizontalen Scrollen auf dem Handy rasten die Tage mittig ein. Der zuletzt
angezeigte Wochentag bleibt im Browser auch nach Neuladen und Wochenwechsel erhalten.
Auf dem Handy markiert etwa 500 ms langes Halten ein Rezept oder einen Platzhalter;
sofortiges Wischen über die Kacheln scrollt normal. Bei markierter Kachel steuern
vertikale Wischbewegungen ab 90 Pixeln die Aktion statt zu scrollen. Die Markierung
bleibt auch nach Loslassen erhalten und endet nach einer Aktion oder durch Tippen.
Ein vertikaler Wisch über ein Tagesrezept verschiebt dieses nach unten
in die Ablage oder entfernt es nach oben. Bei Ablagerezepten sortiert ein Wisch nach
oben in den eingerasteten Tag ein, nach unten entfernt er das Rezept. Entfernungen
nutzen die vorhandene Rückgängig-Funktion.
Dieselben Wischrichtungen gelten für einzelne Platzhalter in Tagen und Ablage;
deren Entfernen erfolgt wie beim Papierkorb unmittelbar ohne Rückgängig-Funktion.
Langes Drücken auf Rezepten öffnet auf Touchgeräten kein Browser-Kontextmenü.
Das native Browser-Ziehen der Wochenkacheln und Bilder ist bei Touchbedienung
deaktiviert, damit es die Haltegeste nicht übernimmt; Mausziehen bleibt verfügbar.
Rezeptvorschauen zeigen links oben vorhandene persönliche Notizen und bieten rechts
oben einen Knopf für die lokale Ablage der aktuellen Berliner Kalenderwoche. In
„Meine Woche“ verschiebt stattdessen ein X Tagesrezepte in die Ablage der angezeigten
Woche; ein Papierkorb entfernt Ablagerezepte rückgängig machbar. Ist das Rezept schon
in der Ablage, bleibt dieser Eintrag erhalten und nur der Tageseintrag wird entfernt.
Auch nicht lokal gespeicherte Wochenrezepte werden bei Bedarf aus Cookidoo geprüft.
Der Notizstatus wird für sichtbare Vorschauen kontobezogen im Hintergrund geladen;
Notizinhalte werden dabei nicht ausgegeben. Der Ablageknopf plant keinen Cookidoo-Tag.
Der manuelle Synchronisieren-Knopf gibt wartende Wochenänderungen sofort zum
Abgleich frei; der Kalenderabgleich folgt nach der laufenden Sammlungssynchronisierung.
Fehlerhafte oder unklare Warteschlangeneinträge werden dabei nicht erneut ausgeführt.
Unter der Wochenablage zeigen aufklappbare lokale Listen ihre Rezepte. Das Plus
speichert ein ausgewähltes Listenrezept in der Ablage der angezeigten Woche; ein zusätzlicher Ablageknopf erscheint dort nicht.
Nach dem Entfernen aus der Woche kann der Nutzer die Änderung fünf Sekunden lang
rückgängig machen; ein Kreis zeigt die verbleibende Zeit. Vorgemerkte Cookidoo-
Löschungen müssen beim Rückgängigmachen sicher entfallen.
„Stärke“ und „Speisestärke“, „Bio-Vanille“ und „Vanilleextrakt“ sowie Spaghetti,
Nudeln und Pasta gelten beim Zutaten- und Vorratsabgleich als gleichwertig; andere
Vanilleprodukte und Spaghettikürbis bleiben getrennt.
Fehlgeschlagene Wochenabfragen dürfen keine Einträge in einer zuvor angezeigten
Woche verändern. Vorgemerkte Änderungen eines anderen Kontos dürfen nicht verworfen
werden. Vorratsmarkierungen auf der Einkaufsliste müssen bestätigt werden.

Unter der Wochenablage stehen die festen Platzhalter „Im Restaurant essen“,
„Fastfood“, „Sushi“, „Pasta mit Pesto“, „Abendbrot“ und „Resteessen“ in einer
einklappbaren Liste über den lokalen Listen. Das Plus legt sie auch mehrfach
kontobezogen in der Ablage der angezeigten Woche ab; dort lassen sie sich einzeln
entfernen. Ein X verschiebt Tagesplatzhalter zurück in die Ablage. Platzhalter lassen
sich mit der Maus aus der Liste oder Ablage auf Wochentage und zwischen Tagen ziehen.
Die Position wird kontobezogen und wochenweise lokal gespeichert. Die Einträge
enthalten keine Zutaten und werden nicht nach Cookidoo übertragen oder in den
Einkaufswagen übernommen.

## Mein Einkaufswagen

Der kontobezogene lokale Einkaufswagen liegt zwischen „Meine Woche“ und „Mein Vorrat“.
Das Einkaufswagensymbol in der Kopfzeile öffnet den Wagen und zeigt die Anzahl seiner
Rezepte; Zusatzartikel zählen nicht mit. Die Anzeige wird bei Änderungen aktualisiert.
Alle Hinzufügen-Knöpfe schreiben lokal; ausschließlich „An Cookidoo übertragen“
schreibt nach Cookidoo. Rezeptversionen und Zutaten werden als Schnappschuss gespeichert,
Zusatzartikel und Vorhanden-Markierungen sind lokal bearbeitbar. Der Vorrat belegt
die Markierungen vor. Zutaten stehen kompakt mit Checkbox, Mengenangabe und
Rezeptname; gleiche Zutaten bleiben gruppiert. Abgehakte Zutaten stehen unter den
noch benötigten. Bereits in Cookidoo enthaltene Rezepte bleiben unverändert.
Der Transfer verwendet den gemeinsamen Cookidoo-Client und Lock, bestätigt Erfolge,
speichert ungeklärte Ergebnisse dauerhaft und wiederholt sie nicht automatisch.
Nach Prüfung in Cookidoo kann der Nutzer ungeklärte Einträge ausdrücklich auf vorhanden
oder erneut übertragbar setzen. Lokale Daten bleiben bis zum ausdrücklichen Entfernen
oder Leeren erhalten; die SQLite-Sicherung und der Export enthalten den Wagen.

Rezeptkarten zeigen Bild, Notizsymbol, Papierkorb sowie verfügbare Dauer und
Portionen. Zutaten stehen nach Warenbereichen gruppiert; Vorratszuordnungen haben
Vorrang, unbekannte Zutaten kommen nach „Sonstiges“. Kleine Symbole entsprechen
denen in Vorrat und Rezeptdetails. Wasser wird in Zutatenansichten, Einkaufswagen,
Vorrat und Zutatenauswahl ausgeblendet; andere Zutaten wie Kokoswasser sowie
Zubereitungsschritte bleiben sichtbar. Einkaufsdaten bleiben erhalten.

## Listen, Vorrat und Navigation

Lokale Rezeptlisten und Vorratskategorien können nach Bestätigung gelöscht werden.
Beim Löschen einer Kategorie werden deren Vorratseinträge mit gelöscht; bei lokalen
Listen entfallen die Listenzuordnungen. Cookidoo-Listen können derzeit nicht in der
App gelöscht werden.

Auf dem Handy stehen sechs Hauptbereiche in einer unteren Navigationszeile; die
Einstellungen sind über das Zahnrad in der Kopfzeile erreichbar.
