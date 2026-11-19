# Android-App: Stand der Fehlerprüfung

Stand: 19. November 2026. Die umfassende Prüfung ist **pausiert und noch nicht
abgeschlossen**. Dieses Dokument beschreibt den Arbeitsstand im lokalen
Arbeitsverzeichnis; es ist kein Bericht über eine bereits veröffentlichte Version.

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

Die gezielten Tests wurden während der Arbeit mehrfach für die jeweils betroffenen
Dateien ausgeführt. **Die vollständige Flutter-Testreihe und die Flutter-Analyse
wurden nach den letzten Änderungen noch nicht gemeinsam erneut ausgeführt.** Die
einzelnen grünen Tests belegen nicht die vollständige Funktionsprüfung.

## Noch ausstehend

1. Die Prüfung aller Android-Funktionen anhand von `FLUTTER-PORTIERUNG.md` und
   `AGENTS.md` fortsetzen und ausdrücklich noch nicht geprüfte Abläufe und
   Fehlerfälle erfassen. Das betrifft insbesondere Listen, Suche und Filter,
   Notizen und Konflikte, Wochenplanung und Rückgängig, Einkaufswagen und
   ungeklärte Übertragungen, Vorrat, Konto und Export, Telegram-Anmeldung und
   Kopplung sowie den nativen Update- und Installationsablauf.
2. Die neuen und geänderten Tests gemeinsam ausführen, Flutter-Analyse und die
   vollständige Flutter-Testreihe durchführen und etwaige Fehler beheben. Wo
   gemeinsame Server-APIs betroffen sind, passende isolierte Backendtests
   ergänzen oder ausführen.
3. Eine isolierte Android-Laufzeit prüfen, soweit verfügbar. Der Nutzer möchte
   **kein physisches Android-Gerät anschließen**. Eine virtuelle Testumgebung
   wurde vorbereitet; der Download ihrer Abhängigkeiten wurde beim Pausieren
   abgebrochen und ist nicht vollständig. Ohne geeigneten Emulator bleiben
   insbesondere Android-Berechtigungen, Telegram/TDLib, Dateiauswahl und der
   tatsächliche Android-Installer nur eingeschränkt geprüft. Keine persönlichen
   Konten oder produktiven Daten als Testdaten verwenden.
4. Änderungen und Ergebnisse vollständig überprüfen; `AGENTS.md`, die betroffenen
   Projektskills und gegebenenfalls die Portierungsdokumentation aktualisieren.
   Erst danach den Android-Testbuild mit steigender Buildnummer bauen, den
   bestehenden Serverstand und Testkanal bereitstellen und die Downloads prüfen.
5. Nach erfolgreicher Prüfung und Bereitstellung alle weiteren Änderungen
   committen und ohne Force-Push nach `origin/main` übertragen.

## Aktueller technischer Stand

- Zuletzt veröffentlichter Android-Testbuild: **1.1.0, Build 17**.
- Der pausierte Arbeitsstand wird auf ausdrücklichen Wunsch in Git gesichert;
  er ist **nicht bereitgestellt**. `app/version.py` enthält für diesen Stand
  bereits `1.1.1` und die Service-Worker-Cacheversion `v136`; die bereitgestellte
  Version bleibt davon unberührt.
- `android-app/test/api_test.dart` enthält die neuen isolierten API-Tests.
- Die teilweise vorbereitete virtuelle Testumgebung und die detaillierte lokale
  Prüfliste liegen unter `.local/` und sind nicht Bestandteil von Git. Der laufende
  Download wurde gestoppt; ein erfolgreicher Abschluss darf nicht angenommen werden.
- Die frühere Testdatei `FLUTTER-PORTIERUNG.md` enthält historische und noch offene
  Abnahmepunkte; sie ist bei der Fortsetzung gegen die aktuellen Anforderungen
  und den tatsächlichen Stand abzugleichen.
