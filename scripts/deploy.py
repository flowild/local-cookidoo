"""SSH deployment to the dedicated LXC. No Proxmox API token is used."""
import io
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRS = ('app', 'tests', 'scripts', 'deploy')
SOURCE_SUFFIXES = {'.py', '.js', '.css', '.html', '.svg', '.png', '.webmanifest', '.service', '.sh'}
SOURCE_FILES = ('requirements.txt', 'THIRD-PARTY-NOTICES.txt', 'README.md', 'deploy/Caddyfile')


def build_archive(root):
    """Package only known source files, never local configuration or private data."""
    paths = {root / name for name in SOURCE_FILES if (root / name).is_file() and not (root / name).is_symlink()}
    for directory in SOURCE_DIRS:
        base = root / directory
        for path in base.rglob('*'):
            if not path.is_file() or path.is_symlink() or path.suffix not in SOURCE_SUFFIXES:
                continue
            if any(part.startswith('.') or part == '__pycache__' for part in path.relative_to(root).parts):
                continue
            paths.add(path)

    def source_permissions(info):
        info.mode = 0o644
        info.uid = info.gid = 0
        info.uname = info.gname = 'root'
        return info

    archive = io.BytesIO()
    with tarfile.open(fileobj=archive, mode='w:gz') as tar:
        for path in sorted(paths):
            tar.add(path, arcname=path.relative_to(root).as_posix(), recursive=False, filter=source_permissions)
    return archive.getvalue()


def main():
    access = ROOT / '.local/proxmox/access'
    ssh = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=12', '-o', 'IdentitiesOnly=yes', '-o',
           'StrictHostKeyChecking=yes', '-o', f'UserKnownHostsFile={access.as_posix()}/known_hosts',
           '-i', f'{access.as_posix()}/id_ed25519', 'root@192.168.184.30']
    subprocess.run([*ssh, 'install -d -m 0755 /opt/cookidoo-manager/source && tar -xzf - -C /opt/cookidoo-manager/source'],
                   input=build_archive(ROOT), check=True)
    commands = '''set -eu
cd /opt/cookidoo-manager/source
/opt/cookidoo-manager/.venv/bin/python scripts/generate_icons.py
/opt/cookidoo-manager/.venv/bin/python -m compileall -q app
/opt/cookidoo-manager/.venv/bin/python -m unittest discover -s tests -v
'''
    if '--install' in sys.argv:
        commands += 'sh deploy/install.sh\n'
    subprocess.run([*ssh, 'sh -s'], input=commands.encode(), check=True)


if __name__ == '__main__':
    main()
