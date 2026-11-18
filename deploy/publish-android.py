"""Verify and publish a staged APK inside the Rezeptgarten container."""

import fcntl
import hashlib
import html
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path('/var/lib/rezeptgarten-downloads')


def publish(channel, staging_name, version, build_number, size, sha256):
    if channel not in ('test', 'release'):
        raise ValueError('Invalid channel')
    if not re.fullmatch(r'apk\.[A-Za-z0-9]{10}', staging_name):
        raise ValueError('Invalid staging file')
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
        raise ValueError('Invalid version')
    if not re.fullmatch(r'[a-f0-9]{64}', sha256) or build_number <= 0 or size <= 0:
        raise ValueError('Invalid APK metadata')

    staged = ROOT / '.incoming' / staging_name
    directory = ROOT / ('test' if channel == 'test' else 'release')
    directory.mkdir(mode=0o755, exist_ok=True)
    filename = f'rezeptgarten-{channel}-{version}-{build_number}-{sha256[:12]}.apk'
    target = directory / filename
    with (ROOT / '.publish.lock').open('ab') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with staged.open('rb') as incoming:
                if os.fstat(incoming.fileno()).st_size != size or hashlib.file_digest(incoming, 'sha256').hexdigest() != sha256:
                    raise ValueError('APK checksum or file size did not match')
            current = directory / 'index.html'
            manifest = {'version': version, 'versionCode': build_number, 'file': filename, 'size': size, 'sha256': sha256}
            if current.exists():
                match = re.search(r'<!-- ([^\n]+) -->', current.read_text(encoding='utf-8'))
                if not match:
                    raise ValueError('Current download page has no version record')
                previous = json.loads(match.group(1))
                if previous == manifest:
                    return filename
                if build_number <= previous['versionCode']:
                    raise ValueError('APK versionCode must increase')
            staged.chmod(0o644)
            os.replace(staged, target)
            title = 'Rezeptgarten Android-Testversion' if channel == 'test' else 'Rezeptgarten für Android'
            page = f'''<!doctype html>
<html lang="de">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title></head>
<body><main><h1>{title}</h1>
<p>Version {html.escape(version)} · Build {build_number} · {size / 1024**2:.1f} MiB</p>
<p><a href="{html.escape(filename)}" download>APK herunterladen</a></p>
</main></body></html>
<!-- {json.dumps(manifest)} -->
'''
            next_page = ROOT / '.incoming' / f'{staging_name}.html'
            try:
                next_page.write_text(page, encoding='utf-8')
                next_page.chmod(0o644)
                os.replace(next_page, current)
            finally:
                next_page.unlink(missing_ok=True)
            return filename
        finally:
            staged.unlink(missing_ok=True)


if __name__ == '__main__':
    channel, staging, version, build, size, checksum = sys.argv[1:]
    print(publish(channel, staging, version, int(build), int(size), checksum))
