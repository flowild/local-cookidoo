import base64
import json
import os
import tempfile
import time
import unittest
import zlib

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from fastapi.testclient import TestClient

from app.main import create_app
from app.security import Vault
from scripts.telegram_bridge import ApiRequests


class TelegramApiTests(unittest.TestCase):
    def setUp(self):
        directory = self.enterContext(tempfile.TemporaryDirectory())
        self.app = create_app(directory)
        self.database = self.app.state.database
        self.database.set('account', {'email': 'recipe@example.invalid', 'region': 'de'})
        self.key = os.urandom(32)
        self.cipher = AESGCM(self.key)
        Vault(directory, 'telegram-server-bot.enc').write({
            'android_user_pair': {'client_id': 333, 'cart_owner': self.app.state.sync.cart_owner(),
                                  'cart_key': base64.b64encode(self.key).decode()},
        })
        self.client = self.enterContext(TestClient(self.app, client=('127.0.0.1', 1234)))

    def envelope(self, method, path, *, body=None, nonce=None, sent=None, **options):
        nonce = nonce or os.urandom(16).hex()
        iv = os.urandom(12)
        payload = {'method': method, 'path': path, 'body': body,
                   'sent': int(time.time()) if sent is None else sent, **options}
        encrypted = self.cipher.encrypt(iv, zlib.compress(json.dumps(payload).encode()),
                                        ('request:' + nonce).encode())
        return {'client_id': 333, 'nonce': nonce, 'data': base64.b64encode(iv + encrypted).decode()}

    def post(self, envelope, client=None):
        response = (client or self.client).post('/api/telegram-api', json=envelope,
                                               headers={'Origin': 'http://testserver'})
        if response.status_code != 200:
            return {'status': response.status_code}
        packed = base64.b64decode(response.json()['data'], validate=True)
        compressed = self.cipher.decrypt(packed[:12], packed[12:], ('response:' + envelope['nonce']).encode())
        return json.loads(zlib.decompress(compressed))

    def test_recipe_revision_avoids_returning_unchanged_text(self):
        original = self.post(self.envelope('GET', '/api/recipes?limit=8'))
        self.assertEqual(original['status'], 200)
        self.assertEqual(original['body']['items'], [])
        again = self.post(self.envelope('GET', '/api/recipes?limit=8', revision=original['revision']))
        self.assertEqual(again['status'], 304)
        self.assertIsNone(again['body'])

    def test_write_is_shared_and_a_duplicate_is_not_reapplied(self):
        request = self.envelope('POST', '/api/local-collections', body={'name': 'Testliste'})
        self.assertEqual(self.post(request)['status'], 200)
        self.assertEqual(self.post(request)['status'], 409)
        lists = self.client.get('/api/collections').json()['items']
        self.assertEqual([item['name'] for item in lists], ['Testliste'])

    def test_telegram_uncheck_yields_to_a_newer_web_check(self):
        headers = {'Origin': 'http://testserver'}
        self.client.post('/api/cart/items', json={'name': 'Testartikel'}, headers=headers)
        item = self.client.get('/api/cart').json()['items'][0]
        path = f"/api/cart/{item['id']}/owned"
        checked = self.client.put(path, json={'owned': True, 'owned_revision': 0}, headers=headers).json()
        delayed = self.post(self.envelope('PUT', path, body={'owned': False, 'owned_revision': 0}))
        self.assertEqual(delayed['status'], 200)
        self.assertEqual(delayed['body'], checked)

    def test_requires_loopback_live_pair_active_account_and_allowed_route(self):
        request = self.envelope('GET', '/api/pantry')
        external = TestClient(self.app, client=('192.0.2.1', 1234))
        self.assertEqual(self.post(request, external)['status'], 403)
        self.assertEqual(self.post({**request, 'client_id': 444})['status'], 403)
        self.assertEqual(self.post({**request, 'nonce': 'a' * 32})['status'], 403)
        self.assertEqual(self.post(self.envelope('GET', '/api/pantry', sent=0))['status'], 403)
        for method, path in [('GET', '/api/export'), ('POST', '/api/connect'),
                             ('GET', '/api/recipes/%2e%2e/export'), ('GET', '//other/api/pantry'),
                             ('GET', '/api/images/' + 'a' * 40 + '.webp')]:
            with self.subTest(path=path):
                self.assertEqual(self.post(self.envelope(method, path))['status'], 403)
        self.database.set('account', {'email': 'other@example.invalid', 'region': 'de'})
        rejected = self.post(request)
        self.assertEqual(rejected['status'], 409)
        self.assertIsNone(rejected['owner'])

    def test_bridge_assembles_only_matching_fresh_private_messages(self):
        requests = ApiRequests()
        nonce = 'a' * 32
        message = {'from': {'id': 333, 'is_bot': False}, 'chat': {'id': 333, 'type': 'private'}, 'date': 1000}
        def update(index, part):
            return {'message': {**message, 'text': f'rezeptgarten-api {nonce} {index}/2 {part}'}}

        self.assertIsNone(requests.accept(update(2, 'Zg=='), 333, 'pair', 1000))
        self.assertIsNone(requests.accept(update(1, 'abc'), 444, 'pair', 1000))
        self.assertIsNone(requests.accept(update(1, 'abc'), 333, 'other', 1000))
        self.assertEqual(requests.accept(update(1, 'abc'), 333, 'pair', 1000), (nonce, 'abcZg=='))


if __name__ == '__main__':
    unittest.main()
