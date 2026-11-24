# Rezeptgarten

Rezeptgarten verwaltet deine Cookidoo-Sammlung auf dem eigenen Server. In der Web-App und der Android-App **Rezeptmix** kannst du Rezepte nach Titel oder Zutaten suchen, Mahlzeiten für die Woche planen und den Einkaufswagen mit deinem Vorrat abgleichen.

## Im Heimnetz starten

1. Lade das [öffentliche CA-Zertifikat des Rezeptgarten-Servers](http://192.168.184.30/zertifikat) und richte es auf deinem Gerät als vertrauenswürdig ein.
2. Öffne [Rezeptgarten](https://192.168.184.30) und verbinde in den Einstellungen dein Cookidoo-Konto. Wähle dabei das Land deines Kontos.
3. Für die Web-App auf dem Startbildschirm wähle in Chrome „App installieren“ oder „Zum Startbildschirm hinzufügen“. Die native Android-App erhältst du als [APK vom Server](https://192.168.184.30/android/).

Die Web-App ist im Heimnetz ohne eigenes Passwort zugänglich. Wer den Server erreicht, kann die Sammlung lesen und ändern. Die Android-App kann nach einmaliger Kopplung im Heimnetz auch unterwegs über Telegram zugreifen.

## Im Repository

| Bereich | Inhalt |
| --- | --- |
| [app/](app/) | Python-Backend, Cookidoo-Anbindung und SQLite. Die Web-App liegt unter [app/static/](app/static/). |
| [android-app/](android-app/) | Native Flutter-App, Widgettests und Android-Build. |
| [tests/](tests/) | Backendtests und Browserprüfung. |
| [scripts/](scripts/) | Werkzeuge für Deployment, APK-Veröffentlichung, Icons und Telegram. |
| [deploy/](deploy/) | Serverinstallation, Caddy-Konfiguration und systemd-Dienste. |
| [docs/](docs/) | [Serverbetrieb und Datenhaltung](docs/betrieb.md), [Android-Portierungsplan](docs/android/FLUTTER-PORTIERUNG.md) und [Android-Prüfstand](docs/android/ANDROID-PRUEFSTAND.md). |

## Lokal entwickeln

Führe diese Befehle mit Python 3.12 oder neuer in einer aktivierten virtuellen Umgebung im Projektstamm aus.

```sh
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
python -m uvicorn app.asgi:app --host 127.0.0.1 --port 8000
```

Die lokale Instanz ist unter [localhost:8000](http://127.0.0.1:8000) erreichbar und verwendet standardmäßig `./data/`. Nach Änderungen am App-Symbol erzeugt `python scripts/generate_icons.py` die benötigten Bildgrößen.

Fachliche Konventionen stehen in den [Projekthinweisen](AGENTS.md). Änderungen an den Apps dokumentieren der [Web-Änderungsverlauf](app/static/changelog.html) und der [Android-Änderungsverlauf](android-app/assets/changelog.txt).
