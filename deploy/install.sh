#!/bin/sh
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends caddy
cd /opt/cookidoo-manager/source
/opt/cookidoo-manager/.venv/bin/pip install -r requirements.txt
/opt/cookidoo-manager/.venv/bin/python scripts/generate_icons.py
find /opt/cookidoo-manager/source -type d -exec chmod 755 {} +
find /opt/cookidoo-manager/source -type f -exec chmod 644 {} +
install -d -o cookidoo -g cookidoo -m 0750 /var/lib/cookidoo-manager
install -m 0644 deploy/rezeptgarten.service /etc/systemd/system/rezeptgarten.service
install -m 0644 deploy/Caddyfile /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl daemon-reload
systemctl enable rezeptgarten caddy
systemctl restart rezeptgarten
systemctl restart caddy
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if curl --fail --silent http://127.0.0.1:8000/api/health >/dev/null && test -f /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt; then
        break
    fi
    sleep 1
done
install -d -o root -g root -m 0755 /var/lib/rezeptgarten-ca
install -m 0644 /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt /var/lib/rezeptgarten-ca/Rezeptgarten-CA.crt
curl --fail --silent --cacert /var/lib/rezeptgarten-ca/Rezeptgarten-CA.crt https://192.168.184.30/api/health
systemctl is-active rezeptgarten caddy
