---
name: rezeptgarten-android
description: Entwickle, prüfe und veröffentliche die native Rezeptgarten-App in android-app mit Flutter, Android-Installer und APK-Downloads auf LXC 103.
---

# Rezeptgarten für Android

- Nutze [FLUTTER-PORTIERUNG.md](../../../FLUTTER-PORTIERUNG.md) für Umfang,
  Design und offene Abnahme. Die mobile PWA ist die Vorlage für Farben,
  Abstände, Karten, Gesten und fachliche Abläufe. Setze die Oberfläche mit
  Flutter-Widgets um und prüfe sie mit denselben isolierten Testdaten wie die PWA.
- Beide Clients nutzen die gemeinsamen Rezeptgarten-APIs, Cookidoo-Konten
  und Daten im bestehenden LXC. Der Android-API-Client vertraut der gebündelten
  Rezeptgarten-CA und setzt bei Schreibanfragen den passenden Origin. Beim
  Start und beim Einkaufswagen gilt die 2,5-Sekunden-Frist für den
  Erreichbarkeitscheck. Schreibvorgänge folgen der gemeinsamen
  Bestätigungs- und Konfliktbehandlung.
- Die APK enthält weder Bot-zu-Bot-Kommunikation noch Gemini oder eine
  Google-API-Schlüsselverwaltung. Die browserseitigen Integrationen gehören
  zur Web-App. Änderungen an den gemeinsamen APIs mit dem Betriebs- und
  gegebenenfalls dem Cookidoo-Skill abgleichen.
- Android erkennt `ThomasWlan` mit Standortberechtigung und prüft den Server
  über die gebündelte CA. Außerhalb des Heimnetzes sowie bei nicht erreichbarem
  Server stehen Woche und Einkaufswagen nach Telegram-Benutzeranmeldung und
  bestätigter Kopplung lesend bereit. Der Einkaufswagen speichert Häkchen
  geräte- und kopplungsbezogen. TDLib verwendet die eingegebene eigene Telegram-
  API-ID und den API-Hash. Der Android-Keystore schützt Zugangsdaten und
  Geräteschlüssel, die TDLib-Sitzung liegt im Backup-ausgeschlossenen Bereich.
  Keine Zugangsdaten, Sitzungen oder Nachrichten in Git und Logs aufnehmen.
  Bei einer späteren Umstellung des Android-Ziel-SDK auf 37 oder höher die
  Laufzeitberechtigung `ACCESS_LOCAL_NETWORK` ergänzen und prüfen.
- Build und Veröffentlichung aus der Projektwurzel mit
  `scripts/Android-APK-veroeffentlichen.ps1`. Der WSL-Build prüft Flutter,
  führt die Widgettests aus und baut ARM64. Verwende eine steigende
  Buildnummer je Kanal und eine stabile Signatur. Test-App und Release
  haben unterschiedliche Paket-IDs und Downloadpfade. Mit `-Upload` prüft
  das Skript den HTTPS-Download und sein `latest.json` auf LXC 103.
- Die manuelle Updateprüfung in den Einstellungen vergleicht den installierten
  `versionCode` mit `latest.json` des eigenen Kanals. Der separate Download
  prüft die APK vor der Übergabe an den Android-Installer. Prüfe bei
  Änderungen den tatsächlich veröffentlichten Kanal und auf einem Gerät
  den Ablauf über Download, Quellenfreigabe und Installationsbestätigung.
