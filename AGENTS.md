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
- [rezeptgarten-android](.agents/skills/rezeptgarten-android/SKILL.md): native
  Flutter-App, Android-Oberfläche, Geräteprüfung, APK-Build und In-App-Updates.
- [rezeptgarten-cookidoo](.agents/skills/rezeptgarten-cookidoo/SKILL.md): Cookidoo-
  Sync, Rezeptdetails, Konto, Kalender und Einkaufsliste.
- [rezeptgarten-betrieb](.agents/skills/rezeptgarten-betrieb/SKILL.md): bestehende
  Serverinstanz, SSH, Deployment, Testumgebungen und lokales HTTPS.

## Android

Die Android-Oberfläche verwendet Material 3 Expressive. Das gemeinsame Flutter-
Theme setzt Rollenfarben, betonte Titel, abgerundete Komponenten und einheitliche
Aktionsgrößen um. Die Hauptnavigation wechselt auf breiten Fenstern zur Seitenleiste.
Android nutzt die Grundfarben der Web-App im Hell- und Dunkelmodus. Eine
eigene Akzentfarbe passt Aktionsfarben an und behält die Grundflächen.
Ansichtswechsel folgen beim Wischen dem Finger und berücksichtigen reduzierte Bewegung.
Die Android-Wochenansicht hebt „Heute“ im Tageskopf hervor. Die ISO-Kalenderwoche
steht als Text zwischen zwei umrandeten Wochenpfeilen. Eine kurze Linie
markiert die laufende Berliner Woche. „Heute“ folgt direkt daneben. Das
Einkaufswagensymbol sitzt in derselben Zeile am rechten Inhaltsrand.
Die Android-Ansichten verwenden `AppSpacing` für gemeinsame Seitenränder,
Kartenabstände und Abstände in Gruppen, Formularen und Dialogen.
Android-Rezeptkarten zeigen Dauer links unten und Portionen rechts unten im
Bild. Notiz und Kartenaktion sind kompakt und liegen in den oberen Bildecken.
Gleich breite Android-Karten reservieren zwei Titelzeilen und eine Zeile für den
Schwierigkeitsgrad. Längere Titel werden auf Karten mit Auslassungszeichen gekürzt.
Beim Wischen einer markierten Wochenkachel folgt sie dem Finger und zeigt die
vorgesehene Aktion. Kurze Wische lassen die Kachel zurückkehren. Bei reduzierter
Bewegung bleibt die Aktionsvorschau sichtbar und die Kachel bleibt am Platz.
Die Android-Ansichten Woche und Einkaufswagen verzichten auf dauerhaft
sichtbare Erklärtexte für Wischgesten und Häkchen.
Android markiert Wochenrezepte und abgelegte Platzhalter nach 250 ms. Ein
Wisch nach oben braucht 140 dp, nach unten 90 dp. Die Wochenablage zeigt kompakte
Kacheln nebeneinander, sobald die Breite ausreicht.
Android-Rezeptlisten sind unter ihren Titeln aufklappbar. Langes Drücken auf
einen Listentitel startet das
Verschieben und lässt die Listen wackeln. Ein Häkchen beendet den Modus.
Bei reduzierter Bewegung kennzeichnen Griffe die verschiebbaren Listentitel.
Die Reihenfolge wird auf dem Gerät gespeichert. Die Titelsuche steht unter
„Neue Liste“. Die Titel sind fett gesetzt und farblich vom
zweispaltigen Raster mit Rezeptbildern abgesetzt. Lokale Listen haben ein
Bearbeiten-Symbol. Importierte Cookidoo-Listen zeigen an derselben Stelle
„Zu Cookidoo“. Öffentliche Kollektionen öffnen direkt, persönliche Listen
führen zu „Meine Rezepte“ bei Cookidoo.
Die globale Rezeptsammlung bündelt Suche, Sortierung und Filter.
Einkaufs-Häkchen reagieren in beiden Android-Verbindungsmodi sofort. Während
der Server die Änderung im Hintergrund speichert, bleibt die Zutatenzeile
an ihrer Position und weitere Zutaten bleiben bedienbar. Der Cookidoo-Transfer
wartet auf ausstehende Häkchen. Bei gleichzeitigen Änderungen hat „abgehakt“
Vorrang. Ein erneuter Tipp auf den aktuellen Stand kann das Häkchen entfernen.
Zusatzartikel erhalten ihren Warenbereich über denselben Serverabgleich wie
Rezeptzutaten. Die Rezepte im Android-Einkaufswagen erscheinen als kompakte
Zeilen mit runden Vorschaubildern wie in den Wochenlisten. Neben dem Wagentitel
steht das Symbol „An Cookidoo übertragen“. Einträge lassen sich einzeln entfernen.
Auf schmalen Displays bleiben die Hauptaktionen in der Kopfzeile bedienbar.
Besuchte Listen-, Rezept-, Wochen- und Vorratsansichten behalten beim Tabwechsel
ihren Zustand. Konto- und Verbindungswechsel setzen Ansichten und Bildcache
im Arbeitsspeicher zurück. Wiederholte Netzmeldungen im selben Heim-WLAN
erhalten die sichtbare Ansicht, ihre Bedienbarkeit und den laufenden Abgleich.
Android zeigt Titel, Navigation, Suche und verfügbare Aktionen schon beim
ersten Abruf. Auf Start erscheinen Statistik, Zufallsrezept und Vorschauen
unabhängig voneinander. Der Einkaufswagen zeigt seine Kopfzeile, die Woche ihre
Tage und Rezeptdetails die vorhandene Vorschau sofort. Bereits geladene Inhalte
bleiben während der Aktualisierung sichtbar.
Android speichert freigegebene Rezeptbilder kontobezogen im privaten, von
Backups ausgeschlossenen Speicher. Beim Öffnen im Heimnetz und nach dem
Sammlungsabgleich lädt Android die Vorschaubilder der Sammlung im Hintergrund.
Der Telegram-Modus nutzt gespeicherte Bilder und zeigt für fehlende Bilder
einen Platzhalter bis zum nächsten Heimnetzabruf. Andere API-Antworten verwenden
keinen HTTP-Cache.
Die Übersichtskarte „Deine Sammlung“ steht direkt unter dem Zufallsrezept.
Sie bietet Direktzugriffe auf Rezeptlisten,
alle Rezepte, die Woche und den Einkaufswagen. Die vier Schaltflächen teilen
sich gleich breite Spalten. Auf Handys steht der Einkaufswagen unten rechts,
bei großer Schrift oder knapper Breite stehen die Ziele untereinander.
Reine Textkennzeichen für Rezeptdaten, aktive Filter und Kalender sind kompakt.
Aktionen behalten ein mindestens 48 dp hohes Tippziel auf Android.
Auf schmalen Android-Displays heißt der Übersichts-Tab „Start“. Wenn für die
Schriftgröße zu wenig Platz ist, zeigt die Navigation die sechs Symbole mit
zugänglichen Beschriftungen. Die Rezeptbibliothek zeigt zwei Karten je Reihe,
sobald sie lesbar nebeneinander passen. Die Filter öffnen auf Handys von unten.
Vorhandene Treffer bleiben während einer laufenden Suche sichtbar.
Im Android-Einkaufswagen stehen offene Zutaten und abgehakte Einträge vor den
Rezeptkarten. Die ganze Zutatenzeile schaltet das Häkchen. Zutaten und Rezepte
werden beim Scrollen aufgebaut. „Artikel hinzufügen“ öffnet ein Eingabeblatt.
Im Vorrat öffnet ein Tipp auf die Zutat die Bearbeitung. Das Vorratsmenü bietet
die Kategorieanlage sowie alle Kategorien ein- oder auszuklappen.

In den Android-Einstellungen schaltet „Debug-Modus“ auf lokale Beispieldaten um.
Die Auswahl bleibt beim Neustart gespeichert. Teständerungen an Rezeptnotizen,
Listen, Woche, Einkaufswagen und Vorrat gelten für die laufende App-Sitzung.
Der Modus zeigt „Testdaten“ an und verwendet keine Verbindung zu LXC, Cookidoo
oder Telegram. Beim Ausschalten folgt die normale Verbindungsprüfung.

Die native Flutter-App entsteht unter `android-app/`. Die
[Flutter-Portierung](FLUTTER-PORTIERUNG.md) erfasst Funktionsumfang, Design und
Freigabekriterien. Testbuilds verwenden eine eigene Android-Paket-ID und die
Downloadseite `https://192.168.184.30/android/test/`. Das
Android-Startmenü zeigt für beide Kanäle den Namen „Rezeptmix“. Android und
PWA verwenden das Motiv Schale mit Keimling. Das adaptive Android-Launcher-Icon
verwendet ein größeres Motiv auf einem fast schwarzen Hintergrund. Bei
„Themensymbole“ bestimmt der Launcher die Farben des Motivs und des Hintergrunds.
`scripts/generate_icons.py` erzeugt die PWA-, Kopfzeilen- und Ersatz-PNGs aus
`app/static/icon-512.png`. Das
Veröffentlichungsskript lädt jeden neuen Test- oder Release-Build standardmäßig
auf LXC 103 hoch und prüft den HTTPS-Download und das Update-Manifest des Kanals.
Bei einem Uploadfehler die vorhandene APK mit derselben Buildnummer erneut
veröffentlichen. Der APK-Upload erfolgt getrennt vom Web-Deployment.
In den Android-Einstellungen vergleicht „Nach Updates suchen“ den installierten
`versionCode` mit dem Manifest des eigenen Kanals. Ist ein neuerer Build
verfügbar, wird derselbe Knopf zu „APK herunterladen und installieren“.
Die App lädt die APK über HTTPS, prüft Größe, SHA-256, Paket-ID und Version und
startet den Android-Installer. Android verwaltet Quellenfreigabe und Bestätigung.
Ein fehlgeschlagener Abruf bleibt als Fehler sichtbar und kann wiederholt werden.
Beim Öffnen und Wiederöffnen im Heimnetz prüft Android automatisch auf Updates.
Ein verfügbarer Build zeigt neben der Suche ein Download-Symbol mit Bestätigung.
Kopfzeile und Einstellungen verwenden denselben Updatestatus.
Der Android-Einkaufswagen verwendet die gemeinsamen Wagen-APIs für Rezept- und
Zusatzartikel, Häkchen sowie den bestätigten Cookidoo-Transfer und seine Klärung.
Die Android-Rezeptdetails laden Versionen, Tipps, Listen, Vorratsstatus und Notizen
über die gemeinsamen APIs. „Zu lokalen Listen hinzufügen“ steht zwischen
„Zum Einkaufswagen hinzufügen“ und „In Cookidoo öffnen“. Die Aktion öffnet die
Listenauswahl von unten. Die Liste wird beim Öffnen geladen und jede Änderung
nach Serverbestätigung in der Auswahl und den Rezeptdetails angezeigt.
Ein Notizkonflikt erhält den Entwurf im Feld.
Kontrastreiche Punkte markieren den Zutatenstatus. „Zur Ablage hinzufügen“
speichert das Rezept in der Ablage der aktuellen Berliner Kalenderwoche und
steht direkt über „Diese Woche kochen“. In Aktionspillen stehen Symbol und
Beschriftung als Gruppe mittig, auch bei einem Zeilenumbruch.
„Diese Woche kochen“ öffnet in Android und der Web-App eine Mehrfachauswahl
von heute bis Sonntag nach Berliner Zeit. Cookidoo bestätigt jeden gewählten
Tag einzeln. Unbestätigte Tage werden angezeigt.
Die Android-Rezeptbibliothek unterstützt Titel- und Zutatensuche, Zutatenfilter,
Portionen, Gesamtzeit und Sortierung. Sortieren und Filtern teilen sich die
Reihe unter der Suche gleich breit. Lokale Listen lassen sich anlegen, nach
Bestätigung löschen und um noch nicht enthaltene Rezepte ergänzen.
Android-Rezeptvorschauen verwenden in Übersicht, Bibliothek, Listen und Woche
denselben Kartenrahmen und dieselben Bezeichnungen für Schwierigkeitsgrade.
Das Raster in Übersicht, Bibliothek und Listen richtet sich nach der Breite
und Schriftgröße. Rezeptlisten und Vorratskategorien verwenden dieselbe
getönte Kopfzeile für aufklappbare Gruppen.
Vorratskategorien richten Symbole, Namen und Aktionen in festen Spalten aus.
In Android stehen die Zutatennamen auf derselben Flucht wie die Kategorienamen.
Die Listenbearbeitung zeigt unter „Alle Rezepte“ vorhandene und hinzufügbare
Rezepte mit einer gemeinsamen Suche. Hinzufügbare Karten haben ein Plus oben rechts.
Der Papierkorb rechts neben „In dieser Liste“ aktiviert das X an zugeordneten
Karten. Die Karten wackeln bei aktiver Animation. Das Häkchen an derselben Stelle
beendet den Modus.
Das Papierkorb-Symbol oben rechts in der Titelleiste öffnet die Bestätigung
zum Löschen der Liste.
Der Android-Vorrat verwendet den gemeinsamen Zutatenkatalog und die gespeicherte
Kategorienreihenfolge. Kategorien und Vorratseinträge können wie im Web verwaltet
werden. Beim Löschen einer Kategorie ist die Bestätigung erforderlich.
„Meine Woche“ auf Android verwendet die serverseitige Warteschlange und die
kontobezogene Ablage. Platzhalter, lokale Listen, Halte- und Wischgesten sowie
Rückgängig sind über diese Ansicht erreichbar.
Die Wochenablage zeigt kompakte Rezeptkarten mit dem Bild über dem Titel in
einer seitlich scrollbaren Reihe. Abgelegte Platzhalter haben denselben Rahmen
und zeigen ihr Symbol über dem Titel. Ein Wisch nach unten entfernt den Eintrag.
Die Gruppen „Platzhalter“ und „Lokale Listen“ nutzen dieselben aufklappbaren
Köpfe und Abstände. In lokalen Wochenlisten hat jede Rezeptzeile ein Vorschaubild
und rechts ein Plus. Nach dem Hinzufügen zeigt sie ein Häkchen.
Der Debug-Modus zeigt unterscheidbare mitgelieferte Rezeptbilder.
Die Android-Einstellungen verwenden die gemeinsamen APIs für Cookidoo.
Der Sammlungsabgleich startet beim Öffnen oder Wiederöffnen der Android-App im
Heimnetz und beim Herunterziehen einer Ansicht. Beim Herunterziehen zeigt die
Ansicht den Fortschritt der Aktualisierung. Die App meldet Fehler und prüft den Status
nach vorübergehenden Fehlern erneut. Ältere Statusantworten beenden keinen neu
gestarteten Abgleich. Beim Aktualisieren
von Rezeptdetails bleibt ein ungeklärter Notizentwurf erhalten. Außerhalb des
Heimnetzes startet Herunterziehen den Sammlungsabgleich über Telegram und
aktualisiert anschließend die Ansicht. Beide Modi verwenden dieselbe Berliner
Kalenderlogik und dieselben serverseitigen Einkaufs-Häkchen. Häkchen aus dem
früheren Telegram-Modus bleiben auf dem Gerät. Der frühere
zeitgesteuerte Sammlungsabgleich ist serverweit entfernt, bestehende Intervalle
haben keine Wirkung. Die separate Warteschlange für Wochenänderungen bleibt
aktiv. Dunkelmodus und Akzentfarbe
werden lokal gespeichert.
Android nutzt bei verbundenem WLAN `ThomasWlan` und erreichbarem Server den
lokalen HTTPS-Zugang. Für die WLAN-Namenerkennung fordert Android beide
Standortberechtigungen gemeinsam an, auch beim Wechsel von ungefährer zu
genauer Freigabe. In den Android-Einstellungen erscheint die
Einrichtungsaktion für WLAN bei fehlender genauer Freigabe und für Telegram
bei fehlender Anmeldung oder Kopplung. Bei eingerichteter Kopplung öffnet
die Telegram-Statuszeile die Verwaltung. Außerhalb des Heimnetzes stehen nach
Telegram-Benutzeranmeldung und Kopplung im Heimnetz dieselben sechs
Hauptansichten mit ihren Bearbeitungsfunktionen verschlüsselt zur Verfügung.
Kontoverwaltung, Telegram-Kopplung und APK-Updates verwenden das Heimnetz.
Die App fragt nach Telegram-API-ID und API-Hash, wenn
sie fehlen, und schützt Zugangsdaten und Sitzung auf dem Gerät. Die Android-
Kopplung ist an das bei der Verbindung ausgewählte Cookidoo-Konto gebunden.
Die Web-App benötigt das Heimnetz. Die APK enthält keine Gemini- oder
Google-API-Schlüsselverwaltung.
Die öffentliche Rezeptgarten-CA wird aus dem Container bezogen. Signaturschlüssel,
Gradle-Zugangsdaten und APK-Dateien bleiben außerhalb von Git.

## Telegram-Verbindung

Die Server-API verwaltet das verschlüsselt auf dem Server gespeicherte Token
des Rezeptgarten-Server-Bots. Die Android-App meldet sich mit dem Telegram-
Benutzerkonto an und koppelt dieses im Heimnetz mit dem Server-Bot und dem
aktuellen Cookidoo-Konto. Der Host-Dienst akzeptiert ausschließlich frische,
private Anfragen bestätigter Benutzer. Der Server prüft Verschlüsselung,
Kontobindung und erlaubte Android-Endpunkte. Wiederholte Anfragen mit derselben
Schreibkennung werden abgefangen. Rezeptabfragen mit unverändertem Ergebnis geben
innerhalb der Android-Sitzung nur eine Änderungskennung zurück. Telegram sieht
Metadaten. Unvollständige oder nicht authentifizierte Antworten werden nicht
angezeigt. Nachrichten, Tokens und Schlüssel nicht protokollieren.
Android aktualisiert den Telegram-Lesestand des Rezeptgarten-Bot-Chats beim
Empfang und nach erfolgreichem Versand. Telegram vergibt das zweite Häkchen
einer ausgehenden Nachricht anhand des Lesestands der Empfängerseite.
Der frühere Client-Bot und der Telegram-Zugriff der Web-App sind entfernt.
Beim Start entfernt die Web-App alte lokale Bot-Zugangsdaten; der Server verwirft
alte Bot-Kopplungen und behält bestehende Android-Benutzerkopplungen.
Die öffentliche App-Hülle bleibt im Service-Worker-Cache; persönliche API-
Antworten werden nicht gecacht.

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

Die Versionsnummern verlinken die Änderungsverläufe. Jede relevante Änderung
ergänzt den Eintrag der neuen Version in `app/static/changelog.html` für die
Web-App oder in `android-app/assets/changelog.txt` für Android.

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
bei laufendem Sammlungsabgleich kommt der Kalenderabruf zwischen dessen
Cookidoo-Anfragen zum Zug.
Pfeile wechseln die Woche, „Heute“ zeigt in Web-App und Android den heutigen Berliner Kalendertag, auch aus einer anderen Woche;
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
Liste“ gesammelt; der nächste angestoßene Abgleich aktualisiert die lokale Sammlung. Eigene Kreationen
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
In den Web-Rezeptdetails öffnet „Zu lokalen Listen hinzufügen“ die Listenauswahl.
Die Aktion steht zwischen „Zum Einkaufswagen hinzufügen“ und „In Cookidoo öffnen“.
Die Rezeptdetailansicht zeigt zugeordnete Listen über dem Titel und vorhandene
Notizen direkt an. Notizen werden im Feld mit Enter oder beim Verlassen gespeichert;
Umschalt+Enter fügt einen Zeilenumbruch ein. Zutaten sind zunächst aufgeklappt,
die Zubereitung eingeklappt. Vorhandene Cookidoo-Tipps stehen darunter in einem
eigenen zunächst eingeklappten Bereich. Hinweise eigener Kreationen und Tipps von
Katalogrezepten werden beim Synchronisieren gespeichert und für ältere Rezepte bei
Bedarf nachgeladen.
In der Web-App folgen Rezeptkacheln in Woche und Ablage dem Design der Rezeptliste und zeigen
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
Der automatische Web-Abgleich lässt die Wartezeit der Wochenänderungen bestehen.
Der Kalenderabgleich folgt nach der laufenden Sammlungssynchronisierung.
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
Zusatzartikel und Vorhanden-Markierungen sind lokal bearbeitbar.
„Artikel hinzufügen“ schlägt beim Tippen gespeicherte Vorratsartikel vor.
Ein Tipp übernimmt den Artikelnamen ins Feld. Freitext bleibt möglich.
Der Vorrat belegt die Markierungen vor.
Aktuell im Vorrat enthaltene Rezeptzutaten werden ausgeblendet;
ihre gespeicherten Einkaufsdaten bleiben erhalten. Zutaten stehen kompakt mit Checkbox,
Mengenangabe und Rezeptname; gleiche Zutaten bleiben gruppiert. Abgehakte Zutaten
und Zusatzartikel stehen unter allen noch benötigten. Bereits in Cookidoo enthaltene
Rezepte bleiben unverändert.
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

„Alle Rezepte“ bietet in der Web-App globale Zutaten-, Portions- und Zeitfilter.
In der Web-Rezeptsammlung wechselt „Cookidoo“ zur Katalogsuche. Treffer und ihre
Rezeptdetails werden lesend geladen. Katalogbilder werden privat und kurz
zwischengespeichert. Die Katalogsuche verändert die Sammlung und ihre Listen
nicht. In der Übersicht kann das Zufallsrezept aus dem Cookidoo-Katalog stammen.
Bei einem fehlgeschlagenen Katalogabruf kennzeichnet die Übersicht einen
verfügbaren Ersatz aus der lokalen Sammlung.
Die Web-Kopfzeile zeigt die Einstellungen rechts neben dem Einkaufswagen.
Die Suchleiste ist auf Desktop bis zu 560 Pixel breit. Die Lupe und der
Platzhalter kennzeichnen die Suche. Platzhalter und Suchtext haben innen
16 Pixel Abstand zum linken Feldrand, auf dem Handy 14 Pixel.
Cookidoo-Verbindung und letzter Abgleich stehen unten in der Desktop-Seitenleiste.
Der Cookidoo-Abgleich startet beim Öffnen, bei Rückkehr und regelmäßig in der
sichtbaren Web-App mit höchstens einem automatischen Start je fünf Minuten.
Die Web-Einstellungen zeigen „App installieren“ auf Android und laden die reguläre
APK oder, solange nur der Testkanal veröffentlicht ist, die Test-APK herunter.

„Zutat hinzufügen“ nutzt in Android und Web-App die volle Inhaltsbreite
der Vorratsansicht einschließlich der üblichen Seitenabstände.
Vorratskategorien starten in Android und Web eingeklappt und merken ihren
Zustand für die laufende Sitzung. Die Suche zeigt passende Zutaten direkt an.

Die Symbolauswahl für Zutaten, Vorratskategorien und lokale Rezeptlisten enthält
auch Lebensmittel und Haushaltsartikel wie Kartoffeln und Toilettenpapier.
Gewählte Listensymbole erscheinen auch in der Woche und in Rezeptdetails.
Gespeicherte Zutatensymbole werden in Rezeptdetails und im Einkaufswagen
über dieselbe Zutatenzuordnung wie im Vorrat übernommen. Der Android-Wagen
über Telegram zeigt sie ebenfalls. Alle Warenbereiche im Einkaufswagen
haben ein Symbol am Gruppentitel. Gewählte Vorratssymbole haben Vorrang,
bestehende Standardbereiche zeigen ein passendes Symbol und sonstige
Bereiche einen Korb.

In Web und Android lassen sich Symbole für Zutaten, Vorratskategorien und
lokale Rezeptlisten beim Anlegen und Bearbeiten wählen. „Standard“ stellt die
automatische Darstellung wieder her. Gewählte Symbole werden in SQLite gespeichert.

Die Web-Listenansicht zeigt „Zurück zu deinen Listen“ als Pille. Bei lokalen
Listen stehen Bearbeiten und Löschen nebeneinander über dem Filterbereich.
Cookidoo-Listen zeigen ihre Beschreibung unter dem Titel.

Lokale Rezeptlisten und Vorratskategorien können nach Bestätigung gelöscht werden.
Beim Löschen einer Kategorie werden deren Vorratseinträge mit gelöscht; bei lokalen
Listen entfallen die Listenzuordnungen. Cookidoo-Listen können derzeit nicht in der
App gelöscht werden.

Auf dem Handy stehen sechs Hauptbereiche in einer unteren Navigationszeile; die
Einstellungen sind über das Zahnrad in der Kopfzeile erreichbar.
In Android wechselt horizontales Wischen im Inhaltsbereich zum benachbarten
Hauptbereich. Flutter berücksichtigt beim Einrasten Zugstrecke und
Wischgeschwindigkeit. Beim Überqueren der Bildschirmmitte wechselt die
Markierung unten sofort. Der Tabwechsel verwendet bereits geladene Ansichten
weiter. Erst nach dem Einrasten wird der Zielbereich aktiv und lädt vorgemerkte
Änderungen. Beim schnellen Loslassen kurz vor dem Ziel bremst der Hauptbereich
über die verbleibende Strecke und rastet ohne Zurückfedern ein.
Der Android-Testkanal verwendet vorab kompilierten Flutter-Code
im Profilmodus. Änderungen an den Daten und angeforderte Aktualisierungen lösen
gezielte neue Abrufe aus. Antippen eines Tabs nutzt denselben Seitencontroller.
Bei reduzierter Bewegung wechselt die Ansicht direkt. Im Kalender von
„Meine Woche“ blättert dieselbe Geste weiterhin zwischen den Tagen.
Beim Aktualisieren bereits geladener Listen, Vorratskategorien und Wocheninhalte
bleibt deren Position erhalten.

Beim Öffnen eines Wochenrezepts erscheint die Detailansicht direkt. Nach reinem
Lesen behalten Woche und Bibliothek ihren geladenen Stand. Eine geladene Notiz
ist während des Abrufs von Tipps und Listen bearbeitbar. Bestätigtes Hinzufügen
im Rezeptdetail aktualisiert den Rezeptzähler in der Kopfzeile. Beide Android-
Verbindungsmodi zeigen Kalenderdaten im deutschen Format und bauen Einkaufszutaten
beim Scrollen auf.
