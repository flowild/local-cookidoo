# Android-App: Stand der Fehlerprüfung

Stand vom 22. November 2026. Die Android-Prüfung wurde fortgesetzt. Dieses Dokument
hält die geprüften Abläufe, die lokalen Korrekturen und die ausstehende Abnahme fest.

## Bisher untersucht und bearbeitet

- **Navigation und Verbindungswechsel:** Bei einer vorübergehenden Netzwerkprüfung
  sprang die App von Listen, Rezepten oder Vorrat zur Wochenansicht. Die lokale
  Änderung erhält die ausgewählte Seite, solange die Verbindung geprüft wird.
  Ein Widgettest deckt auch den anschließenden Wechsel in den Telegram-Modus ab.
- **Abgleichstatus:** Eine einzelne fehlgeschlagene Statusabfrage beendete die
  Anzeige eines laufenden Abgleichs. Außerdem konnte eine ältere Antwort aus einer
  Ansicht einen neu gestarteten Abgleich als beendet darstellen. Die lokale
  Änderung versucht fehlgeschlagene Statusabfragen erneut und unterscheidet
  Statusantworten anhand des aktuellen Abgleichs. Gezielte Widgettests für beide
  Fälle bestanden.
- **Wochentag:** Ein verspätet geladener gespeicherter Wochentag konnte eine
  zwischenzeitliche Nutzerauswahl überschreiben. Die lokale Korrektur und ein
  Widgettest sichern die Nutzerauswahl ab.
- **Wocheneinkauf:** Die App meldete auch bei einer leeren Woche oder bereits
  vorhandenen Rezepten eine erfolgreiche Übernahme. Die lokale Änderung zeigt
  abhängig von der Serverantwort eine passende Meldung. Ein Test prüft leere,
  bereits vorhandene und hinzugefügte Rezepte.
- **Herunterziehen zum Aktualisieren:** Die Funktion fehlte in Rezeptdetails und
  in der Rezeptauswahl innerhalb einer Liste. Sie wurde lokal ergänzt. In den
  Rezeptdetails wird vor dem Aktualisieren ein geänderter Notizentwurf gespeichert;
  bei einem Konflikt bleibt der Entwurf erhalten und der Abgleich wird nicht
  gestartet. Die betreffenden Widgettests bestanden.
- **Rezeptkacheln:** Der Schwierigkeitsgrad `advanced` erschien auf Englisch und
  `hard` wich von der Beschriftung in den Details ab. Beide werden lokal wie in
  den Details als „Anspruchsvoll“ dargestellt; ein Widgettest prüft `advanced`.
- **API:** Neue isolierte Tests prüfen ein Zeitlimit bei stockendem Antwortinhalt
  und dass eine Schreibanfrage keiner Weiterleitung zu einem anderen Origin folgt.
- **Bildschirmgrößen:** Isolierte Widgettests für Einstellungen und Hauptnavigation
  auf einem 320 Pixel breiten Bildschirm mit größerer Schrift bestanden.

## Fortsetzung am 20. November 2026

- **Telegram-Einkaufswagen:** Frühe Änderungen konnten gespeicherte Häkchen anderer
  Artikel überschreiben. Die App lädt sie vor den ersten Änderungen und bietet nach
  einem Lesefehler einen erneuten Versuch an. Beim Wiederöffnen wartet der Lesezugriff
  auf noch ausstehende Schreibvorgänge.
- **Telegram-Woche:** Die Navigation behandelt Tage als Kalenderdaten. Beim
  Zurückblättern über die Berliner Umstellung auf Sommerzeit bleibt der Montag
  erhalten.
- **Telegram-Anmeldung:** Wenn der Dialog während einer Anfrage geschlossen wird,
  greift die Antwort auf kein bereits freigegebenes Eingabefeld mehr zu.
- **WLAN-Erkennung:** Beim Wechsel von ungefährer zu genauer Standortfreigabe
  fordert die App beide Standortberechtigungen gemeinsam erneut an. Das ermöglicht
  den dafür vorgesehenen Android-Systemdialog.
- **Flutter:** Die Analyse lief nach einer Korrektur im Verbindungstest ohne
  Befund durch. Alle 32 Tests bestanden gemeinsam in WSL mit `Europe/Berlin`.
  Der erste Lauf erreichte das sechsminütige Zeitlimit des Buildskripts. Der
  vollständige Wiederholungslauf verwendete eine lokale Skriptkopie ohne dieses
  Zeitlimit.
- **Backend:** 128 Tests bestanden unter Windows. Die beiden dort übersprungenen
  Linux-Tests des APK-Publishers bestanden separat in WSL.

Mit isolierten Daten geprüft sind die Verbindungsauswahl, Abgleich und Wiederholung
nach Statusfehlern, lokale Listen, Suche mit Zutatenfiltern, Rezept- und
Notizdetails, Wochenwechsel, Wischen samt Rückgängig, Einkaufsübernahme, lokale
Häkchen, ungeklärte Transfers, Vorrat und Kategorie-Löschung. Widgettests prüfen
Konto, JSON-Export und APK-Update bis zu ihren jeweiligen Schnittstellen.
Telegram-Tests prüfen verschlüsselte Antwortteile, Wochenwechsel, Häkchen und den
Anmeldedialog.

Im isolierten Emulator mit Android 35 startete die separate x86_64-Prüf-APK.
Nach vorbereiteter ungefährer Standortfreigabe bot Android den Wechsel zu genauer
Freigabe an und bestätigte anschließend beide Berechtigungen. Rezeptgarten zeigte
danach die Telegram-Einrichtung. Die ARM64-APK ließ sich im Emulator installieren;
der Start über die ARM-Übersetzung erreichte dort keine bedienbare App-Oberfläche.

## Debug-Modus

Version `1.2.0` ergänzt in den Android-Einstellungen den Schalter „Debug-Modus“.
Die normalen Ansichten lassen sich mit lokalen Beispieldaten bedienen. Änderungen
an Testdaten gelten für die laufende App-Sitzung. Android merkt sich die Auswahl
des Modus für den nächsten Start. Die Flutter-Analyse war ohne Befund. Alle 34
Flutter-Tests bestanden, darunter der Wechsel bei unerreichbarem Server und ein
Test für isolierte Notizen, Wochenänderungen und den JSON-Export der Beispieldaten.
Die signierte ARM64-APK für Testbuild **19** liegt lokal unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.2.0-build19.apk`.
Das Veröffentlichungsskript hat Signatur, Paket-ID, Architektur und Version geprüft.
Im Android-35-Emulator wurde Testbuild 19 mit x86_64 im Flugmodus geprüft. Der
Schalter ließ sich ohne WLAN- oder Telegram-Einrichtung einschalten. Die Woche
übernahm zwei weitere Beispielrezepte in den Einkaufswagen. Nach einem vollständigen
App-Neustart blieb der Debug-Modus aktiv und der Wagen enthielt wieder die
ursprünglichen Beispieldaten. Das Ausschalten wurde gespeichert. Der Emulator
zeigte beim Kaltstart zeitweise einen Android-Wartehinweis.

## Material 3 Expressive

Version `1.3.0` aktualisiert die Android-Oberfläche. Das gemeinsame Expressive-Theme
gilt in den Hauptansichten sowie in Detailseiten, Einstellungen und Dialogen.
Die Navigation passt sich der Fensterbreite an. Die Wochenansicht gruppiert die
Datumsschalter und verwendet eine kontrastierende Rollenfarbe für den heutigen Tag.
Die Analyse war ohne Befund, alle 35 Flutter-Tests und 130 Backend- und
Publisher-Tests bestanden. Flutter-Tests prüfen unter anderem die Navigation beim
Wechsel zwischen kompaktem und breitem Fenster sowie die gesperrten Ziele im
Telegram-Modus. Auf schmalen Rezeptkarten misst die Bildfläche den Platz für
Zeit und Portionen, damit die Aktion in der oberen Ecke frei bleibt.

Die signierte ARM64-APK für Testbuild **21** liegt lokal unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.3.0-build21.apk`.
Signatur, Paket-ID, Architektur und Versionsangaben wurden geprüft.
Der Android-35-Emulator zeigte Testbuild 21 im Flugmodus auf Handybreite im
Hellmodus sowie mit erweiterter Seitenleiste im Dunkelmodus. In den breiten
Wochenansichten blieben Zeit- und Portionsschild unter der Kartenaktion sichtbar.

Version `1.3.1` vereinheitlicht die Abstände in den Android-Ansichten und Dialogen.
Der Wochenplan zeigt sieben gleichmäßig getrennte Spalten, sobald die verfügbare
Breite für ihre Bedienelemente ausreicht. Der Flutter-Analyselauf war ohne Befund,
alle 35 Flutter-Tests bestanden. Die Windows-Testsuite meldete 128 erfolgreiche
Tests und zwei übersprungene Tests.

Die signierte ARM64-APK für Testbuild **22** liegt lokal unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.3.1-build22.apk`.
Paket-ID, Version und Architektur wurden geprüft. Die Signatur entspricht Build 21.
Im Android-35-Emulator im Flugmodus wurden die Einstellungen und die Woche auf
Handybreite sowie die sieben gleichmäßig getrennten Spalten auf Tabletbreite
geprüft.

Version `1.3.2` richtet die Wochenaktionen auf einer Höhe aus und verwendet das
Abstandsraster auch bei umgebrochenen Einkaufsaktionen, Telegram-Abschnitten und
dem Übergang zur Vorratsliste. Der Wochen-Widgettest misst die gemeinsame Höhe
der Bedienelemente und den 12-dp-Abstand zwischen zwei Tagesspalten. Die Analyse
und alle 35 Flutter-Tests bestanden. Die signierte ARM64-APK für Testbuild **23**
liegt lokal unter `android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.3.2-build23.apk`.
Paket-ID, Version, Architektur und die unveränderte Signatur wurden geprüft.

Version `1.3.3` trennt Zeit und Portionen in den unteren Bildecken und
verkleinert die sichtbaren oberen Aktionen. Die Wischvorschau zeigt beim
Bewegen der Kachel das Ziel. Ein Widgettest prüft die Positionen in schmalen
Spalten sowie Vorschau, Rückkehr unterhalb der Wischschwelle und Ausführung
erst beim Loslassen. Die Flutter-Analyse war ohne Befund und alle 35 Tests
bestanden. Die signierte ARM64-APK für Testbuild **24** liegt lokal unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.3.3-build24.apk`.
Paket-ID, Version, Architektur und die unveränderte Signatur wurden geprüft.
Im Android-35-Emulator im Flugmodus waren die Badges auf Handybreite und in
den schmalen Tablet-Spalten getrennt sichtbar. Eine Touch-Aufnahme vor dem
Loslassen bestätigte die verschobene Kachel mit „In die Ablage“.

Version `1.3.4` erhält den Zustand häufig genutzter Tabs, zeigt beim Nachladen
eines geöffneten Einkaufswagens den bisherigen Stand und begrenzt breite
Rezeptdetails auf eine 720-dp-Lesespalte. Bildabrufe werden gebündelt und
freigegebene Bilder wiederverwendet. Alle 37 Flutter-Tests bestanden. Die neuen
Tests prüfen unter anderem Sucherhalt ohne weiteren Abruf, korrektes Leeren des
Wagenzählers und die Wiederverwendung von Bilddaten.
Die signierte ARM64-APK für Testbuild **25** liegt lokal unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.3.4-build25.apk`.
Paket-ID, Version, Architektur und die unveränderte Signatur wurden geprüft.
Der Android-35-Emulator zeigte die mittige Detailspalte im Querformat und die
kompakte Kopfzeile im schmalen Format. Bei rund 332 dp brach „Übersicht“ in der
Navigation um. Der sehr langsame Start in der x86-Umgebung löste Androids
Wartehinweis aus. Danach ließen sich Ansichten und Rezeptdetails bedienen.

Version `1.3.5` verwendet „Start“ im schmalen Navigationslayout und zeigt
Rezeptfilter auf Handys als Bottom Sheet. Bei normaler Schrift stehen bei
332 dp zwei Rezeptkarten nebeneinander. Vorhandene Treffer bleiben beim
Nachladen sichtbar. Alle 39 Flutter-Tests bestanden, darunter die kompakte
Navigation, die Filtereingaben und ein Suchabruf mit verzögerter Antwort.
Die signierte ARM64-APK für Testbuild **26** liegt lokal unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.3.5-build26.apk`.
Paket-ID, Version, Architektur und Signatur wurden geprüft.
Der Android-35-Emulator zeigte bei rund 332 dp die sechs einzeiligen
Navigationsbeschriftungen, zwei Rezeptspalten und das Filterblatt von unten.
Bei 150 Prozent Systemschrift wechselte die Liste auf eine Spalte und die
Navigation auf Symbole. Der Kaltstart im x86-Emulator blieb langsam.

Version `1.3.6` ordnet offene Zutaten zuerst im Android-Einkaufswagen an,
macht die Zutatenzeile vollständig antippbar und baut lange Einkaufslisten
schrittweise beim Scrollen auf. Im Vorrat sind die Kategorieaktionen gebündelt
und Zutaten durch Antippen bearbeitbar.
Alle 40 Flutter-Tests bestanden. Ein Test baut eine Einkaufsliste mit
100 Einträgen auf und prüft das Nachladen beim Scrollen. Die signierte ARM64-APK
für Testbuild **27** liegt unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.3.6-build27.apk`.
Paket-ID, Version, Architektur und Signatur wurden geprüft.
Im isolierten Android-35-Emulator waren bei 332 dp die Zutaten vor den
Rezeptkarten sichtbar. Das Eingabeblatt samt Aktion blieb über geöffneter
Bildschirmtastatur sichtbar. Android meldete Zeitlimits beim Start und bei
der Zurück-Taste. Der Vorratsablauf wurde im Flutter-Widgettest geprüft.

Version `1.3.7` reserviert gleich hohe Titel- und Schwierigkeitsbereiche für
gleich breite Android-Rezeptkarten. Titel ab der dritten Zeile werden mit
Auslassungszeichen gekürzt. Der Layouttest prüft kurze und lange Titel sowie
unterschiedliche Bildbadges bei 150 Prozent Schriftgröße. Alle 41 Flutter-Tests
bestanden. Die signierte ARM64-APK für Testbuild **28** liegt unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.3.7-build28.apk`.
Paket-ID, Version, Architektur und Signatur wurden geprüft.

Version `1.3.8` entfernt die dauerhaft eingeblendeten Bedienhinweise zu
Wischgesten in der Android-Woche und Häkchen im Einkaufswagen. Alle 41
Flutter-Tests bestanden.

Version `1.4.0` überarbeitet Übersicht, Listen, Rezeptsammlung, Woche und
Einkaufswagen. Die Einkaufsliste hält während der Häkchenbestätigung ihre
Position. Zusatzartikel erhalten einen Warenbereich aus der Serverantwort.
Ein Aufwärtswisch erfordert 140 dp. Eine Kachel wird nach 250 ms markiert.
Alle 41 Flutter-Tests bestanden. Der Backendlauf meldete 128 erfolgreiche
und zwei übersprungene Tests. Die Android-Tests prüfen die stabile Position
beim Abhaken, das Sortierblatt und die Wischvorschau vor der Ausführung.
Die signierte ARM64-APK für Testbuild **30** liegt unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.4.0-build30.apk`.
Paket-ID, Version, Architektur und Signatur wurden geprüft.

Version `1.4.1` hebt aufklappbare Listenköpfe farblich ab und zeigt ihre
Rezeptkarten mit Vorschaubild in zwei Spalten. „Neue Liste“ steht über der Suche.
Das Bearbeiten-Symbol führt zur Verwaltung lokaler Listen.
Die Android-Grundfarben folgen im Hell- und Dunkelmodus der Web-App.
Alle 43 Flutter-Tests bestanden. Geprüft wurden unter anderem die Palette
in beiden Modi und zwei Rezeptkarten pro Zeile bei 332 dp.
Die signierte ARM64-APK für Testbuild **31** liegt unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.4.1-build31.apk`.
Paket-ID, Version, Architektur und Signatur wurden geprüft.

Version `1.5.0` umrandet Rezeptkarten in Listen. „Rezepte hinzufügen“ zeigt
die Karten mit einem Plus in der oberen rechten Bildecke. Wischen im Hauptinhalt
wechselt den Navigationsbereich und im Wochenkalender weiterhin den Tag.
Rezeptdetails zeigen kräftigere Vorratspunkte und bieten die Ablageaktion
für die aktuelle Berliner Kalenderwoche über „Heute kochen“ an.
Die statische Analyse und alle 45 Flutter-Tests bestanden.
Die signierte ARM64-APK für Testbuild **33** liegt unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.5.0-build33.apk`.
Paket-ID, Version, Architektur und Signatur wurden geprüft.

Version `1.5.1` führt beide Navigationsseiten beim Wischen mit. Der Widget-Test
prüft ihre Positionen während des Ziehens, das Zurückgleiten nach kurzer Geste,
den Wechsel beim Loslassen und die separate Tagesgeste in „Meine Woche“.
Die Rezeptansicht zeigt linksbündige Aktionsschaltflächen mit Symbolen. In der
Wochenablage stehen die Vorschaupillen in einer seitlich scrollbaren Reihe.
Die statische Analyse und alle 46 Flutter-Tests bestanden.
Die signierte ARM64-APK für Testbuild **34** liegt unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.5.1-build34.apk`.
Paket-ID, Version, Architektur und Signatur wurden lokal geprüft.

Version `1.5.2` hält die Position geladener Listen, Vorratskategorien und
Wocheninhalte nach einem Wischwechsel auch bei verzögerter Serverantwort.
Die Wochenablage zeigt kleine Karten mit dem Bild über dem Titel. Ein Wisch
nach unten entfernt den Eintrag und lässt sich bei Rezepten rückgängig
machen. Die drei Debug-Rezepte verwenden unterschiedliche mitgelieferte PNGs.
Die statische Analyse und alle 48 Flutter-Tests bestanden.
Die signierte ARM64-APK für Testbuild **35** liegt unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.5.2-build35.apk`.
Paket-ID, Version, Architektur, Signatur und die mitgelieferten PNGs wurden
lokal geprüft.

Version `1.5.3` verwendet einen horizontalen Flutter-`PageView` für die
Hauptnavigation. Wischen nutzt die Geschwindigkeits- und Einrastphysik von
Flutter. Tabtasten verwenden denselben `PageController`. Der Widget-Test prüft
auch die Wochentage und die Position während verzögerter Aktualisierung.
Die statische Analyse und alle 48 Flutter-Tests bestanden.
Die signierte ARM64-APK für Testbuild **36** liegt unter
`android-app/build/app/outputs/flutter-apk/Rezeptgarten-Test-1.5.3-build36.apk`.
Paket-ID, Version, Architektur und Signatur wurden lokal geprüft.

## Noch ausstehend

Telegram-Anmeldung und Kopplung, Android-Dateiauswahl und den In-App-Installer
mit isolierten Daten in der Android-Laufzeit prüfen. Die vollständige Abnahme
ist in `FLUTTER-PORTIERUNG.md` beschrieben.

## Aktueller technischer Stand

- Für Version **1.10.0** prüfen die Widgettests den Sprung mit „Heute“ auf
  Freitag, den 1. Januar 2027, aus der laufenden Woche und der Folgewoche.
  Im Telegram-Modus prüfen sie die sichtbare Position des heutigen Tageskopfs.
  Alle 62 Flutter-Tests und 130 Backendtests bestanden. Testbuild **49** ist
  auf LXC 103 veröffentlicht. HTTPS-Download und Update-Manifest stimmen
  mit der lokal signierten APK überein.
- Am 22. November 2026 wurde **1.9.6, Build 48** auf LXC 103 veröffentlicht.
  Die ARM64-Profil-APK hat dieselbe Signatur wie Build 17. HTTPS-Download,
  SHA-256 und Update-Manifest wurden mit der lokalen APK abgeglichen.
  Das Backend meldete über HTTPS Version 1.9.6. Alle 130 Backendtests
  bestanden auf LXC 103 mit isolierten Testdaten.
- Der pausierte Arbeitsstand (`1.1.1`, Service-Worker-Cache `v136`) ist in Commit
  `9723187` gesichert. Version `1.1.2`, Android-Testbuild **18**, wurde lokal
  gebaut und geprüft. Der Debug-Modus ist in `1.2.0` enthalten.
- Die virtuelle Testumgebung und die lokale Prüfliste liegen unter `.local/`.
  Für die Sichtprüfungen kam der isolierte x86_64-Emulator mit Android 35 zum
  Einsatz.
