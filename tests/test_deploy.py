import io
import tarfile
import tempfile
import unittest
from pathlib import Path

from scripts.deploy import build_archive


class DeploymentArchiveTests(unittest.TestCase):
    def test_archive_only_contains_allowed_source_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('app/main.py', 'app/static/app.js', 'app/static/icon.png', 'tests/test_app.py',
                         'deploy/Caddyfile', 'requirements.txt', '.local/private.py', '.codex/settings.json',
                         'data/accounts.py', 'app/.local/private.py', 'app/secrets.json', 'app/__pycache__/cached.py'):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('example', encoding='utf-8')
            with tarfile.open(fileobj=io.BytesIO(build_archive(root)), mode='r:gz') as archive:
                self.assertEqual(set(archive.getnames()), {'app/main.py', 'app/static/app.js', 'app/static/icon.png',
                                                           'tests/test_app.py', 'deploy/Caddyfile', 'requirements.txt'})
                self.assertTrue(all(item.mode == 0o644 for item in archive.getmembers()))


if __name__ == '__main__':
    unittest.main()
