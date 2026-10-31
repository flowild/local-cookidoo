"""SSH deployment to the dedicated LXC. No Proxmox API token is used."""
import io
import subprocess
import sys
import tarfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
access = root / '.local/proxmox/access'
ssh = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=12', '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=yes', '-o', f'UserKnownHostsFile={access.as_posix()}/known_hosts', '-i', f'{access.as_posix()}/id_ed25519', 'root@192.168.184.30']
archive = io.BytesIO()
with tarfile.open(fileobj=archive, mode='w:gz') as tar:
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if not path.is_file() or any(part in {'.local', '.venv', '.qa-venv', 'data', '__pycache__', '.git', '.pytest_cache', 'certificates', 'test-results'} for part in relative.parts):
            continue
        def source_permissions(info):
            info.mode = 0o644
            info.uid = info.gid = 0
            info.uname = info.gname = 'root'
            return info
        tar.add(path, arcname=relative.as_posix(), recursive=False, filter=source_permissions)
subprocess.run([*ssh, 'install -d -m 0755 /opt/cookidoo-manager/source && tar -xzf - -C /opt/cookidoo-manager/source'], input=archive.getvalue(), check=True)
commands = '''set -eu
cd /opt/cookidoo-manager/source
/opt/cookidoo-manager/.venv/bin/python scripts/generate_icons.py
/opt/cookidoo-manager/.venv/bin/python -m compileall -q app
/opt/cookidoo-manager/.venv/bin/python -m unittest discover -s tests -v
'''
if '--install' in sys.argv:
    commands += 'sh deploy/install.sh\n'
subprocess.run([*ssh, 'sh -s'], input=commands.encode(), check=True)
