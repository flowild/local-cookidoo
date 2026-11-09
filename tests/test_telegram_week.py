import base64
import json
import os
import tempfile
import unittest
import zlib
from unittest.mock import AsyncMock

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from fastapi.testclient import TestClient

from app.main import create_app
from app.security import Vault
from app.telegram_week import snapshot


class TelegramWeekTests(unittest.TestCase):
    def test_snapshot_applies_queue_and_preserves_shelf_and_placeholders(self):
        week = {'today':'2026-01-05', 'days':[{'date':f'2026-01-{i:02}', 'recipes':[]} for i in range(5, 12)],
                'shelf':[{'name':'Ablage'}]}
        week['days'][0]['recipes'] = [{'calendar_id':'one','custom':False,'name':'Rezept A'}]
        queue = {'phase':'pending', 'items':[{'week':'2026-01-05','source':'2026-01-05','target':'2026-01-06','recipe_id':'one','custom':False}]}
        result = snapshot(week, queue, [{'target':'2026-01-05','placeholder':'sushi'}, {'target':'shelf','placeholder':'resteessen'}])
        self.assertEqual(result['days'][0]['recipes'], [])
        self.assertEqual(result['days'][1]['recipes'], ['Rezept A'])
        self.assertEqual(result['days'][0]['placeholders'], ['sushi'])
        self.assertEqual(result['shelf'], ['Ablage'])
        self.assertEqual(result['shelf_placeholders'], ['resteessen'])
        self.assertEqual(week['days'][0]['recipes'][0]['name'], 'Rezept A')

    def test_loopback_endpoint_encrypts_only_paired_account(self):
        with tempfile.TemporaryDirectory() as directory:
            app = create_app(directory)
            database = app.state.database
            database.set('account', {'email':'test@example.invalid','region':'de'})
            owner = app.state.sync.cart_owner()
            key = os.urandom(32)
            Vault(directory, 'telegram-server-bot.enc').write({'cart_key':base64.b64encode(key).decode(), 'cart_owner':owner})
            week = {'today':'2026-01-05','days':[{'date':f'2026-01-{i:02}','recipes':[]} for i in range(5,12)], 'shelf':[]}
            week['days'][0]['recipes'] = [{'name':'Testgericht'}]
            app.state.sync.calendar_week = AsyncMock(return_value=week)
            with TestClient(app, client=('127.0.0.1', 1234)) as client:
                nonce = 'a' * 32
                response = client.get('/api/telegram-week', params={'day':'2026-01-05','nonce':nonce,'compressed':'true'})
                self.assertEqual(response.status_code, 200)
                self.assertNotIn('Testgericht', response.text)
                packed = base64.b64decode(response.json()['data'])
                decoded = AESGCM(key).decrypt(packed[:12], packed[12:], nonce.encode())
                self.assertEqual(json.loads(zlib.decompress(decoded))['days'][0]['recipes'], ['Testgericht'])
                database.set('account', {'email':'other@example.invalid','region':'de'})
                self.assertEqual(client.get('/api/telegram-week', params={'day':'2026-01-05','nonce':nonce}).status_code, 409)


if __name__ == '__main__':
    unittest.main()
