# Rezeptgarten

Private, responsive Cookidoo recipe library for the Proxmox LXC `cookidoo-manager` (103).

The first version reads personal recipe lists and saved official collections into SQLite, deduplicates their recipes, downloads and normalizes real recipe images, and supports search, list browsing, recipe details and JSON export. It includes automatic synchronization, local password authentication and an installable PWA shell. Ingredients returned by Cookidoo are retained for a later ingredient view; this version shows recipe metadata and links to Cookidoo.

## Installed service

- App: `https://192.168.184.30`
- Public local CA download: `http://192.168.184.30/zertifikat`
- Runtime: `/opt/cookidoo-manager/.venv`
- Source: `/opt/cookidoo-manager/source`
- Database, encrypted OAuth tokens, encryption key, images and seven rotating database snapshots: `/var/lib/cookidoo-manager`
- Services: `rezeptgarten` (user `cookidoo`, loopback port 8000), `caddy` (LAN IPv4 ports 80/443).

The address currently comes from DHCP. Reserve `192.168.184.30` for MAC `BC:24:11:96:6F:AA` in the router before relying on a stable bookmark or PWA installation. Changing the address requires adjusting `deploy/Caddyfile` and the PWA certificate-download link.

## First use

1. Trust the **public** CA certificate from `certificates/Rezeptgarten-CA.crt` on each device. Only install this certificate for your own server. No CA private key is copied to the workspace.
2. Open the app over HTTPS. The first setup requires the single-use code stored in `/var/lib/cookidoo-manager/setup-code`. A prepared local setup link is provided separately after deployment.
3. Choose an app password of at least eight characters.
4. Connect a Cookidoo account in the app, selecting the correct account country (Germany, Austria or Switzerland). The Cookidoo password is used for login and discarded; rotated OAuth tokens are encrypted on disk. Some recipe details require an active subscription.
5. On Android Chrome, use the browser menu's **Install app** / **Add to Home screen**. The local CA must be trusted without certificate warnings. The service worker caches only the public shell, never private recipe API responses.

Desktop Windows: import the public CA into the current user's **Trusted Root Certification Authorities** through the certificate import wizard. Android: import it as a **CA certificate** in the device's certificate/security settings; wording varies by device. The app is reachable while the device can reach the home LAN. Offline reloads show a connection message rather than a cached personal library.

## Development and checks

Python 3.12+ is required. Install `requirements.txt`, run `python scripts/generate_icons.py`, and run `python -m unittest discover -s tests -v`.

For local development only, disable secure-only cookies on localhost and launch the app instance:

```sh
REZEPTGARTEN_SECURE_COOKIE=0 python -m uvicorn app.asgi:app --host 127.0.0.1 --port 8000
```

Production uses secure HttpOnly cookies and same-origin checks for mutations. Tokens and passwords are excluded from logs and JSON export. The password hash and session hashes are in the database, so database snapshots must remain protected. Back up the whole data directory, including `vault.key` and `cookidoo.enc`, for account restoration; keep those backups private.

Deploy from the workspace with `python scripts/deploy.py --install`, using the SSH key from `.local/proxmox/access/id_ed25519`. This script does not need a Proxmox API token. The service configuration is intended for this dedicated LXC, not a shared server.

## Synchronization behavior and limits

The app fetches every page of custom and managed collections, reads details once per unique recipe, and caches WebP images at up to 960 pixels. Metadata with an existing image is reused for fourteen days. A complete list snapshot is committed in one transaction; list-read/authentication failures preserve the previous library. Individual unavailable recipe details retain list stubs and previously cached fields. Images are fetched only from HTTPS `tmecosys.com` asset hosts, without Cookidoo authorization headers. Unreferenced image files remain cached for now.

This version reads Cookidoo data and does not write changes back to Cookidoo. A bidirectional editing interface is a later step. Personal recipe lists, saved official collections and the separate Merkliste/bookmarks endpoint are included. The bookmark adapter uses the private request helper of the pinned library, including its token-refresh handling, and reads every bookmark page.

The integration pins `cookidoo-api==0.19.0` and uses its token refresh/pagination APIs directly. It does not import the older `cookidoo-migrate` integration, whose cookie/session imports do not match this release. Cookidoo's unofficial endpoints can change. Real account authentication cannot be verified without a user's Cookidoo account; automated tests use deterministic simulated API responses.

## Local workspace

The project is rooted at `D:\Github\local-cookidoo` in its own existing Git repository.
Local provisioning records and private SSH access files are in `.local/proxmox/`;
the relocated browser QA environment is `.qa-venv/`. Both are ignored by Git and
excluded from deployment archives. Public CA files are in `certificates/`.
See `AGENTS.md` for current project context and the SSH workflow.
