"""Real browser QA against an isolated fixture database over an SSH tunnel."""
import json
import base64
import hashlib
import socket
import ssl
import tempfile
import subprocess
import time
from pathlib import Path

from playwright.sync_api import sync_playwright, expect

root = Path(__file__).resolve().parents[1]
access = root / '.local/proxmox/access'
output = root / 'test-results'
output.mkdir(exist_ok=True)
tunnel = subprocess.Popen(['ssh', '-N', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes', '-o', 'ConnectTimeout=12', '-o', 'StrictHostKeyChecking=yes', '-o', f'UserKnownHostsFile={access.as_posix()}/known_hosts', '-i', f'{access.as_posix()}/id_ed25519', '-L', '127.0.0.1:8901:127.0.0.1:8901', 'root@192.168.184.30'], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
errors = []
profile = tempfile.TemporaryDirectory(prefix='rezeptgarten-browser-', ignore_cleanup_errors=True)
try:
    time.sleep(1)
    if tunnel.poll() is not None:
        raise RuntimeError(tunnel.stderr.read().decode())
    tls = ssl.create_default_context(cafile=str(root / 'certificates/Rezeptgarten-CA.crt'))
    with socket.create_connection(('192.168.184.30', 443), timeout=12) as raw:
        with tls.wrap_socket(raw, server_hostname='192.168.184.30') as secured:
            certificate = secured.getpeercert(binary_form=True)
    openssl = 'C:/msys64/ucrt64/bin/openssl.exe'
    public_certificate_path = output / 'server-public.der'
    public_certificate_path.write_bytes(certificate)
    public_key = subprocess.run([openssl, 'x509', '-inform', 'DER', '-in', str(public_certificate_path), '-pubkey', '-noout'], capture_output=True, check=True).stdout
    public_key_path = output / 'server-public-key.pem'
    public_key_path.write_bytes(public_key)
    spki = subprocess.run([openssl, 'pkey', '-pubin', '-in', str(public_key_path), '-outform', 'DER'], capture_output=True, check=True).stdout
    fingerprint = base64.b64encode(hashlib.sha256(spki).digest()).decode()
    with sync_playwright() as playwright:
        context = playwright.chromium.launch_persistent_context(user_data_dir=profile.name, executable_path='C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', headless=True, args=['--ignore-certificate-errors-spki-list=' + fingerprint], viewport={'width':1440,'height':1000}, reduced_motion='reduce')
        page = context.new_page()
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.goto('https://192.168.184.30', wait_until='networkidle')
        expect(page.locator('.featured-copy h1')).to_be_visible()
        page.screenshot(path=str(output / 'first-use-desktop.png'), full_page=True)
        page.evaluate('() => Promise.race([navigator.serviceWorker.ready, new Promise((_, reject) => setTimeout(() => reject(new Error("Service worker timeout")), 10000))])')
        cdp = context.new_cdp_session(page)
        manifest = cdp.send('Page.getAppManifest')
        assert not manifest.get('errors'), manifest
        installability = cdp.send('Page.getInstallabilityErrors')
        print('Production PWA installability:', json.dumps(installability))
        assert not installability.get('installabilityErrors'), installability

        page.goto('http://127.0.0.1:8901', wait_until='networkidle')
        expect(page.locator('.featured-copy h1')).to_be_visible()
        expect(page.locator('.collection-card')).to_have_count(3)
        expect(page.locator('.recipe-card')).to_have_count(2)
        page.wait_for_function('Array.from(document.querySelectorAll("img[data-recipe-image]")).every(image => image.complete && image.naturalWidth > 0)')
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), 'Desktop overflow'
        page.screenshot(path=str(output / 'desktop-library.png'), full_page=True)
        page.locator('.desktop-nav [data-nav="listen"]').click()
        expect(page.locator('.collection-card h3').first).to_have_text('<Lieblingsgerichte>')
        page.locator('.collection-card').first.click()
        expect(page.locator('#recipe-grid .recipe-card')).to_have_count(2)
        page.locator('#recipe-grid .recipe-card').first.click()
        expect(page.locator('#recipe-dialog')).to_be_visible()
        expect(page.locator('#recipe-title')).to_have_text('Käse-Spätzle')
        expect(page.locator('.detail-lists a')).to_have_count(2)
        expect(page.locator('#recipe-content a[target="_blank"]')).to_have_attribute('href', 'https://cookidoo.de/recipes/recipe/de-DE/r1')
        page.screenshot(path=str(output / 'desktop-recipe.png'))
        page.locator('#recipe-dialog .close-dialog').click()
        page.locator('#search').fill('KÄSE')
        expect(page.locator('#recipe-grid .recipe-card')).to_have_count(1)
        page.locator('#search').fill('nicht-vorhandenes-rezept')
        expect(page.locator('#recipe-empty')).to_contain_text('Noch kein Treffer.')
        page.locator('#search').fill('')
        expect(page.locator('#recipe-grid .recipe-card')).to_have_count(2)
        page.locator('#sort').select_option('time')
        expect(page.locator('#recipe-grid .recipe-card h3').first).to_have_text('Suppe mit 50% Gemüse')

        page.set_viewport_size({'width':390,'height':844})
        page.goto('http://127.0.0.1:8901/#uebersicht', wait_until='networkidle')
        expect(page.locator('.mobile-nav')).to_be_visible()
        expect(page.locator('.featured-copy h1')).to_be_visible()
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), 'Mobile overflow'
        page.screenshot(path=str(output / 'mobile-library.png'), full_page=True)
        page.locator('.mobile-nav [data-nav="listen"]').click()
        page.locator('.collection-card').last.click()
        expect(page.locator('#recipe-empty')).to_contain_text('Hier ist noch Platz')
        page.locator('.mobile-nav [data-nav="einstellungen"]').click()
        expect(page.locator('.settings-card')).to_have_count(5)
        page.locator('#sync-hours').select_option('24')
        expect(page.locator('#toast')).to_contain_text('gespeichert')
        status = page.request.get('http://127.0.0.1:8901/api/status').json()
        assert status['sync_hours'] == 24, status
        page.locator('[data-action="install-help"]').click()
        expect(page.locator('#install-dialog')).to_be_visible()
        expect(page.locator('#certificate-link')).to_be_visible()
        page.locator('#install-dialog .close-dialog').click()
        page.screenshot(path=str(output / 'mobile-settings.png'), full_page=True)
        page.evaluate('() => Promise.race([navigator.serviceWorker.ready, new Promise((_, reject) => setTimeout(() => reject(new Error("Service worker timeout")), 10000))])')
        context.set_offline(True)
        page.reload(wait_until='domcontentloaded')
        expect(page.locator('#offline-banner')).to_be_visible()
        expect(page.locator('#content')).to_contain_text('nicht erreichbar')
        assert not errors, errors
        print('Desktop/mobile browser checks passed; no uncaught JavaScript errors.')
        context.close()
finally:
    tunnel.terminate()
    try:
        tunnel.wait(timeout=5)
    except subprocess.TimeoutExpired:
        tunnel.kill()
    profile.cleanup()
