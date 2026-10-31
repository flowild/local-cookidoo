import asyncio
import dataclasses
import io
import json
import tempfile
import time
import unittest
from datetime import timedelta
from pathlib import Path
from types import SimpleNamespace as NS
from unittest.mock import patch

from yarl import URL

import httpx
from fastapi.testclient import TestClient
from PIL import Image

from app.main import create_app
from app.security import Vault
from app.storage import Database, now
from app.sync import SyncService

PASSWORD = 'test-only-password-123'
ORIGIN = {'Origin': 'https://testserver'}


class EmptyBookmarks:
    api_endpoint = URL('https://cookidoo.de')

    async def _request_json(self, *args, **kwargs):
        return {'bookmarks': [], 'page': {'totalPages': 0}}


def snapshot():
    recipes = {
        'r1': {'id': 'r1', 'name': 'Käse-Spätzle', 'source_url': 'https://cookidoo.de/recipes/recipe/de-DE/r1', 'total_seconds': 1800, 'updated_at': now()},
        'r2': {'id': 'r2', 'name': 'Suppe mit 50% Gemüse', 'source_url': 'https://cookidoo.de/recipes/recipe/de-DE/r2', 'total_seconds': 900, 'updated_at': now()},
    }
    collections = [
        {'id': 'custom:list1', 'source_id': 'list1', 'kind': 'custom', 'name': '<Lieblingsgerichte>', 'members': [{'id': 'r1'}, {'id': 'r2'}]},
        {'id': 'managed:list2', 'source_id': 'list2', 'kind': 'managed', 'name': 'Für jeden Tag', 'members': [{'id': 'r1'}]},
    ]
    return collections, recipes


class AppTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.app = create_app(self.tmp.name)
        self.client = TestClient(self.app, base_url='https://testserver')
        self.client.__enter__()

    def tearDown(self):
        self.client.__exit__(None, None, None)
        self.tmp.cleanup()

    def login(self):
        code = (Path(self.tmp.name) / 'setup-code').read_text()
        response = self.client.post('/api/auth/setup', json={'password': PASSWORD, 'code': code}, headers=ORIGIN)
        self.assertEqual(response.status_code, 200, response.text)
        return response

    def test_setup_is_single_use_and_sessions_are_revocable(self):
        self.assertEqual(self.client.get('/api/collections').status_code, 401)
        code = (Path(self.tmp.name) / 'setup-code').read_text()
        bad = self.client.post('/api/auth/setup', json={'password': PASSWORD, 'code': 'incorrect-code'}, headers=ORIGIN)
        self.assertEqual(bad.status_code, 403)
        response = self.login()
        self.assertIn('HttpOnly', response.headers['set-cookie'])
        self.assertIn('Secure', response.headers['set-cookie'])
        old_cookie = self.client.cookies.get('rezeptgarten_session')
        self.assertFalse((Path(self.tmp.name) / 'setup-code').exists())
        self.assertEqual(self.client.post('/api/auth/setup', json={'password': PASSWORD, 'code': code}, headers=ORIGIN).status_code, 403)
        self.assertEqual(self.client.post('/api/settings', json={'sync_hours': 1}, headers={'Origin':'https://evil.example'}).status_code, 403)
        self.assertEqual(self.client.post('/api/auth/logout', json={}, headers=ORIGIN).status_code, 200)
        self.client.cookies.set('rezeptgarten_session', old_cookie)
        self.assertEqual(self.client.get('/api/collections').status_code, 401)
        self.client.cookies.clear()
        self.assertEqual(self.client.post('/api/auth/login', json={'password': PASSWORD}, headers=ORIGIN).status_code, 200)

    def test_library_search_membership_export_and_private_images(self):
        self.login()
        self.app.state.database.save_snapshot(*snapshot())
        stats = self.client.get('/api/status').json()['stats']
        self.assertEqual((stats['collections'], stats['recipes']), (2, 2))
        result = self.client.get('/api/recipes', params={'q':'KÄSE'}).json()
        self.assertEqual([row['id'] for row in result['items']], ['r1'])
        self.assertEqual(self.client.get('/api/recipes', params={'q':'%'}).json()['total'], 1)
        self.assertEqual(self.client.get('/api/recipes', params={'collection':'managed:list2'}).json()['total'], 1)
        self.assertEqual(len(self.client.get('/api/recipes/r1').json()['collections']), 2)
        self.assertEqual(self.client.get('/api/recipes?sort=time&limit=1').json()['items'][0]['id'], 'r2')
        self.assertEqual(self.client.get('/api/recipes?offset=1&limit=1').json()['total'], 2)
        exported = self.client.get('/api/export').json()
        self.assertEqual(len(exported['recipes']), 2)
        self.assertNotIn('admin_password', json.dumps(exported))
        filename = 'a' * 40 + '.webp'
        Image.new('RGB', (3, 3), 'green').save(Path(self.tmp.name) / 'images' / filename)
        image = self.client.get('/api/images/' + filename)
        self.assertEqual(image.status_code, 200)
        self.assertEqual(image.headers['cache-control'], 'no-store')
        self.client.post('/api/auth/logout', json={}, headers=ORIGIN)
        self.assertEqual(self.client.get('/api/images/' + filename).status_code, 401)

    def test_snapshot_failure_preserves_previous_library(self):
        database = self.app.state.database
        database.save_snapshot(*snapshot())
        bad = [{'id':'custom:bad','source_id':'bad','kind':'custom','name':'bad','members':[{'id':'missing'}]}]
        with self.assertRaises(Exception):
            database.save_snapshot(bad, {})
        self.assertEqual(database.stats()['recipes'], 2)
        self.assertEqual(database.stats()['collections'], 2)

    def test_manifest_and_shell_are_available_without_personal_data(self):
        self.assertEqual(self.client.get('/').status_code, 200)
        manifest = self.client.get('/static/manifest.webmanifest').json()
        self.assertEqual(manifest['display'], 'standalone')
        for item in manifest['icons']:
            image = self.client.get(item['src'])
            self.assertEqual(image.status_code, 200)
            width, height = map(int, item['sizes'].split('x'))
            self.assertEqual(Image.open(io.BytesIO(image.content)).size, (width, height))
        worker = self.client.get('/sw.js')
        self.assertEqual(worker.headers['service-worker-allowed'], '/')
        self.assertIn("path.startsWith('/api/')", worker.text)

    def test_sync_endpoint_runs_on_event_loop(self):
        self.login()
        class Fake(EmptyBookmarks):
            async def count_custom_collections(self): return (0, 0)
            async def count_managed_collections(self): return (0, 0)
        self.app.state.sync.client = Fake()
        response = self.client.post('/api/sync', json={}, headers=ORIGIN)
        self.assertEqual(response.status_code, 200)
        for _ in range(50):
            if not self.app.state.sync.state['running']: break
            time.sleep(.01)
        self.assertEqual(self.app.state.sync.state['phase'], 'done')


class SyncTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Database(self.tmp.name)
        self.vault = Vault(self.tmp.name)
        self.service = SyncService(self.db, self.vault)

    async def asyncTearDown(self):
        await self.service.close()
        self.tmp.cleanup()

    async def test_all_pages_saved_and_recipe_details_deduplicated(self):
        calls = []
        def collection(id, recipes):
            return NS(id=id, name=id, description='', chapters=[NS(name='', recipes=[NS(id=r, name=r, total_time=timedelta(minutes=10)) for r in recipes])])
        class Fake(EmptyBookmarks):
            async def count_custom_collections(self): return (2, 2)
            async def get_custom_collections(self, page=0): return [collection('c'+str(page), ['r1', 'r2'] if page == 0 else ['r1'])]
            async def count_managed_collections(self): return (1, 1)
            async def get_managed_collections(self, page=0): return [collection('m1', ['r3'])]
            async def get_recipe_details(self, recipe_id):
                calls.append(recipe_id)
                if recipe_id == 'r3': raise RuntimeError('unavailable')
                return NS(name='Rezept '+recipe_id,total_time=timedelta(minutes=15),active_time=timedelta(minutes=5),serving_size=4,difficulty='easy',ingredients=[],image=None,thumbnail=None)
        self.service.client = Fake()
        self.assertTrue(self.service.begin())
        self.assertFalse(self.service.begin())
        await self.service.task
        self.assertEqual(sorted(calls), ['r1','r2','r3'])
        self.assertEqual(self.db.stats()['collections'], 3)
        self.assertEqual(self.db.stats()['recipes'], 3)
        self.assertEqual(self.db.recipe('r3')['name'], 'r3')
        self.assertEqual(self.service.state['phase'], 'done')
        self.assertTrue(list((Path(self.tmp.name) / 'backups').glob('*.sqlite3')))

    async def test_remote_list_failure_keeps_last_good_snapshot(self):
        self.db.save_snapshot(*snapshot())
        class Fake(EmptyBookmarks):
            async def count_custom_collections(self): raise RuntimeError('network unavailable')
        self.service.client = Fake()
        self.service.begin()
        await self.service.task
        self.assertEqual(self.db.stats()['recipes'], 2)
        self.assertEqual(self.service.state['phase'], 'error')

    async def test_image_download_is_normalized_and_rejects_arbitrary_hosts(self):
        data = io.BytesIO()
        Image.new('RGB', (1500, 1000), '#608050').save(data, 'PNG')
        requests = []
        def handler(request):
            requests.append(request)
            return httpx.Response(200, content=data.getvalue(), headers={'content-type':'image/png'})
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            self.assertIsNone(await self.service.cache_image('http://127.0.0.1/secret', client))
            self.assertIsNone(await self.service.cache_image('https://evil.example/photo', client))
            filename = await self.service.cache_image('https://assets.tmecosys.com/recipe.jpg', client)
            self.assertEqual(len(requests), 1)
            self.assertNotIn('authorization', requests[0].headers)
            with Image.open(self.service.images / filename) as image:
                self.assertEqual(image.format, 'WEBP')
                self.assertLessEqual(max(image.size), 960)
            self.assertEqual(await self.service.cache_image('https://assets.tmecosys.com/recipe.jpg', client), filename)
            self.assertEqual(len(requests), 1)

    async def test_bookmarks_import_even_when_custom_and_managed_lists_are_empty(self):
        pages_requested = []
        details_requested = []
        class Fake(EmptyBookmarks):
            async def count_custom_collections(self): return (0, 0)
            async def count_managed_collections(self): return (0, 0)
            async def _request_json(self, method, url, description, **kwargs):
                page = int(kwargs['params']['page'])
                pages_requested.append(page)
                self.assert_url = str(url)
                items = [{'recipe': {'id': 'r1', 'title': 'Pasta', 'totalTime': 900}}] if page == 0 else [{'recipeId': 'r2', 'title': 'Suppe'}, {'recipe': {'id': 'r1', 'title': 'Pasta'}}]
                return {'bookmarks': items, 'page': {'totalPages': 2}}
            async def get_recipe_details(self, recipe_id):
                details_requested.append(recipe_id)
                return NS(name=recipe_id,total_time=900,active_time=300,serving_size=4,difficulty='easy',ingredients=[],image=None,thumbnail=None)
        self.service.client = Fake()
        self.service.begin()
        await self.service.task
        self.assertEqual(pages_requested, [0, 1])
        self.assertEqual(details_requested, ['r1', 'r2'])
        self.assertEqual(self.db.stats()['recipes'], 2)
        self.assertEqual(self.db.collections()[0]['name'], 'Merkliste')
        self.assertEqual(self.db.collections()[0]['kind'], 'bookmarks')
        self.assertFalse(self.db.get('last_result')['running'])

    async def test_login_password_is_discarded_and_tokens_are_encrypted(self):
        @dataclasses.dataclass
        class Auth:
            access_token: str = 'fixture-access-token'
            refresh_token: str = 'fixture-refresh-token'
            expires_at: float = 9999999999
        configs = []
        class Fake:
            def __init__(self, session, cfg, on_auth_data_update):
                self.cfg, self.callback = cfg, on_auth_data_update
                configs.append(cfg)
            async def login(self): self.callback(Auth())
        with patch('app.sync.Cookidoo', Fake):
            await self.service.connect('fixture@example.test', 'not-a-real-password', 'de')
        self.assertEqual(configs[0].password, '')
        self.assertEqual(self.vault.read()['auth']['access_token'], 'fixture-access-token')
        self.assertNotIn(b'fixture-access-token', self.vault.path.read_bytes())
        self.assertNotIn(b'not-a-real-password', self.vault.path.read_bytes())


if __name__ == '__main__':
    unittest.main()
