import hashlib
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path


@unittest.skipUnless(os.name == 'posix', 'The publisher runs on Linux')
class AndroidPublishTests(unittest.TestCase):
    def setUp(self):
        script = Path(__file__).resolve().parents[1] / 'deploy/publish-android.py'
        spec = importlib.util.spec_from_file_location('android_publisher', script)
        self.publisher = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.publisher)
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = self.publisher.ROOT = Path(temporary.name)
        (self.root / '.incoming').mkdir()

    def publish(self, build, data, checksum=None, channel='test'):
        staging_name = 'apk.ABC012def3'
        (self.root / '.incoming' / staging_name).write_bytes(data)
        return self.publisher.publish(
            channel, staging_name, '0.6.2', build, len(data),
            checksum or hashlib.sha256(data).hexdigest(),
        )

    def test_invalid_upload_and_old_build_leave_current_download_available(self):
        filename = self.publish(2, b'current')
        directory = self.root / 'test'
        original_page = (directory / 'index.html').read_bytes()

        with self.assertRaisesRegex(ValueError, 'checksum'):
            self.publish(3, b'corrupt', checksum='0' * 64)
        with self.assertRaisesRegex(ValueError, 'versionCode'):
            self.publish(1, b'old')

        self.assertEqual((directory / 'index.html').read_bytes(), original_page)
        self.assertEqual((directory / filename).read_bytes(), b'current')
        self.assertEqual(list((self.root / '.incoming').iterdir()), [])

    def test_channels_publish_independently_and_keep_versioned_files(self):
        first = self.publish(1, b'first')
        second = self.publish(2, b'second')
        self.assertEqual(self.publish(2, b'second'), second)
        release = self.publish(1, b'release', channel='release')
        self.assertEqual((self.root / 'test' / first).read_bytes(), b'first')
        self.assertIn(second, (self.root / 'test' / 'index.html').read_text(encoding='utf-8'))
        self.assertIn(release, (self.root / 'release' / 'index.html').read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
