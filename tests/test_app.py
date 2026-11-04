import asyncio
import dataclasses
import hashlib
import io
import json
import sqlite3
import tempfile
import time
import unittest
from datetime import timedelta
from pathlib import Path
from types import SimpleNamespace as NS
from unittest.mock import AsyncMock, patch

from yarl import URL

import httpx
from fastapi.testclient import TestClient
from PIL import Image

from app.main import create_app
from app.ingredients import ingredient_available, ingredient_display_name, ingredient_group_key, ingredient_name
from app.security import Vault
from app.storage import Database, now
from app.sync import NoteRequestError, SyncService

PASSWORD = 'test-only-password-123'
ORIGIN = {'Origin': 'https://testserver'}


class EmptyBookmarks:
    async def list_custom_recipes(self): return []

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
        self.app.state.sync.creation_origins = AsyncMock(return_value={})
        self.client = TestClient(self.app, base_url='https://testserver')
        self.client.__enter__()

    def tearDown(self):
        self.client.__exit__(None, None, None)
        self.tmp.cleanup()

    def test_access_without_password_and_origin_protection(self):
        self.assertEqual(self.client.get('/api/collections').status_code, 200)
        self.assertEqual(self.client.get('/api/status').status_code, 200)
        self.assertFalse((Path(self.tmp.name) / 'setup-code').exists())
        self.assertEqual(self.client.post('/api/settings', json={'sync_hours': 1}, headers={'Origin': 'https://evil.example'}).status_code, 403)
        self.assertEqual(self.client.post('/api/settings', json={'sync_hours': 1}, headers=ORIGIN).status_code, 200)

    def test_week_placeholders_are_scoped_and_do_not_enter_calendar_queue(self):
        db = self.app.state.database
        payload = {'week': '2026-01-05', 'placeholder': 'sushi', 'present': True}
        self.assertEqual(self.client.put('/api/calendar/placeholders', json=payload).status_code, 403)
        self.assertEqual(self.client.put('/api/calendar/placeholders', json=payload, headers=ORIGIN).json()['items'], ['sushi'])
        moved = self.client.put('/api/calendar/placeholders', json={**payload, 'target':'2026-01-07'}, headers=ORIGIN).json()
        self.assertEqual(moved['items'], [])
        self.assertEqual([(item['placeholder'], item['target']) for item in moved['placements']], [('sushi', '2026-01-07')])
        self.assertEqual(self.client.put('/api/calendar/placeholders', json={**payload, 'target':'2026-01-12'}, headers=ORIGIN).status_code, 400)
        self.assertEqual(db.week_placeholder_shelf(self.app.state.sync.week_collection_owner(), '2026-01-05')[0]['target'], '2026-01-07')
        self.assertEqual(self.client.put('/api/calendar/placeholders', json=payload, headers=ORIGIN).json()['items'], ['sushi'])
        other_week = {**payload, 'week': '2026-01-12', 'placeholder': 'abendbrot'}
        self.assertEqual(self.client.put('/api/calendar/placeholders', json=other_week, headers=ORIGIN).json()['items'], ['abendbrot'])
        self.assertEqual(self.client.put('/api/calendar/placeholders', json={**payload, 'week':'2026-01-06'}, headers=ORIGIN).status_code, 400)
        self.assertEqual(self.client.put('/api/calendar/placeholders', json={**payload, 'placeholder':'invalid'}, headers=ORIGIN).status_code, 422)
        leftovers = self.client.put('/api/calendar/placeholders', json={**payload, 'placeholder':'resteessen', 'target':'2026-01-06'}, headers=ORIGIN)
        self.assertEqual(leftovers.status_code, 200)
        self.assertIn(('resteessen', '2026-01-06'), [(item['placeholder'], item['target']) for item in leftovers.json()['placements']])
        self.assertFalse((db.get('calendar_move_queue') or {}).get('items'))
        db.set('account', {'email':'another@example.test', 'region':'de'})
        self.assertEqual(self.client.put('/api/calendar/placeholders', json={**payload, 'present':False}, headers=ORIGIN).json()['items'], [])
        db.set('account', None)
        self.assertEqual(self.client.put('/api/calendar/placeholders', json={**payload, 'present':False}, headers=ORIGIN).json()['items'], [])
        self.assertEqual(self.client.put('/api/calendar/placeholders', json={**other_week, 'present':True}, headers=ORIGIN).json()['items'], ['abendbrot'])

    def test_existing_placeholder_shelf_is_migrated_without_losing_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            db = sqlite3.connect(str(Path(directory) / 'library.sqlite3'))
            with db:
                db.execute('CREATE TABLE week_placeholder_shelf (owner TEXT NOT NULL, week TEXT NOT NULL, placeholder TEXT NOT NULL, PRIMARY KEY(owner, week, placeholder))')
                db.execute("INSERT INTO week_placeholder_shelf VALUES ('owner', '2026-01-05', 'sushi')")
            db.close()
            database = Database(directory)
            rows = database.week_placeholder_shelf('owner', '2026-01-05')
            self.assertEqual([(row['placeholder'], row['target']) for row in rows], [('sushi', 'shelf')])
            self.assertTrue(rows[0]['id'])

    def test_week_placeholders_allow_multiple_independent_instances(self):
        base = {'week':'2026-01-05', 'placeholder':'sushi', 'present':True, 'target':'shelf'}
        first = {**base, 'instance_id':'first', 'create':True}
        second = {**base, 'instance_id':'second', 'create':True}
        self.client.put('/api/calendar/placeholders', json=first, headers=ORIGIN)
        self.client.put('/api/calendar/placeholders', json=first, headers=ORIGIN)
        result = self.client.put('/api/calendar/placeholders', json=second, headers=ORIGIN).json()
        self.assertEqual([item['id'] for item in result['placements']], ['first', 'second'])
        result = self.client.put('/api/calendar/placeholders', json={**first, 'create':False, 'target':'2026-01-06'}, headers=ORIGIN).json()
        self.assertEqual([(item['id'], item['target']) for item in result['placements']], [('first','2026-01-06'), ('second','shelf')])
        result = self.client.put('/api/calendar/placeholders', json={**first, 'create':False}, headers=ORIGIN).json()
        self.assertEqual([item['target'] for item in result['placements']], ['shelf', 'shelf'])
        result = self.client.put('/api/calendar/placeholders', json={**first, 'create':False, 'present':False}, headers=ORIGIN).json()
        self.assertEqual([item['id'] for item in result['placements']], ['second'])
        self.assertEqual(self.client.put('/api/calendar/placeholders', json={**first, 'create':False, 'target':'2026-01-07'}, headers=ORIGIN).status_code, 404)

    def test_calendar_week_reads_cookidoo_and_fills_empty_days(self):
        from datetime import datetime, timedelta
        from zoneinfo import ZoneInfo
        today = datetime.now(ZoneInfo('Europe/Berlin')).date()
        monday = today - timedelta(days=today.weekday())
        self.app.state.database.save_snapshot(*snapshot())
        remote = NS(id='not-local', name='Rezept aus Cookidoo')
        local = NS(id='r1', name='Anderer Name')
        day = NS(id=monday.isoformat(), recipes=[local, remote], customer_recipe_ids=['own'])
        cookidoo = NS(get_recipes_in_calendar_week=AsyncMock(return_value=[day]),
                      get_custom_recipe=AsyncMock(return_value=NS(name='Meine Kreation')))
        self.app.state.sync.client = cookidoo
        response = self.client.get('/api/calendar/week')
        self.assertEqual(response.status_code, 200)
        week = response.json()
        self.assertEqual(week['today'], today.isoformat())
        self.assertEqual([d['date'] for d in week['days']], [(monday + timedelta(days=i)).isoformat() for i in range(7)])
        self.assertEqual([r['name'] for r in week['days'][0]['recipes']], ['Käse-Spätzle', 'Rezept aus Cookidoo', 'Meine Kreation'])
        self.assertEqual(week['days'][0]['recipes'][0]['id'], 'r1')
        self.assertEqual(week['days'][0]['recipes'][1]['id'], 'not-local')
        self.assertTrue(all(not d['recipes'] for d in week['days'][1:]))
        cookidoo.get_recipes_in_calendar_week.assert_awaited_once_with(monday)

    def test_calendar_week_reports_disconnected_or_failed_read(self):
        self.assertEqual(self.client.get('/api/calendar/week').status_code, 409)
        self.app.state.sync.client = NS(get_recipes_in_calendar_week=AsyncMock(side_effect=RuntimeError('secret')))
        response = self.client.get('/api/calendar/week')
        self.assertEqual(response.status_code, 502)
        self.assertNotIn('secret', response.text)

    def test_week_and_existing_shelf_use_local_recipe_difficulty(self):
        service = self.app.state.sync
        collections, recipes = snapshot()
        recipes['r1']['difficulty'] = 'easy'
        recipes['r1']['servings'] = '4'
        self.app.state.database.save_snapshot(collections, recipes)
        day = NS(id='2026-01-05', recipes=[NS(id='r1', name='Test')], customer_recipe_ids=[])
        service.client = NS(get_recipes_in_calendar_week=AsyncMock(return_value=[day]))
        payload = {'week':'2026-01-05','source':'preview','target':'shelf','recipe_id':'r1','custom':False,'move_id':'preview-1','recipe':{}}
        self.assertEqual(self.client.post('/api/calendar/placement', json=payload, headers=ORIGIN).status_code, 200)
        owner = service.week_collection_owner()
        def old_shelf(queue):
            queue['shelves'][owner]['2026-01-05'][0].pop('difficulty')
            return queue
        self.app.state.database.calendar_queue_update(old_shelf)
        response = self.client.get('/api/calendar/week?day=2026-01-05')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['days'][0]['recipes'][0]['difficulty'], 'easy')
        self.assertEqual(response.json()['shelf'][0]['difficulty'], 'easy')
        self.assertNotIn('difficulty', self.app.state.database.get('calendar_move_queue')['shelves'][owner]['2026-01-05'][0])

    def test_week_badges_reuse_local_difficulty_without_extra_detail_request(self):
        service = self.app.state.sync
        collections, recipes = snapshot()
        recipes['r1'].update(difficulty='medium', servings='4')
        self.app.state.database.save_snapshot(collections, recipes)
        service._read_recipe_note = AsyncMock(return_value=None)
        service.client = NS(get_recipe_details=AsyncMock(), get_custom_recipe=AsyncMock())
        response = self.client.get('/api/calendar/badges?recipe_id=r1')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['items'][0]['difficulty'], 'medium')
        service.client.get_recipe_details.assert_not_awaited()

    def test_calendar_recipe_opens_details_without_adding_to_library(self):
        detail = NS(name='Externes Rezept', ingredients=['2 Eier'], instructions=[], total_time=900, active_time=300,
                    serving_size=2, image=None, thumbnail=None,
                    step_groups=[NS(title='Zubereitung', recipe_steps=[NS(formatted_text='<b>Verrühren</b>')])])
        cookidoo = NS(get_recipe_details=AsyncMock(return_value=detail))
        self.app.state.sync.client = cookidoo
        self.assertEqual(self.client.get('/api/recipes/r-remote').status_code, 404)
        response = self.client.get('/api/recipes/r-remote?calendar=true')
        self.assertEqual(response.status_code, 200)
        result = response.json()
        self.assertEqual(result['name'], 'Externes Rezept')
        self.assertFalse(result['is_local'])
        self.assertEqual(json.loads(result['ingredients_json']), ['2 Eier'])
        self.assertEqual(json.loads(result['instructions_json'])[0]['steps'], ['Verrühren'])
        self.assertEqual(result['source_url'], 'https://cookidoo.de/recipes/recipe/de-DE/r-remote')
        self.assertIsNone(self.app.state.database.recipe('r-remote'))
        cookidoo.get_recipe_details.assert_awaited_once_with('r-remote')

    def test_calendar_creation_and_recipe_actions_keep_identity(self):
        detail = NS(name='Eigene Kreation', ingredients=['1 Apfel'], instructions=['Schneiden'], total_time=60,
                    active_time=30, serving_size=1, image=None, thumbnail=None)
        service = self.app.state.sync
        service.client = NS(get_custom_recipe=AsyncMock(return_value=detail))
        response = self.client.get('/api/recipes/creation:own?calendar=true')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['id'], 'creation:own')
        self.assertEqual(json.loads(response.json()['instructions_json']), ['Schneiden'])
        service.client.get_custom_recipe.assert_awaited_once_with('own')
        service.recipe_action = AsyncMock(return_value={'verified': True})
        self.assertEqual(self.client.post('/api/recipes/creation:own/plan-today', headers=ORIGIN).status_code, 404)
        self.assertEqual(self.client.post('/api/recipes/creation:own/plan-today?calendar=true', headers=ORIGIN).json(), {'verified': True})
        service.recipe_action.assert_awaited_once_with('creation:own', 'plan')

    def test_calendar_badges_include_metadata_and_only_note_presence(self):
        service = self.app.state.sync
        self.app.state.database.save_snapshot(*snapshot())
        async def note(identifier):
            if identifier == 'own':
                raise RuntimeError('not available')
            return 'private note content'
        service._read_recipe_note = AsyncMock(side_effect=note)
        detail = NS(total_time=1200, serving_size=4, difficulty='easy')
        service.client = NS(get_recipe_details=AsyncMock(return_value=detail), get_custom_recipe=AsyncMock(return_value=detail))
        response = self.client.get('/api/calendar/badges?recipe_id=r1&recipe_id=creation:own&recipe_id=r1')
        self.assertEqual(response.status_code, 200)
        items = response.json()['items']
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0], {'id':'r1', 'has_note':True, 'total_seconds':1800, 'servings':'4', 'difficulty':'easy'})
        self.assertEqual(items[1], {'id':'creation:own', 'has_note':None, 'total_seconds':1200, 'servings':'4', 'difficulty':'easy'})
        self.assertNotIn('private note content', response.text)
        self.assertEqual(self.client.get('/api/calendar/badges?recipe_id=invalid%2Fid').status_code, 409)

    def test_preview_note_status_does_not_fetch_recipe_details(self):
        service = self.app.state.sync
        service._read_recipe_note = AsyncMock(return_value='private note')
        service.client = NS(get_recipe_details=AsyncMock(), get_custom_recipe=AsyncMock())
        response = self.client.get('/api/calendar/badges?notes_only=true&recipe_id=r1')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()['items'][0]['has_note'])
        self.assertNotIn('private note', response.text)
        service.client.get_recipe_details.assert_not_awaited()
        service.client.get_custom_recipe.assert_not_awaited()

    def test_unfiled_week_recipe_creates_and_confirms_cookidoo_list(self):
        from unittest.mock import Mock
        service = self.app.state.sync
        recipe = NS(id='r-unfiled', is_custom=False)
        creation = NS(id='own', is_custom=True)
        created = NS(id='new-list')
        updated = NS(chapters=[NS(recipes=[recipe])])
        service.client = NS(get_recipes_in_calendar_week=AsyncMock(return_value=[NS(recipes=[recipe, creation])]),
                            add_custom_collection=AsyncMock(return_value=created), add_recipes_to_custom_collection=AsyncMock(return_value=updated))
        service.collections = AsyncMock(return_value=[])
        service.begin = Mock(return_value=True)
        payload = {'day':'2026-01-05'}
        self.assertEqual(self.client.post('/api/calendar/save-unfiled', json=payload).status_code, 403)
        response = self.client.post('/api/calendar/save-unfiled', json=payload, headers=ORIGIN)
        self.assertEqual(response.json(), {'added':1, 'sync_started':True})
        service.client.add_recipes_to_custom_collection.assert_awaited_once_with('new-list', ['r-unfiled'])
        self.assertTrue(self.app.state.database.get('week_unfiled_collection')['id'] == 'new-list')
        service.begin.assert_called_once()

    def test_unfiled_week_recipe_does_not_duplicate_existing_cookidoo_membership(self):
        from unittest.mock import Mock
        service = self.app.state.sync
        recipe = NS(id='r-unfiled', is_custom=False)
        service.client = NS(get_recipes_in_calendar_week=AsyncMock(return_value=[NS(recipes=[recipe])]),
                            add_custom_collection=AsyncMock(), add_recipes_to_custom_collection=AsyncMock())
        service.database.set('week_unfiled_collection', {'owner':service.week_collection_owner(), 'id':'archive'})
        service.collections = AsyncMock(return_value=[{'kind':'custom', 'source_id':'original', 'name':'Existing', 'members':[{'id':'r-unfiled'}]}, {'kind':'custom', 'source_id':'archive', 'name':'Archive', 'members':[]}])
        service.begin = Mock(return_value=True)
        response = self.client.post('/api/calendar/save-unfiled', json={'day':'2026-01-05'}, headers=ORIGIN)
        self.assertEqual(response.json(), {'added':0, 'sync_started':True})
        service.client.add_custom_collection.assert_not_awaited()
        service.client.add_recipes_to_custom_collection.assert_not_awaited()

    def test_unfiled_list_is_created_even_when_week_is_empty(self):
        from unittest.mock import Mock
        service = self.app.state.sync
        service.client = NS(get_recipes_in_calendar_week=AsyncMock(return_value=[]),
                            add_custom_collection=AsyncMock(return_value=NS(id='new-list')),
                            add_recipes_to_custom_collection=AsyncMock())
        service.collections = AsyncMock(return_value=[])
        service.begin = Mock(return_value=True)
        response = self.client.post('/api/calendar/save-unfiled', json={'day':'2026-01-05'}, headers=ORIGIN)
        self.assertEqual(response.json(), {'added':0, 'sync_started':True})
        service.client.add_custom_collection.assert_awaited_once()
        service.client.add_recipes_to_custom_collection.assert_not_awaited()

    def test_unfiled_week_recipe_reports_unconfirmed_list_addition(self):
        from unittest.mock import Mock
        service = self.app.state.sync
        recipe = NS(id='r-unfiled', is_custom=False)
        service.client = NS(get_recipes_in_calendar_week=AsyncMock(return_value=[NS(recipes=[recipe])]),
                            add_custom_collection=AsyncMock(return_value=NS(id='new-list')),
                            add_recipes_to_custom_collection=AsyncMock(return_value=NS(chapters=[])))
        service.collections = AsyncMock(return_value=[])
        service.begin = Mock(return_value=True)
        response = self.client.post('/api/calendar/save-unfiled', json={'day':'2026-01-05'}, headers=ORIGIN)
        self.assertEqual(response.status_code, 409)
        service.begin.assert_not_called()

    def test_calendar_week_selects_monday_and_supplies_remote_links_and_images(self):
        from datetime import date
        remote = NS(id='r123', name='Rezept', image='https://assets.tmecosys.com/photo.jpg', thumbnail=None)
        custom = NS(name='Eigene Idee', image='https://assets.tmecosys.com/custom.jpg', thumbnail=None)
        day = NS(id='2025-12-29', recipes=[remote], customer_recipe_ids=['own'])
        cookidoo = NS(get_recipes_in_calendar_week=AsyncMock(return_value=[day]), get_custom_recipe=AsyncMock(return_value=custom))
        self.app.state.sync.client = cookidoo
        self.app.state.sync.cache_image = AsyncMock()
        response = self.client.get('/api/calendar/week?day=2026-01-01')
        self.assertEqual(response.status_code, 200)
        cookidoo.get_recipes_in_calendar_week.assert_awaited_once_with(date(2025, 12, 29))
        days = response.json()['days']
        self.assertEqual([days[0]['date'], days[-1]['date']], ['2025-12-29', '2026-01-04'])
        recipe, creation = days[0]['recipes']
        self.assertEqual(recipe['source_url'], 'https://cookidoo.de/recipes/recipe/de-DE/r123')
        self.assertEqual(creation['source_url'], 'https://cookidoo.de/created-recipes/de-DE/own/edit')
        self.assertEqual(recipe['image_file'], hashlib.sha256(b'https://assets.tmecosys.com/photo.jpg').hexdigest()[:40] + '.webp')
        self.assertEqual(creation['image_file'], hashlib.sha256(b'https://assets.tmecosys.com/custom.jpg').hexdigest()[:40] + '.webp')
        self.app.state.sync.cache_image.assert_not_awaited()
        self.assertEqual(self.client.get('/api/calendar/week?day=not-a-date').status_code, 422)

    def test_calendar_move_adds_verifies_and_only_then_removes(self):
        source, target = '2026-01-05', '2026-01-06'
        def day(value): return NS(id=value, recipes=[NS(id='r1')], customer_recipe_ids=[])
        cookidoo = NS(get_recipes_in_calendar_week=AsyncMock(side_effect=[[day(source)], [day(source), day(target)], [day(target)]]),
                      add_recipes_to_calendar=AsyncMock(), remove_recipe_from_calendar=AsyncMock())
        self.app.state.sync.client = cookidoo
        payload = {'source': source, 'target': target, 'recipe_id': 'r1', 'custom': False}
        self.assertEqual(self.client.post('/api/calendar/move', json=payload).status_code, 403)
        result = self.client.post('/api/calendar/move', json=payload, headers=ORIGIN)
        self.assertEqual(result.json()['status'], 'moved')
        self.assertEqual(cookidoo.get_recipes_in_calendar_week.await_count, 3)
        cookidoo.add_recipes_to_calendar.assert_awaited_once()
        cookidoo.remove_recipe_from_calendar.assert_awaited_once()

    def test_calendar_move_does_not_remove_without_confirmed_target(self):
        source, target = '2026-01-05', '2026-01-06'
        day = NS(id=source, recipes=[], customer_recipe_ids=['own'])
        cookidoo = NS(get_recipes_in_calendar_week=AsyncMock(return_value=[day]),
                      add_custom_recipes_to_calendar=AsyncMock(), remove_custom_recipe_from_calendar=AsyncMock())
        self.app.state.sync.client = cookidoo
        payload = {'source': source, 'target': target, 'recipe_id': 'own', 'custom': True}
        response = self.client.post('/api/calendar/move', json=payload, headers=ORIGIN)
        self.assertEqual(response.json()['status'], 'uncertain')
        cookidoo.add_custom_recipes_to_calendar.assert_awaited_once()
        cookidoo.remove_custom_recipe_from_calendar.assert_not_awaited()
        self.assertEqual(self.client.post('/api/calendar/move', json={**payload, 'target': '2026-01-12'}, headers=ORIGIN).status_code, 409)

    def test_calendar_move_never_removes_if_target_already_contains_recipe(self):
        day = lambda value: NS(id=value, recipes=[NS(id='r1')], customer_recipe_ids=[])
        cookidoo = NS(get_recipes_in_calendar_week=AsyncMock(return_value=[day('2026-01-05'), day('2026-01-06')]),
                      add_recipes_to_calendar=AsyncMock(), remove_recipe_from_calendar=AsyncMock())
        self.app.state.sync.client = cookidoo
        response = self.client.post('/api/calendar/move', json={'source':'2026-01-05', 'target':'2026-01-06', 'recipe_id':'r1', 'custom':False}, headers=ORIGIN)
        self.assertEqual(response.status_code, 409)
        cookidoo.add_recipes_to_calendar.assert_not_awaited()
        cookidoo.remove_recipe_from_calendar.assert_not_awaited()

    def test_calendar_move_reports_unconfirmed_removal_of_custom_recipe(self):
        source = NS(id='2026-01-05', recipes=[], customer_recipe_ids=['own'])
        target = NS(id='2026-01-06', recipes=[], customer_recipe_ids=['own'])
        cookidoo = NS(get_recipes_in_calendar_week=AsyncMock(side_effect=[[source], [source, target]]),
                      add_custom_recipes_to_calendar=AsyncMock(), remove_custom_recipe_from_calendar=AsyncMock(side_effect=RuntimeError('uncertain')))
        self.app.state.sync.client = cookidoo
        response = self.client.post('/api/calendar/move', json={'source':'2026-01-05', 'target':'2026-01-06', 'recipe_id':'own', 'custom':True}, headers=ORIGIN)
        self.assertEqual(response.json()['status'], 'uncertain')
        self.assertIn('Zieltag', response.json()['message'])
        cookidoo.remove_custom_recipe_from_calendar.assert_awaited_once()

    def test_manual_sync_requests_calendar_sync(self):
        with patch.object(self.app.state.sync, 'begin', return_value=True) as begin:
            response = self.client.post('/api/sync', headers=ORIGIN)
        self.assertEqual(response.json(), {'started': True})
        begin.assert_called_once_with(manual=True)

    def test_calendar_queue_persists_and_resets_five_minute_deadline(self):
        from datetime import datetime, timedelta, timezone
        service = self.app.state.sync
        service.client = NS()
        first = {'source':'2026-01-05','target':'2026-01-06','recipe_id':'r1','custom':False,'move_id':'move-1'}
        self.assertEqual(self.client.post('/api/calendar/queue', json=first).status_code, 403)
        before = datetime.now(timezone.utc)
        result = self.client.post('/api/calendar/queue', json=first, headers=ORIGIN).json()
        self.assertEqual(result['phase'], 'waiting')
        self.assertGreaterEqual((datetime.fromisoformat(result['due']) - before).total_seconds(), 299)
        self.assertLessEqual((datetime.fromisoformat(result['due']) - before).total_seconds(), 301)
        def age(queue):
            queue['due'] = (datetime.now(timezone.utc) + timedelta(seconds=10)).isoformat()
            return queue
        service.database.calendar_queue_update(age)
        second = {**first, 'source':'2026-01-06', 'target':'2026-01-07', 'move_id':'move-2'}
        result = self.client.post('/api/calendar/queue', json=second, headers=ORIGIN).json()
        self.assertEqual(len(result['items']), 2)
        self.assertGreater((datetime.fromisoformat(result['due']) - before).total_seconds(), 299)
        again = self.client.post('/api/calendar/queue', json=second, headers=ORIGIN).json()
        self.assertEqual(len(again['items']), 2)
        self.assertEqual(again['due'], result['due'])
        self.assertEqual(self.client.get('/api/status').json()['calendar_queue'], again)
        self.assertEqual(self.client.delete('/api/calendar/queue', headers=ORIGIN).status_code, 409)

    def test_cannot_discard_another_accounts_failed_calendar_queue(self):
        service = self.app.state.sync
        service.client = NS()
        service.database.set('account', {'email':'first@example.test', 'region':'de'})
        queue = {'owner':service.week_collection_owner(), 'phase':'error', 'items':[{'source':'2026-01-05', 'target':'2026-01-06', 'recipe_id':'r1', 'custom':False}], 'due':None, 'error':'unconfirmed'}
        service.database.set('calendar_move_queue', queue)
        service.database.set('account', {'email':'second@example.test', 'region':'de'})
        self.assertEqual(self.client.get('/api/status').json()['calendar_queue']['phase'], 'error')
        self.assertEqual(self.client.delete('/api/calendar/queue', headers=ORIGIN).status_code, 409)
        self.assertEqual(service.database.get('calendar_move_queue'), queue)

    def test_week_shelf_is_persistent_scoped_and_queued(self):
        service = self.app.state.sync
        service.client = NS()
        payload = {'week':'2026-01-05', 'source':'2026-01-06', 'target':'shelf', 'recipe_id':'r1', 'custom':False, 'move_id':'shelf-1', 'recipe':{'name':'Testrezept'}}
        self.assertEqual(self.client.post('/api/calendar/placement', json=payload).status_code, 403)
        response = self.client.post('/api/calendar/placement', json=payload, headers=ORIGIN)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['items'][0]['target'], 'shelf')
        saved = service.database.get('calendar_move_queue')
        self.assertEqual(saved['shelves'][service.week_collection_owner()]['2026-01-05'][0]['name'], 'Testrezept')
        self.assertEqual(len(self.client.post('/api/calendar/placement', json=payload, headers=ORIGIN).json()['items']), 1)
        moved = {**payload, 'source':'shelf', 'target':'2026-01-09', 'move_id':'shelf-2'}
        self.assertEqual(self.client.post('/api/calendar/placement', json=moved, headers=ORIGIN).status_code, 200)
        saved = service.database.get('calendar_move_queue')
        self.assertEqual(saved['shelves'][service.week_collection_owner()]['2026-01-05'], [])
        self.assertEqual(len(saved['items']), 2)
        self.assertEqual(self.client.post('/api/calendar/placement', json={**payload, 'target':'2026-01-12', 'move_id':'bad'}, headers=ORIGIN).status_code, 409)

    def test_add_local_list_recipe_to_week_shelf_without_calendar_write(self):
        service = self.app.state.sync; service.client = NS()
        collections, recipes = snapshot()
        self.app.state.database.save_snapshot(collections, recipes)
        local = self.app.state.database.create_local_collection('Kochen')
        self.assertTrue(self.app.state.database.set_local_membership(local, 'r1', True))
        payload = {'week':'2026-01-05', 'source':'library', 'target':'shelf', 'recipe_id':'r1', 'custom':False, 'move_id':'library-1', 'recipe':{'name':'Manipuliert'}}
        response = self.client.post('/api/calendar/placement', json=payload, headers=ORIGIN)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['phase'], 'idle')
        shelf = self.app.state.database.get('calendar_move_queue')['shelves'][service.week_collection_owner()]['2026-01-05']
        self.assertEqual(shelf[0]['name'], recipes['r1']['name'])
        self.assertEqual(self.client.post('/api/calendar/placement', json={**payload, 'move_id':'library-2'}, headers=ORIGIN).status_code, 409)
        self.assertEqual(self.client.post('/api/calendar/placement', json={**payload, 'recipe_id':'r2', 'move_id':'library-3'}, headers=ORIGIN).status_code, 409)
        self.assertEqual(self.client.post('/api/calendar/placement', json={**payload, 'target':'2026-01-06', 'move_id':'library-4'}, headers=ORIGIN).status_code, 409)

    def test_preview_adds_collection_recipe_to_shelf_without_calendar_write(self):
        service = self.app.state.sync; service.client = NS()
        collections, recipes = snapshot()
        self.app.state.database.save_snapshot(collections, recipes)
        payload = {'week':'2026-01-05', 'source':'preview', 'target':'shelf', 'recipe_id':'r1', 'custom':False, 'move_id':'preview-1', 'recipe':{'id':'r1','name':'Manipuliert'}}
        self.assertEqual(self.client.post('/api/calendar/placement', json=payload).status_code, 403)
        response = self.client.post('/api/calendar/placement', json=payload, headers=ORIGIN)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['phase'], 'idle')
        shelf = service.database.get('calendar_move_queue')['shelves'][service.week_collection_owner()]['2026-01-05']
        self.assertEqual(shelf[0]['name'], recipes['r1']['name'])
        self.assertEqual(self.client.post('/api/calendar/placement', json={**payload, 'move_id':'preview-2'}, headers=ORIGIN).status_code, 409)
        self.assertEqual(self.client.post('/api/calendar/placement', json={**payload, 'target':'2026-01-06', 'move_id':'preview-3'}, headers=ORIGIN).status_code, 409)

    def test_preview_adds_verified_remote_recipe_and_rejects_account_change(self):
        service = self.app.state.sync; service.client = NS()
        payload = {'week':'2026-01-05', 'source':'preview', 'target':'shelf', 'recipe_id':'remote', 'custom':False, 'move_id':'remote-1', 'recipe':{'name':'Manipuliert'}}
        service.calendar_recipe_details = AsyncMock(return_value={'id':'remote', 'name':'Remote'})
        response = self.client.post('/api/calendar/placement', json=payload, headers=ORIGIN)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['shelf_recipe']['name'], 'Remote')
        self.assertEqual(response.json()['items'], [])
        async def changed_account(identifier):
            service.database.set('account', {'email':'other@example.invalid', 'region':'de'})
            return {'id':identifier, 'name':'Remote'}
        service.calendar_recipe_details = AsyncMock(side_effect=changed_account)
        response = self.client.post('/api/calendar/placement', json={**payload, 'recipe_id':'remote2', 'move_id':'remote-2'}, headers=ORIGIN)
        self.assertEqual(response.status_code, 409)
        self.assertNotIn(service.week_collection_owner(), service.database.get('calendar_move_queue')['shelves'])

    def test_moving_day_recipe_already_in_shelf_preserves_shelf_and_can_undo(self):
        service = self.app.state.sync; service.client = NS()
        self.app.state.database.save_snapshot(*snapshot())
        base = {'week':'2026-01-05', 'target':'shelf', 'recipe_id':'r1', 'custom':False, 'recipe':{'name':'Test'}}
        self.assertEqual(self.client.post('/api/calendar/placement', json={**base, 'source':'preview', 'move_id':'preview-1'}, headers=ORIGIN).status_code, 200)
        response = self.client.post('/api/calendar/placement', json={**base, 'source':'2026-01-06', 'move_id':'merge-1'}, headers=ORIGIN)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['items'][0]['target'], 'trash')
        self.assertIn('not_before', response.json()['items'][0])
        shelf = service.database.get('calendar_move_queue')['shelves'][service.week_collection_owner()]['2026-01-05']
        self.assertEqual(len(shelf), 1)
        self.assertEqual(shelf[0]['id'], 'r1')
        undo = self.client.post('/api/calendar/undo-removal', json={'move_id':'merge-1'}, headers=ORIGIN)
        self.assertEqual(undo.status_code, 200)
        self.assertEqual(undo.json()['items'], [])
        shelf = service.database.get('calendar_move_queue')['shelves'][service.week_collection_owner()]['2026-01-05']
        self.assertEqual(len(shelf), 1)

    def test_week_shelf_deletion_is_local_after_queued_removal(self):
        service = self.app.state.sync; service.client = NS()
        payload = {'week':'2026-01-05', 'source':'2026-01-06', 'target':'shelf', 'recipe_id':'r1', 'custom':False, 'move_id':'shelf-1', 'recipe':{'name':'Test'}}
        self.client.post('/api/calendar/placement', json=payload, headers=ORIGIN)
        response = self.client.post('/api/calendar/placement', json={**payload, 'source':'shelf', 'target':'trash', 'move_id':'shelf-2'}, headers=ORIGIN)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.json()['items']), 1)
        self.assertEqual(service.database.get('calendar_move_queue')['shelves'][service.week_collection_owner()]['2026-01-05'], [])

    def test_undo_removal_cancels_queued_delete_and_restores_shelf(self):
        service = self.app.state.sync; service.client = NS()
        base = {'week':'2026-01-05', 'source':'2026-01-06', 'target':'trash', 'recipe_id':'r1', 'custom':False, 'move_id':'delete-1', 'recipe':{'name':'Test'}}
        self.assertEqual(self.client.post('/api/calendar/placement', json=base, headers=ORIGIN).status_code, 200)
        self.assertEqual(self.client.post('/api/calendar/undo-removal', json={'move_id':'delete-1'}).status_code, 403)
        response = self.client.post('/api/calendar/undo-removal', json={'move_id':'delete-1'}, headers=ORIGIN)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['phase'], 'idle')
        self.assertEqual(self.client.post('/api/calendar/undo-removal', json={'move_id':'delete-1'}, headers=ORIGIN).status_code, 409)
        self.client.post('/api/calendar/placement', json={**base, 'target':'shelf', 'move_id':'shelf-1'}, headers=ORIGIN)
        self.client.post('/api/calendar/placement', json={**base, 'source':'shelf', 'move_id':'delete-2'}, headers=ORIGIN)
        response = self.client.post('/api/calendar/undo-removal', json={'move_id':'delete-2'}, headers=ORIGIN)
        self.assertEqual(response.status_code, 200)
        shelf = service.database.get('calendar_move_queue')['shelves'][service.week_collection_owner()]['2026-01-05']
        self.assertEqual([item['calendar_id'] for item in shelf], ['r1'])
        self.assertEqual(len(response.json()['items']), 1)

    def test_undo_refuses_processing_or_expired_removal(self):
        service = self.app.state.sync; service.client = NS()
        payload = {'week':'2026-01-05', 'source':'2026-01-06', 'target':'trash', 'recipe_id':'r1', 'custom':False, 'move_id':'delete-1', 'recipe':{'name':'Test'}}
        self.client.post('/api/calendar/placement', json=payload, headers=ORIGIN)
        def processing(queue): queue['phase'] = 'processing'; return queue
        service.database.calendar_queue_update(processing)
        self.assertEqual(self.client.post('/api/calendar/undo-removal', json={'move_id':'delete-1'}, headers=ORIGIN).status_code, 409)
        def expired(queue): queue['phase'] = 'waiting'; queue['undo_removals'][0]['expires'] = '2000-01-01T00:00:00+00:00'; return queue
        service.database.calendar_queue_update(expired)
        self.assertEqual(self.client.post('/api/calendar/undo-removal', json={'move_id':'delete-1'}, headers=ORIGIN).status_code, 409)

    def test_week_shopping_uses_queue_shelf_and_never_writes_to_cookidoo(self):
        from datetime import datetime
        class FixedDateTime(datetime):
            @classmethod
            def now(cls, tz=None): return cls(2026, 1, 7, 12, tzinfo=tz)
        def recipe(identifier): return NS(id=identifier, is_custom=False)
        entries = [NS(id='2026-01-06', recipes=[recipe('past'), recipe('moved')], customer_recipe_ids=[]),
                   NS(id='2026-01-07', recipes=[recipe('today')], customer_recipe_ids=[]),
                   NS(id='2026-01-08', recipes=[recipe('removed')], customer_recipe_ids=['own'])]
        service = self.app.state.sync
        client = NS(get_recipes_in_calendar_week=AsyncMock(return_value=entries),
                    add_ingredient_items_for_recipes=AsyncMock())
        service.client = client
        service.database.set('calendar_move_queue', {'owner':service.week_collection_owner(), 'phase':'waiting', 'due':'2099-01-01T00:00:00+00:00', 'error':None,
            'items':[{'source':'2026-01-06','target':'2026-01-09','recipe_id':'moved','custom':False},
                     {'week':'2026-01-05','source':'2026-01-08','target':'trash','recipe_id':'removed','custom':False}],
            'shelves':{service.week_collection_owner():{'2026-01-05':[{'calendar_id':'shelf','custom':False}]}}})
        async def details(_, identifier, custom, pantry):
            return {'id': ('creation:' if custom else '') + identifier, 'name':identifier, 'ingredients':[]}
        with patch('app.sync.datetime', FixedDateTime), patch('app.sync.remote_recipe_snapshot', side_effect=details):
            response = self.client.post('/api/calendar/shopping', json={'day':'2026-01-07'}, headers=ORIGIN)
            again = self.client.post('/api/calendar/shopping', json={'day':'2026-01-07'}, headers=ORIGIN)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['added'], 4)
        self.assertEqual(again.json()['added'], 0)
        self.assertEqual({item['recipe_id'] for item in service.database.cart(service.week_collection_owner())}, {'today','moved','creation:own','shelf'})
        client.add_ingredient_items_for_recipes.assert_not_awaited()
        self.assertEqual(self.client.post('/api/calendar/shopping', json={'day':'2026-01-07'}).status_code, 403)

    def test_week_shopping_does_not_change_cart_when_details_fail(self):
        from datetime import datetime
        class FixedDateTime(datetime):
            @classmethod
            def now(cls, tz=None): return cls(2026, 1, 7, 12, tzinfo=tz)
        service = self.app.state.sync
        service.client = NS(get_recipes_in_calendar_week=AsyncMock(return_value=[
            NS(id='2026-01-07', recipes=[NS(id='r1', is_custom=False), NS(id='r2', is_custom=False)], customer_recipe_ids=[])]))
        with patch('app.sync.datetime', FixedDateTime), patch('app.sync.remote_recipe_snapshot', new=AsyncMock(side_effect=[{'id':'r1'}, RuntimeError('failed')])):
            response = self.client.post('/api/calendar/shopping', json={'day':'2026-01-07'}, headers=ORIGIN)
        self.assertEqual(response.status_code, 502)
        self.assertEqual(service.database.cart(service.week_collection_owner()), [])

    def test_week_shopping_future_week_respects_week_boundaries(self):
        from datetime import datetime
        class FixedDateTime(datetime):
            @classmethod
            def now(cls, tz=None): return cls(2026, 1, 7, 12, tzinfo=tz)
        service = self.app.state.sync
        service.client = NS(get_recipes_in_calendar_week=AsyncMock(return_value=[
            NS(id='2026-01-12', recipes=[NS(id='monday', is_custom=False)], customer_recipe_ids=[]),
            NS(id='2026-01-18', recipes=[NS(id='sunday', is_custom=False)], customer_recipe_ids=[]),
            NS(id='2026-01-19', recipes=[NS(id='next', is_custom=False)], customer_recipe_ids=[])]))
        async def details(_, identifier, custom, pantry):
            return {'id':identifier, 'name':identifier, 'ingredients':[]}
        with patch('app.sync.datetime', FixedDateTime), patch('app.sync.remote_recipe_snapshot', side_effect=details):
            response = self.client.post('/api/calendar/shopping', json={'day':'2026-01-14'}, headers=ORIGIN)
        self.assertEqual(response.json()['added'], 2)
        self.assertEqual({item['recipe_id'] for item in service.database.cart(service.cart_owner())}, {'monday','sunday'})

    def test_week_shopping_past_week_and_uncertain_queue_do_not_write(self):
        from datetime import datetime
        class FixedDateTime(datetime):
            @classmethod
            def now(cls, tz=None): return cls(2026, 1, 7, 12, tzinfo=tz)
        service = self.app.state.sync
        service.client = NS(get_recipes_in_calendar_week=AsyncMock())
        with patch('app.sync.datetime', FixedDateTime):
            response = self.client.post('/api/calendar/shopping', json={'day':'2025-12-29'}, headers=ORIGIN)
            self.assertEqual(response.json()['status'], 'empty')
            service.client.get_recipes_in_calendar_week.assert_not_awaited()
            service.database.set('calendar_move_queue', {'owner':service.week_collection_owner(),'phase':'error','items':[{'source':'2026-01-05','target':'2026-01-06','recipe_id':'r1','custom':False}],'due':None,'error':'unknown'})
            response = self.client.post('/api/calendar/shopping', json={'day':'2026-01-07'}, headers=ORIGIN)
            self.assertEqual(response.status_code, 409)

    def test_recipe_tips_load_and_cache_for_catalog_and_creations(self):
        collections, recipes = snapshot()
        collections[0]['members'].append({'id':'creation:own'})
        recipes['creation:own'] = {'id':'creation:own', 'name':'Eigenes Rezept', 'updated_at':now()}
        self.app.state.database.save_snapshot(collections, recipes)
        client = NS(get_recipe_details=AsyncMock(return_value=NS(notes=['<b>Erster Tipp</b> &amp; mehr'])),
                    get_custom_recipe=AsyncMock(return_value=NS(hints=['Eigener Tipp', 'Noch ein Tipp'])))
        self.app.state.sync.client = client
        self.assertEqual(self.client.get('/api/recipes/r1/tips').json(), {'tips':['Erster Tipp & mehr']})
        self.assertEqual(self.client.get('/api/recipes/creation:own/tips').json(), {'tips':['Eigener Tipp', 'Noch ein Tipp']})
        self.assertEqual(json.loads(self.app.state.database.recipe('r1')['tips_json']), ['Erster Tipp & mehr'])
        self.assertEqual(self.client.get('/api/recipes/r1/tips').json(), {'tips':['Erster Tipp & mehr']})
        client.get_recipe_details.assert_awaited_once_with('r1')
        client.get_custom_recipe.assert_awaited_once_with('own')

    def test_recipe_notes_create_update_delete_and_conflict(self):
        service = self.app.state.sync
        service.client = NS()
        request = AsyncMock(side_effect=[None, {'text':'erste Notiz'}, {'text':'erste Notiz'}, None, {'text':'zweite Notiz'}, {'text':'geändert'}])
        service._recipe_note_request = request
        self.assertEqual(self.client.get('/api/notes/r1').json(), {'text': ''})
        response = self.client.put('/api/notes/r1', headers=ORIGIN, json={'expected':'alte Notiz', 'text':'neuer Text'})
        self.assertEqual(response.status_code, 409)
        self.assertEqual(request.await_count, 2)
        response = self.client.put('/api/notes/r1', headers=ORIGIN, json={'expected':'erste Notiz', 'text':'zweite Notiz'})
        self.assertEqual(response.json(), {'text':'zweite Notiz'})
        self.assertEqual(request.await_args_list[3].args, ('put', 'r1', {'text':'zweite Notiz'}))
        response = self.client.put('/api/notes/r1', headers=ORIGIN, json={'expected':'nicht aktuell', 'text':''})
        self.assertEqual(response.status_code, 409)

    def test_recipe_notes_create_and_delete_are_confirmed(self):
        service = self.app.state.sync
        service.client = NS()
        service._recipe_note_request = AsyncMock(side_effect=[None, None, {'text':'Notiz'}, {'text':'Notiz'}, None, None])
        response = self.client.put('/api/notes/r1', headers=ORIGIN, json={'expected':'', 'text':'Notiz'})
        self.assertEqual(response.json(), {'text':'Notiz'})
        self.assertEqual(service._recipe_note_request.await_args_list[1].args, ('post', 'r1', {'recipeId':'r1', 'text':'Notiz'}))
        response = self.client.put('/api/notes/r1', headers=ORIGIN, json={'expected':'Notiz', 'text':''})
        self.assertEqual(response.json(), {'text':''})
        self.assertEqual(service._recipe_note_request.await_args_list[4].args, ('delete', 'r1'))

    def test_recipe_notes_failure_does_not_report_success(self):
        service = self.app.state.sync
        service.client = NS()
        service._recipe_note_request = AsyncMock(side_effect=[None, RuntimeError('private text')])
        response = self.client.put('/api/notes/r1', headers=ORIGIN, json={'expected':'', 'text':'Notiz'})
        self.assertEqual(response.status_code, 502)
        self.assertNotIn('private text', response.text)
        self.assertEqual(self.client.put('/api/notes/r1', json={'expected':'', 'text':'Notiz'}).status_code, 403)

    def test_custom_note_targets_hints_preserves_recipe_and_checks_conflicts(self):
        service = self.app.state.sync
        state = {'hints':'Tipp eins\nTipp zwei', 'image':'original-image', 'instructions':['step']}
        async def read(identifier):
            return URL('https://cookidoo.de/test'), {'recipeContent':dict(state)}, state['hints']
        async def request(method, url, operation, **kwargs):
            self.assertEqual(method, 'patch')
            self.assertEqual(set(kwargs['json']), {'hints'})
            state['hints'] = kwargs['json']['hints']
        service._read_custom_note_source = AsyncMock(side_effect=read)
        service.client = NS(_request_json=AsyncMock(side_effect=request))
        self.assertEqual(self.client.get('/api/notes/creation:own').json(), {'text':''})
        result = self.client.put('/api/notes/creation:own', headers=ORIGIN, json={'expected':'', 'text':'Erste Zeile\nZweite Zeile'})
        self.assertEqual(result.json(), {'text':'Erste Zeile\nZweite Zeile'})
        self.assertEqual(state['hints'], 'Tipp eins\nTipp zwei\nNotiz: Erste Zeile\nZweite Zeile')
        self.assertEqual(state['image'], 'original-image')
        badge = self.client.get('/api/calendar/badges?notes_only=true&recipe_id=creation:own').json()['items'][0]
        self.assertTrue(badge['has_note'])
        result = self.client.put('/api/notes/creation:own', headers=ORIGIN, json={'expected':'alt', 'text':'anderer Text'})
        self.assertEqual(result.status_code, 409)
        self.assertEqual(service.client._request_json.await_count, 1)
        result = self.client.put('/api/notes/creation:own', headers=ORIGIN, json={'expected':'Erste Zeile\nZweite Zeile', 'text':''})
        self.assertEqual(result.json(), {'text':''})
        self.assertEqual(state['hints'], 'Tipp eins\nTipp zwei\n')

    def test_custom_note_rejects_ambiguous_and_concurrent_hint_changes(self):
        service = self.app.state.sync
        service.client = NS(_request_json=AsyncMock())
        service._read_custom_note_source = AsyncMock(return_value=(URL('https://cookidoo.de/test'), {'recipeContent':{}}, 'Notiz: eins\nNotiz: zwei'))
        self.assertEqual(self.client.get('/api/notes/creation:own').status_code, 409)
        service._read_custom_note_source = AsyncMock(side_effect=[(URL('https://cookidoo.de/test'), {'recipeContent':{}}, 'Tipp'), (URL('https://cookidoo.de/test'), {'recipeContent':{}}, 'Tipp geändert')])
        result = self.client.put('/api/notes/creation:own', headers=ORIGIN, json={'expected':'', 'text':'Text'})
        self.assertEqual(result.status_code, 409)
        service.client._request_json.assert_not_awaited()

    def test_custom_note_unconfirmed_or_changed_recipe_never_reports_success(self):
        service = self.app.state.sync
        url = URL('https://cookidoo.de/test')
        service.client = NS(_request_json=AsyncMock())
        before = (url, {'recipeContent':{'hints':'Tipp', 'image':'original'}}, 'Tipp')
        changed = (url, {'recipeContent':{'hints':'Tipp\nNotiz: Text', 'image':'other'}}, 'Tipp\nNotiz: Text')
        service._read_custom_note_source = AsyncMock(side_effect=[before, before, changed])
        result = self.client.put('/api/notes/creation:own', headers=ORIGIN, json={'expected':'', 'text':'Text'})
        self.assertEqual(result.status_code, 502)
        self.assertNotIn('other', result.text)

    def test_recipe_note_transport_uses_configured_cookidoo_origin(self):
        class Response:
            def __init__(self, status, payload=None): self.status, self.payload = status, payload
            async def __aenter__(self): return self
            async def __aexit__(self, *args): pass
            async def json(self): return self.payload
        responses = [Response(404), Response(201, {'text':'Test'}), Response(200, {'text':'Test'})]
        calls = []
        def request(method, url, **kwargs):
            calls.append((method, str(url), kwargs))
            return responses.pop(0)
        session = NS(request=request)
        self.app.state.sync.client = NS(api_endpoint=URL('https://cookidoo.de'), _ensure_token=AsyncMock(), _api_headers={'Authorization':'Bearer fixture'}, _session=session)
        response = self.client.put('/api/notes/r1', headers=ORIGIN, json={'expected':'', 'text':'Test'})
        self.assertEqual(response.json(), {'text':'Test'})
        self.assertEqual([call[0] for call in calls], ['get', 'post', 'get'])
        self.assertEqual(calls[0][1], 'https://cookidoo.de/recipe-notes/de-DE/recipes/r1')
        self.assertEqual(calls[1][1], 'https://cookidoo.de/recipe-notes/de-DE/recipes')
        self.assertTrue(all(call[2]['allow_redirects'] is False for call in calls))

    def test_google_key_is_encrypted_write_only_and_removable(self):
        key = 'test-google-secret-unique-123'
        self.assertFalse(self.client.get('/api/status').json()['google_api_key_set'])
        self.assertEqual(self.client.post('/api/google-api-key', json={'key': key}, headers={'Origin': 'https://evil.example'}).status_code, 403)
        response = self.client.post('/api/google-api-key', json={'key': key}, headers=ORIGIN)
        self.assertEqual(response.json(), {'ok': True})
        self.assertNotIn(key, response.text)
        encrypted = (Path(self.tmp.name) / 'google-api-key.enc').read_bytes()
        self.assertNotIn(key.encode(), encrypted)
        self.assertEqual(Vault(self.tmp.name, 'google-api-key.enc').read()['key'], key)
        self.assertTrue(self.client.get('/api/status').json()['google_api_key_set'])
        self.assertNotIn(key, self.client.get('/api/status').text)
        self.assertNotIn(key, self.client.get('/api/export').text)
        self.assertEqual(self.client.get('/api/google-api-key').status_code, 405)
        replacement = 'new-test-secret-456'
        self.assertEqual(self.client.post('/api/google-api-key', json={'key': replacement}, headers=ORIGIN).json(), {'ok': True})
        self.assertEqual(Vault(self.tmp.name, 'google-api-key.enc').read()['key'], replacement)
        invalid = self.client.post('/api/google-api-key', json={'key': 'test secret'}, headers=ORIGIN)
        self.assertEqual(invalid.status_code, 400)
        self.assertNotIn('test secret', invalid.text)
        self.assertEqual(self.client.delete('/api/google-api-key', headers=ORIGIN).status_code, 200)
        self.assertFalse(self.client.get('/api/status').json()['google_api_key_set'])
        self.assertFalse((Path(self.tmp.name) / 'google-api-key.enc').exists())

    def test_featured_recipe_changes_on_new_day_and_manual_shuffle(self):
        database = self.app.state.database
        self.assertIsNone(database.featured_recipe(day='2026-10-31')['recipe'])
        database.save_snapshot(*snapshot())
        first = database.featured_recipe(day='2026-10-31')
        self.assertTrue(first['can_shuffle'])
        self.assertEqual(first['recipe']['id'], database.featured_recipe(day='2026-10-31')['recipe']['id'])
        second = database.featured_recipe(refresh=True, day='2026-10-31')
        self.assertNotEqual(first['recipe']['id'], second['recipe']['id'])
        self.assertEqual(second['recipe']['id'], database.featured_recipe(day='2026-10-31')['recipe']['id'])
        next_day = database.featured_recipe(day='2026-11-01')
        self.assertNotEqual(second['recipe']['id'], next_day['recipe']['id'])
        self.assertEqual(next_day['recipe']['id'], database.featured_recipe(day='2026-11-01')['recipe']['id'])
        self.assertEqual(self.client.post('/api/featured-recipe/shuffle', json={}, headers={'Origin':'https://evil.example'}).status_code, 403)

    def test_featured_recipe_handles_empty_single_and_grouped_versions(self):
        database = self.app.state.database
        collections, recipes = snapshot()
        collections = [collections[0]]
        collections[0]['members'] = [{'id':'r1'}, {'id':'creation:c1'}]
        recipes = {'r1':recipes['r1'], 'creation:c1':{'id':'creation:c1','name':'Variante','source_url':'','origin_recipe_id':'r1','updated_at':now()}}
        database.save_snapshot(collections, recipes)
        result = database.featured_recipe(day='2026-10-31')
        self.assertFalse(result['can_shuffle'])
        self.assertEqual(result['recipe']['id'], 'r1')
        self.assertEqual(database.featured_recipe(refresh=True, day='2026-10-31')['recipe']['id'], 'r1')

    def test_library_search_membership_export_and_private_images(self):
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
        self.assertEqual(image.headers['cache-control'], 'private, max-age=86400')
        self.assertEqual(self.client.get('/api/status').headers['cache-control'], 'no-store')
        self.assertEqual(self.client.get('/api/images/' + 'b' * 40 + '.webp').headers['cache-control'], 'no-store')

    def test_recipe_thumbnails_are_smaller_cached_and_keep_original(self):
        filename = 'c' * 40 + '.webp'
        original = Path(self.tmp.name) / 'images' / filename
        Image.new('RGB', (960, 640), 'green').save(original, 'WEBP')
        response = self.client.get('/api/images/' + filename + '?size=thumb')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers['cache-control'], 'private, max-age=86400')
        with Image.open(io.BytesIO(response.content)) as preview:
            self.assertEqual(preview.format, 'WEBP')
            self.assertEqual(preview.size, (480, 320))
        with Image.open(original) as source:
            self.assertEqual(source.size, (960, 640))
        thumbnail = original.parent / 'thumbnails' / filename
        modified = thumbnail.stat().st_mtime_ns
        self.assertEqual(self.client.get('/api/images/' + filename + '?size=thumb').content, response.content)
        self.assertEqual(thumbnail.stat().st_mtime_ns, modified)
        self.assertEqual(self.client.get('/api/images/' + filename + '?size=invalid').status_code, 422)

    def test_calendar_images_are_fetched_only_when_requested(self):
        service = self.app.state.sync
        url = 'https://assets.tmecosys.com/week-image.jpg'
        item = NS(id='external', name='Extern', image=url, thumbnail=None)
        service.client = NS(get_recipes_in_calendar_week=AsyncMock(return_value=[NS(id='2026-01-05', recipes=[item], customer_recipe_ids=[])]))
        async def fetch(source, http):
            filename = hashlib.sha256(source.encode()).hexdigest()[:40] + '.webp'
            Image.new('RGB', (960, 640), 'green').save(service.images / filename, 'WEBP')
            return filename
        service.cache_image = AsyncMock(side_effect=fetch)
        response = self.client.get('/api/calendar/week?day=2026-01-05')
        self.assertEqual(response.status_code, 200)
        filename = response.json()['days'][0]['recipes'][0]['image_file']
        service.cache_image.assert_not_awaited()
        image = self.client.get('/api/images/' + filename + '?size=thumb')
        self.assertEqual(image.status_code, 200)
        with Image.open(io.BytesIO(image.content)) as preview:
            self.assertEqual(preview.size, (480, 320))
        service.cache_image.assert_awaited_once()
        self.assertEqual(self.client.get('/api/images/' + filename).status_code, 200)
        service.cache_image.assert_awaited_once()

    def test_calendar_image_reference_rejects_untrusted_urls(self):
        service = self.app.state.sync
        for url in ('http://127.0.0.1/secret', 'https://evil.example/photo', 'https://user:pass@assets.tmecosys.com/photo', 'https://assets.tmecosys.com:444/photo'):
            self.assertIsNone(service.calendar_image_reference(url))

    def test_snapshot_failure_preserves_previous_library(self):
        database = self.app.state.database
        database.save_snapshot(*snapshot())
        bad = [{'id':'custom:bad','source_id':'bad','kind':'custom','name':'bad','members':[{'id':'missing'}]}]
        with self.assertRaises(Exception):
            database.save_snapshot(bad, {})
        self.assertEqual(database.stats()['recipes'], 2)
        self.assertEqual(database.stats()['collections'], 2)

    def test_header_search_ranks_title_before_ingredients_and_preserves_filters(self):
        collections, recipes = snapshot()
        recipes['r1'].update(name='Zwiebelkuchen', servings='4', ingredients_json=json.dumps([{'name':'Salz'}]))
        recipes['r2'].update(name='Apfelsuppe', servings='2', ingredients_json=json.dumps([{'name':'Zwiebeln'}]))
        recipes['r3'] = {'id':'r3', 'name':'Anderes Gericht', 'source_url':'', 'servings':'4', 'ingredients_json':json.dumps([{'name':'Zwiebeln'}, {'name':'Salz'}]), 'updated_at':now()}
        recipes['creation:c1'] = {'id':'creation:c1', 'name':'Variante', 'source_url':'', 'origin_recipe_id':'r1', 'servings':'2', 'ingredients_json':json.dumps([{'name':'Zwiebeln'}]), 'updated_at':now()}
        collections[0]['members'].extend([{'id':'r3'}, {'id':'creation:c1'}])
        self.app.state.database.save_snapshot(collections, recipes)
        def request(**params):
            return self.client.get('/api/recipes', params={'q':'zwiebel', **params}).json()
        self.assertEqual([r['id'] for r in request()['items']], ['r1', 'r3', 'r2'])
        self.assertEqual([r['id'] for r in request(offset=1, limit=1)['items']], ['r3'])
        self.assertEqual([r['id'] for r in request(ingredient='Salz')['items']], ['r1', 'r3'])
        self.assertEqual({r['id']:r['matches'] for r in request(collection='custom:list1', show_all='true', min_servings=4)['items']}, {'r1':True, 'r3':True, 'r2':False})
        self.assertEqual([r['id'] for r in request(q='onion')['items']], ['r3', 'r2', 'creation:c1'])
        self.assertEqual(request(q='%')['total'], 0)

    def test_local_lists_and_membership_survive_cookidoo_sync(self):
        database = self.app.state.database
        database.save_snapshot(*snapshot())
        response = self.client.post('/api/local-collections', json={'name': '  Wochenplan  '}, headers=ORIGIN)
        self.assertEqual(response.status_code, 200)
        local_id = response.json()['id']
        path = f'/api/local-collections/{local_id}/recipes/r1'
        self.assertEqual(self.client.put(path, json={'present': True}, headers=ORIGIN).status_code, 200)
        self.assertEqual(self.client.put('/api/local-collections/custom:list1/recipes/r2', json={'present': True}, headers=ORIGIN).status_code, 404)
        self.assertEqual(self.client.post('/api/local-collections', json={'name': '   '}, headers=ORIGIN).status_code, 400)
        database.save_snapshot([], {})
        self.assertEqual([(c['name'], c['recipe_count']) for c in database.collections()], [('Wochenplan', 1)])
        self.assertEqual(database.recipe('r1')['name'], 'Käse-Spätzle')
        self.assertIsNone(database.recipe('r2'))
        self.assertEqual(self.client.put(path, json={'present': False}, headers=ORIGIN).status_code, 200)
        self.assertEqual(database.collections()[0]['recipe_count'], 0)
        self.assertEqual(self.client.post('/api/local-collections', json={'name': 'X'}, headers={'Origin': 'https://evil.example'}).status_code, 403)

    def test_recipes_outside_a_list_are_searchable_and_paginated(self):
        database = self.app.state.database
        database.save_snapshot(*snapshot())
        local_id = database.create_local_collection('Plan')
        database.set_local_membership(local_id, 'r1', True)
        response = self.client.get('/api/recipes', params={'exclude_collection': local_id, 'limit': 1}).json()
        self.assertEqual(response['total'], 1)
        self.assertEqual([item['id'] for item in response['items']], ['r2'])
        self.assertEqual(self.client.get('/api/recipes', params={'exclude_collection': local_id, 'q': 'KÄSE'}).json()['total'], 0)
        self.assertEqual(self.client.get('/api/recipes', params={'exclude_collection': local_id, 'offset': 1, 'limit': 1}).json()['items'], [])
        database.set_local_membership(local_id, 'r2', True)
        self.assertEqual(self.client.get('/api/recipes', params={'exclude_collection': local_id}).json()['total'], 0)

    def test_recipe_list_filters_and_sorts(self):
        collections, recipes = snapshot()
        recipes['r1'].update(servings='4', ingredients_json=json.dumps([{'name':'Tomaten'}, {'name':'Salz'}]))
        recipes['r2'].update(servings='2', ingredients_json=json.dumps([{'name':'Tomaten'}]))
        recipes['r3'] = {'id':'r3', 'name':'Ohne Details', 'source_url':'', 'updated_at':now()}
        collections[0]['members'].append({'id':'r3'})
        self.app.state.database.save_snapshot(collections, recipes)
        def request(**params):
            return self.client.get('/api/recipes', params={'collection':'custom:list1', **params}).json()
        self.assertEqual([r['id'] for r in request(sort='servings')['items']], ['r2', 'r1', 'r3'])
        self.assertEqual([r['id'] for r in request(sort='ingredients')['items']], ['r2', 'r1', 'r3'])
        self.assertEqual([r['id'] for r in request(sort='time')['items']], ['r2', 'r1', 'r3'])
        self.assertEqual([r['id'] for r in request(ingredient='TOMAT', min_servings=3, max_minutes=30)['items']], ['r1'])
        self.assertEqual(request(ingredient='Tomat', max_minutes=14)['total'], 0)
        self.assertEqual(request(ingredient='%')['total'], 0)
        self.assertEqual([r['id'] for r in request(ingredient='tomat', sort='time', offset=1, limit=1)['items']], ['r1'])
        self.assertEqual(self.client.get('/api/recipes', params={'max_minutes':0}).status_code, 422)

    def test_list_filter_options_and_multiple_ingredients(self):
        collections, recipes = snapshot()
        recipes['r1'].update(servings='4', ingredients_json=json.dumps([{'name':'Chicken'}, {'name':'Chili, gemahlen'}]))
        recipes['r2'].update(servings='2', ingredients_json=json.dumps([{'name':'Chicken'}]))
        self.app.state.database.save_snapshot(collections, recipes)
        response = self.client.get('/api/collections/custom:list1/filter-options')
        self.assertEqual(response.status_code, 200)
        options = response.json()
        self.assertEqual(options['ingredients'], ['Chili', 'Hähnchen'])
        self.assertEqual(options['servings'], [2, 4])
        self.assertEqual(options['minutes'], [15, 30])
        scoped = self.client.get('/api/collections/managed:list2/filter-options').json()
        self.assertEqual(scoped['servings'], [4])
        params = [('collection','custom:list1'), ('ingredient','Chicken'), ('ingredient','Chili, gemahlen')]
        result = self.client.get('/api/recipes', params=params).json()
        self.assertEqual([item['id'] for item in result['items']], ['r1'])
        self.assertEqual(self.client.get('/api/collections/missing/filter-options').status_code, 404)
        self.assertEqual(self.client.get('/api/recipes', params=[('ingredient', 'x')] * 21).status_code, 400)

    def test_list_filter_can_keep_nonmatching_recipes_visible(self):
        collections, recipes = snapshot()
        recipes['r1'].update(servings='4', ingredients_json=json.dumps([{'name':'Chicken'}, {'name':'Chili'}]))
        recipes['r2'].update(servings='2', ingredients_json=json.dumps([{'name':'Chicken'}]))
        self.app.state.database.save_snapshot(collections, recipes)
        params = [('collection','custom:list1'), ('show_all','true'), ('ingredient','Chicken'), ('ingredient','Chili')]
        result = self.client.get('/api/recipes', params=params).json()
        self.assertEqual((result['total'], result['match_total']), (2, 1))
        self.assertEqual({item['id']:item['matches'] for item in result['items']}, {'r1':True, 'r2':False})
        page = self.client.get('/api/recipes', params=params + [('offset','1'), ('limit','1')]).json()
        self.assertEqual((page['total'], page['match_total'], len(page['items'])), (2, 1, 1))
        none = self.client.get('/api/recipes', params={'collection':'custom:list1', 'show_all':'true', 'max_minutes':1}).json()
        self.assertEqual((none['total'], none['match_total']), (2, 0))
        self.assertTrue(all(item['matches'] is False for item in none['items']))
        ordinary = self.client.get('/api/recipes', params={'collection':'custom:list1', 'ingredient':'Chili'}).json()
        self.assertEqual((ordinary['total'], ordinary['match_total']), (1, 1))

    def test_candidate_search_preserves_results_and_applies_list_filters(self):
        database = self.app.state.database
        collections, recipes = snapshot()
        recipes['r1'].update(servings='4', ingredients_json=json.dumps([{'name':'Salz'}]))
        recipes['r2'].update(servings='2', ingredients_json=json.dumps([{'name':'Salz'}]))
        recipes['r3'] = {'id':'r3', 'name':'Cremesuppe', 'source_url':'', 'servings':'4', 'total_seconds':1200, 'ingredients_json':json.dumps([{'name':'Salz'}, {'name':'Tomaten'}]), 'updated_at':now()}
        collections[0]['members'].append({'id':'r3'})
        database.save_snapshot(collections, recipes)
        local_id = database.create_local_collection('Plan')
        database.set_local_membership(local_id, 'r1', True)
        params = [('exclude_collection',local_id), ('show_all','true'), ('ingredient','Salz'), ('ingredient','Tomaten'), ('min_servings','4'), ('max_minutes','20')]
        result = self.client.get('/api/recipes', params=params).json()
        self.assertEqual((result['total'], result['match_total']), (2, 1))
        self.assertEqual({item['id']:item['matches'] for item in result['items']}, {'r2':False, 'r3':True})
        searched = self.client.get('/api/recipes', params=params + [('candidate_q','Cremesuppe')]).json()
        self.assertEqual((searched['total'], searched['match_total']), (1, 1))
        searched_missing = self.client.get('/api/recipes', params=params + [('candidate_q','50%')]).json()
        self.assertEqual((searched_missing['total'], searched_missing['match_total']), (1, 0))
        page = self.client.get('/api/recipes', params=params + [('limit','1'),('offset','1')]).json()
        self.assertEqual((page['total'], page['match_total'], len(page['items'])), (2, 1, 1))

    def test_grouped_recipe_uses_the_matching_list_version(self):
        collections, recipes = snapshot()
        recipes['r1'].update(servings='2')
        recipes['creation:c1'] = {'id':'creation:c1', 'name':'Version', 'source_url':'', 'origin_recipe_id':'r1', 'servings':'4', 'updated_at':now()}
        collections[0]['members'].append({'id':'creation:c1'})
        self.app.state.database.save_snapshot(collections, recipes)
        result = self.client.get('/api/recipes', params={'collection':'custom:list1', 'min_servings':4, 'show_all':'true'}).json()
        self.assertEqual((result['total'], result['match_total']), (2, 1))
        match = next(item for item in result['items'] if item['matches'])
        self.assertEqual(match['id'], 'creation:c1')

    def test_recipe_preview_shows_servings_for_all_available_versions(self):
        collections, recipes = snapshot()
        recipes['r1']['servings'] = '4'
        recipes['creation:c1'] = {'id':'creation:c1', 'name':'Version', 'source_url':'', 'origin_recipe_id':'r1', 'servings':'2', 'updated_at':now()}
        recipes['creation:c2'] = {'id':'creation:c2', 'name':'Version 2', 'source_url':'', 'origin_recipe_id':'r1', 'servings':'2', 'updated_at':now()}
        collections.append({'id':'creations:default', 'source_id':'creations', 'kind':'creations', 'name':'Meine Kreationen', 'members':[{'id':'creation:c1'}, {'id':'creation:c2'}]})
        self.app.state.database.save_snapshot(collections, recipes)
        bookmark = self.client.get('/api/recipes', params={'collection':'custom:list1'}).json()
        original = next(item for item in bookmark['items'] if item['id'] == 'r1')
        self.assertEqual(original['version_servings'], ['4', '2'])
        creations = self.client.get('/api/recipes', params={'collection':'creations:default'}).json()
        self.assertEqual(creations['items'][0]['version_servings'], ['4', '2'])
        self.assertEqual(next(item for item in bookmark['items'] if item['id'] == 'r2')['version_servings'], [])

    def test_versions_are_grouped_and_local_memberships_cover_the_family(self):
        database = self.app.state.database
        collections, recipes = snapshot()
        recipes['creation:c1'] = {'id': 'creation:c1', 'name': 'Käse-Spätzle', 'source_url': 'https://cookidoo.de/', 'origin_recipe_id': 'r1', 'servings': '2', 'updated_at': now()}
        collections.append({'id': 'creations:default', 'source_id': 'creations', 'kind': 'creations', 'name': 'Meine Kreationen', 'members': [{'id': 'creation:c1'}]})
        database.save_snapshot(collections, recipes)
        self.assertEqual(database.recipes()['total'], 2)
        self.assertEqual(len(database.recipe('r1')['versions']), 2)
        self.assertEqual(len(database.recipe('creation:c1')['versions']), 2)
        local = database.create_local_collection('Plan')
        self.assertTrue(database.set_local_membership(local, 'creation:c1', True))
        self.assertTrue(database.set_local_membership(local, 'r1', True))
        self.assertEqual(database.recipes(collection=local)['total'], 1)
        self.assertEqual(database.recipes(exclude_collection=local)['total'], 1)
        self.assertIn(local, [c['id'] for c in database.recipe('r1')['collections']])
        self.assertTrue(database.set_local_membership(local, 'r1', False))
        self.assertEqual(database.recipes(collection=local)['total'], 0)

    def test_delete_local_collection_preserves_recipe_and_cannot_delete_cookidoo(self):
        db = self.app.state.database
        db.save_snapshot(*snapshot())
        local = self.client.post('/api/local-collections', json={'name':'Testliste'}, headers=ORIGIN).json()['id']
        self.client.put(f'/api/local-collections/{local}/recipes/r1', json={'present':True}, headers=ORIGIN)
        self.assertEqual(self.client.delete(f'/api/local-collections/{local}').status_code, 403)
        self.assertEqual(self.client.delete('/api/local-collections/custom:list1', headers=ORIGIN).status_code, 404)
        self.assertEqual(self.client.delete(f'/api/local-collections/{local}', headers=ORIGIN).status_code, 200)
        self.assertIsNotNone(db.recipe('r1'))
        self.assertTrue(any(item['id'] == 'custom:list1' for item in db.collections()))
        self.assertFalse(any(item['id'] == local for item in db.collections()))

    def test_delete_pantry_category_removes_only_its_items_and_stays_deleted(self):
        db = self.app.state.database
        categories = db.pantry()['categories']
        first, second = categories[0]['id'], categories[1]['id']
        db.save_pantry_item(first, 'Salz', '')
        db.save_pantry_item(second, 'Zwiebel', '')
        self.assertEqual(self.client.delete(f'/api/pantry/categories/{first}').status_code, 403)
        self.assertEqual(self.client.delete(f'/api/pantry/categories/{first}', headers=ORIGIN).status_code, 200)
        self.assertEqual([item['name'] for item in db.pantry()['items']], ['Zwiebel'])
        self.assertEqual(self.client.delete(f'/api/pantry/categories/{first}', headers=ORIGIN).status_code, 404)
        for category in db.pantry()['categories']:
            self.assertEqual(self.client.delete(f"/api/pantry/categories/{category['id']}", headers=ORIGIN).status_code, 200)
        self.assertEqual(Database(self.tmp.name).pantry()['categories'], [])

    def test_spaghetti_noodles_and_pasta_are_equivalent(self):
        for recipe_ingredient in ('Spaghetti', 'Nudeln', 'Pasta'):
            for pantry_ingredient in ('Spaghetti', 'Nudeln', 'Pasta'):
                self.assertTrue(ingredient_available(recipe_ingredient, [pantry_ingredient]))
                self.assertEqual(ingredient_group_key(recipe_ingredient), ingredient_group_key(pantry_ingredient))
        self.assertFalse(ingredient_available('Spaghettikürbis', ['Nudeln']))

    def test_pantry_categories_items_export_and_sync_independence(self):
        pantry = self.client.get('/api/pantry').json()
        spices = next(c for c in pantry['categories'] if c['name'] == 'Gewürze')
        created = self.client.post('/api/pantry/items', json={'name': ' Paprika ', 'category_id': spices['id'], 'quantity': ' 2 Gläser '}, headers=ORIGIN)
        self.assertEqual(created.status_code, 200)
        item_id = created.json()['id']
        self.assertEqual(self.client.post('/api/pantry/items', json={'name': 'paprika', 'category_id': spices['id']}, headers=ORIGIN).status_code, 409)
        category = self.client.post('/api/pantry/categories', json={'name': 'Tee'}, headers=ORIGIN)
        self.assertEqual(category.status_code, 200)
        self.assertEqual(self.client.post('/api/pantry/categories', json={'name': 'tee'}, headers=ORIGIN).status_code, 409)
        updated = self.client.put(f'/api/pantry/items/{item_id}', json={'name': 'Paprika edelsüß', 'category_id': category.json()['id'], 'quantity': '1 Glas'}, headers=ORIGIN)
        self.assertEqual(updated.status_code, 200)
        self.app.state.database.save_snapshot(*snapshot())
        items = self.client.get('/api/pantry').json()['items']
        self.assertEqual([(i['name'], i['quantity']) for i in items], [('Paprika edelsüß', '1 Glas')])
        self.assertEqual(self.client.get('/api/export').json()['pantry']['items'], items)
        self.assertEqual(self.client.delete(f'/api/pantry/items/{item_id}', headers={'Origin': 'https://evil.example'}).status_code, 403)
        self.assertEqual(self.client.delete(f'/api/pantry/items/{item_id}', headers=ORIGIN).status_code, 200)
        self.assertEqual(self.client.get('/api/pantry').json()['items'], [])
        self.assertEqual(self.client.post('/api/pantry/items', json={'name': '  ', 'category_id': spices['id']}, headers=ORIGIN).status_code, 400)

    def test_pantry_category_order_persists_and_items_remain_alphabetical(self):
        before = self.client.get('/api/pantry').json()
        category_ids = [c['id'] for c in before['categories']]
        category = category_ids[0]
        for name in ('Zimt', 'Anis'):
            self.assertEqual(self.client.post('/api/pantry/items', json={'name':name, 'category_id':category}, headers=ORIGIN).status_code, 200)
        reordered = list(reversed(category_ids))
        response = self.client.put('/api/pantry/categories/order', json={'category_ids':reordered}, headers=ORIGIN)
        self.assertEqual(response.status_code, 200)
        result = self.client.get('/api/pantry').json()
        self.assertEqual([c['id'] for c in result['categories']], reordered)
        self.assertEqual([item['name'] for item in result['items']], ['Anis','Zimt'])
        self.app.state.database.save_snapshot(*snapshot())
        self.assertEqual([c['id'] for c in self.client.get('/api/pantry').json()['categories']], reordered)
        self.assertEqual(self.client.put('/api/pantry/categories/order', json={'category_ids':reordered[:-1]}, headers=ORIGIN).status_code, 409)
        self.assertEqual(self.client.put('/api/pantry/categories/order', json={'category_ids':reordered[:-1]+[reordered[0]]}, headers=ORIGIN).status_code, 409)
        self.assertEqual(self.client.put('/api/pantry/categories/order', json={'category_ids':category_ids}, headers={'Origin':'https://evil.example'}).status_code, 403)
        self.assertEqual([c['id'] for c in self.client.get('/api/pantry').json()['categories']], reordered)

    def test_ingredient_suggestions_and_pantry_links_survive_sync(self):
        database = self.app.state.database
        collections, recipes = snapshot()
        recipes['r1']['ingredients_json'] = json.dumps([{'name':'Möhren', 'description':'100 g', 'preparation':', gewürfelt'}, {'name':'Salz', 'description':'1 TL'}], ensure_ascii=False)
        recipes['r2']['ingredients_json'] = json.dumps(['100 g Möhren, in Stücken', '½ TL Salz und etwas mehr', '2 Eier'], ensure_ascii=False)
        database.save_snapshot(collections, recipes)
        suggestions = self.client.get('/api/ingredients/suggestions', params={'q':'möh'}).json()['items']
        self.assertEqual(len(suggestions), 1)
        self.assertEqual(suggestions[0]['name'], 'Karotten')
        self.assertEqual(suggestions[0]['recipe_count'], 2)
        identifier = suggestions[0]['id']
        category = self.client.get('/api/pantry').json()['categories'][0]['id']
        payload = {'name':'Karotten', 'category_id':category, 'quantity':'500 g', 'ingredient_id':identifier}
        self.assertEqual(self.client.post('/api/pantry/items', json=payload, headers=ORIGIN).status_code, 200)
        self.assertEqual(self.client.post('/api/pantry/items', json={**payload, 'name':'Zwiebeln'}, headers=ORIGIN).status_code, 409)
        database.save_snapshot(collections, recipes)
        item = self.client.get('/api/pantry').json()['items'][0]
        self.assertEqual((item['ingredient_id'], item['quantity']), (identifier, '500 g'))
        self.assertEqual(self.client.get('/api/ingredients/suggestions', params={'q':'möH'}).json()['items'][0]['id'], identifier)
        exported = self.client.get('/api/export').json()
        names = {row['id']:row['name'] for row in exported['ingredient_catalog']}
        self.assertTrue(any(ingredient_group_key(names[r['ingredient_id']]) == ingredient_group_key(item['name']) and '100 g' in r['original_json'] for r in exported['recipe_ingredients']))

    def test_freely_written_ingredients_keep_distinct_names(self):
        self.assertEqual(ingredient_name('½ TL Salz und etwas mehr'), 'Salz')
        self.assertEqual(ingredient_name('100 g Möhren, in Stücken'), 'Möhren')
        self.assertEqual(ingredient_name('2 Eier'), 'Eier')
        self.assertEqual(ingredient_name({'name':'Olivenöl','description':'40 g'}), 'Olivenöl')
        self.assertNotEqual(ingredient_name('1 EL Olivenöl'), ingredient_name('1 EL Öl'))

    def test_ingredient_choices_group_broth_variants_without_losing_recipe_details(self):
        database = self.app.state.database
        collections, recipes = snapshot()
        original = [{'name':'Gewürzpaste für Gemüsebrühe, selbst gemacht'}, {'name':'Hühnerbrühe'}]
        recipes['r1']['ingredients_json'] = json.dumps(original, ensure_ascii=False)
        recipes['r2']['ingredients_json'] = json.dumps([{'name':'Gemüsebouillon Paste'}, {'name':'Gemüsebrühe (für 0,5 l)'}], ensure_ascii=False)
        database.save_snapshot(collections, recipes)
        options = self.client.get('/api/collections/custom:list1/filter-options').json()['ingredients']
        self.assertEqual(options.count('Gemüsebrühe'), 1)
        self.assertIn('Hühnerbrühe', options)
        matches = self.client.get('/api/recipes', params={'collection':'custom:list1', 'ingredient':'Gemüsebrühe'}).json()
        self.assertEqual({item['id'] for item in matches['items']}, {'r1', 'r2'})
        suggestions = self.client.get('/api/ingredients/suggestions', params={'q':'bouillon'}).json()['items']
        self.assertEqual([(s['name'], s['recipe_count']) for s in suggestions], [('Gemüsebrühe', 2)])
        category = self.client.get('/api/pantry').json()['categories'][0]['id']
        self.assertEqual(self.client.post('/api/pantry/items', json={'name':'Gemüsebrühe','ingredient_id':suggestions[0]['id'],'category_id':category}, headers=ORIGIN).status_code, 200)
        detail = self.client.get('/api/recipes/r1').json()
        self.assertEqual(json.loads(detail['ingredients_json']), original)
        self.assertTrue(detail['ingredient_availability']['0'])
        self.assertFalse(detail['ingredient_availability']['1'])
        self.assertEqual(ingredient_display_name('Süßkartoffeln'), 'Süßkartoffeln')
        self.assertNotEqual(ingredient_display_name('Hühnerbrühe'), ingredient_display_name('Gemüsebrühe'))

    def test_recipe_ingredient_availability_tracks_pantry(self):
        database = self.app.state.database
        collections, recipes = snapshot()
        recipes['r1']['ingredients_json'] = json.dumps([{'name':'Möhren','description':'100 g'}, {'name':'Salz','description':'1 TL'}, {'description':'unbekannt'}], ensure_ascii=False)
        recipes['r2']['ingredients_json'] = json.dumps(['200 g Salz'], ensure_ascii=False)
        database.save_snapshot(collections, recipes)
        self.assertEqual(self.client.get('/api/recipes/r1').json()['ingredient_availability'], {'0': False, '1': False})
        category = self.client.get('/api/pantry').json()['categories'][0]['id']
        created = self.client.post('/api/pantry/items', json={'name':'salz', 'category_id':category, 'quantity':''}, headers=ORIGIN)
        self.assertEqual(created.status_code, 200)
        self.assertEqual(self.client.get('/api/recipes/r1').json()['ingredient_availability'], {'0': False, '1': True})
        self.assertEqual(self.client.get('/api/recipes/r2').json()['ingredient_availability'], {'0': True})
        self.client.delete(f"/api/pantry/items/{created.json()['id']}", headers=ORIGIN)
        self.assertFalse(self.client.get('/api/recipes/r1').json()['ingredient_availability']['1'])

    def test_recipe_availability_matches_spice_variants_and_water(self):
        database = self.app.state.database
        collections, recipes = snapshot()
        recipes['r1']['ingredients_json'] = json.dumps([{'name':'Kreuzkümmel (Cumin), gemahlen'}, {'name':'Wasser'}, {'name':'Paprika'}, {'name':'Kümmel'}, {'name':'Wasser und mehr zum Kochen der Nudeln'}], ensure_ascii=False)
        database.save_snapshot(collections, recipes)
        category = self.client.get('/api/pantry').json()['categories'][0]['id']
        for name in ('Kreuzkümmel', 'Paprika edelsüß'):
            self.assertEqual(self.client.post('/api/pantry/items', json={'name':name, 'category_id':category}, headers=ORIGIN).status_code, 200)
        self.assertEqual(self.client.get('/api/recipes/r1').json()['ingredient_availability'], {'0': True, '1': True, '2': False, '3': False, '4': True})
        self.assertTrue(ingredient_available('Paprikapulver, edelsüß', ['Paprika edelsüß']))
        self.assertTrue(ingredient_available('Muskat', ['Muskatnuss']))
        self.assertTrue(ingredient_available('Muskatnuss, gemahlen', ['Muskat']))
        self.assertTrue(ingredient_available('Pfeffer, gemahlen', ['Schwarzer Pfeffer']))
        self.assertFalse(ingredient_available('rote Pfefferkörner', ['Schwarzer Pfeffer']))
        self.assertFalse(ingredient_available('Kokoswasser', []))
        self.assertTrue(ingredient_available('heißes Wasser', []))

    def test_starch_and_cornstarch_are_equivalent_in_both_directions(self):
        database = self.app.state.database
        collections, recipes = snapshot()
        recipes['r1']['ingredients_json'] = json.dumps([{'name':'Stärke'}, {'name':'Speisestärke'}, {'name':'Kartoffelstärke'}], ensure_ascii=False)
        database.save_snapshot(collections, recipes)
        category = self.client.get('/api/pantry').json()['categories'][0]['id']
        self.client.post('/api/pantry/items', json={'name':'Speisestärke', 'category_id':category}, headers=ORIGIN)
        self.assertEqual(self.client.get('/api/recipes/r1').json()['ingredient_availability'], {'0':True, '1':True, '2':False})
        self.assertTrue(ingredient_available('Speisestärke', ['Stärke']))

    def test_bio_vanilla_matches_vanilla_extract_without_matching_other_vanilla_products(self):
        for name in ('Bio-Vanille', 'Bio Vanille', 'Bio-Vanilleextrakt', 'vanilla extract'):
            self.assertTrue(ingredient_available('Vanilleextrakt', [name]), name)
            self.assertEqual(ingredient_group_key(name), ingredient_group_key('Vanilleextrakt'))
        for name in ('Vanillezucker', 'Vanilleschote', 'Vanillepudding', 'Vanillearoma'):
            self.assertFalse(ingredient_available('Vanilleextrakt', [name]), name)

    def test_generic_oil_accepts_cooking_oils_but_specific_oils_stay_distinct(self):
        for oil in ('Olivenöl', 'Rapsöl', 'Sonnenblumenöl', 'Sesamöl', 'Kokosöl', 'Kürbiskernöl'):
            self.assertTrue(ingredient_available('Öl', [oil]), oil)
        self.assertFalse(ingredient_available('Öl', ['Motoröl', 'ätherisches Öl']))
        self.assertFalse(ingredient_available('Olivenöl', ['Rapsöl']))
        self.assertTrue(ingredient_available('Olivenöl', ['Olivenöl']))
        self.assertFalse(ingredient_available('Öl', []))

    def test_english_ingredient_names_match_german_pantry_and_filters(self):
        database = self.app.state.database
        collections, recipes = snapshot()
        recipes['r1']['ingredients_json'] = json.dumps([{'name':'Chicken'}, {'name':'Olive oil'}, {'name':'Vegetable stock'}])
        recipes['r2']['ingredients_json'] = json.dumps([{'name':'Hähnchen'}, {'name':'Zwiebeln'}], ensure_ascii=False)
        database.save_snapshot(collections, recipes)
        category = self.client.get('/api/pantry').json()['categories'][0]['id']
        for name in ('Hähnchen', 'Olivenöl', 'Gemüsebrühe'):
            self.assertEqual(self.client.post('/api/pantry/items', json={'name':name,'category_id':category}, headers=ORIGIN).status_code, 200)
        self.assertEqual(self.client.get('/api/recipes/r1').json()['ingredient_availability'], {'0':True,'1':True,'2':True})
        filtered = self.client.get('/api/recipes', params={'collection':'custom:list1','ingredient':'chicken'}).json()
        self.assertEqual({item['id'] for item in filtered['items']}, {'r1','r2'})
        options = self.client.get('/api/collections/custom:list1/filter-options').json()
        self.assertEqual(options['ingredients'].count('Hähnchen'), 1)
        self.assertIn('chicken', options['ingredient_aliases']['Hähnchen'])
        suggestions = self.client.get('/api/ingredients/suggestions', params={'q':'chi'}).json()['items']
        self.assertTrue(any(item['name'] == 'Hähnchen' and item['recipe_count'] == 2 for item in suggestions))
        self.assertTrue(ingredient_available('Ground cumin', ['Kreuzkümmel']))
        self.assertTrue(ingredient_available('carrots', ['Möhren']))
        self.assertTrue(ingredient_available('Chicken breast', ['Hähnchenbrustfilets']))
        self.assertTrue(ingredient_available('Chicken thighs', ['Hähnchen-Oberschenkel, ohne Knochen und Haut']))
        self.assertEqual(ingredient_name('- 200 g Hähnchenbrust'), 'Hähnchenbrust')
        self.assertFalse(ingredient_available('Chicken', ['Schweinefleisch']))
        self.assertFalse(ingredient_available('bell pepper', ['Schwarzer Pfeffer']))
        self.assertFalse(ingredient_available('vegetable stock', ['Hühnerbrühe']))

    def test_recipe_steps_render_cookidoo_symbols_and_entities_without_changing_source(self):
        collections, recipes = snapshot()
        original = [{'title':'', 'steps':['20 Min./100°C/\ue003/Stufe \ue002 kochen.&#x20;Heiß servieren.', 'Anbraten \ue026 und Pürieren \ue01e.', '\ue937 Offenes Kochen/2 Min.', '10 Min./\ue904 100°C/\ue003/Stufe 1.', 'Unbekannt \ue999']}]
        recipes['r1']['instructions_json'] = json.dumps(original, ensure_ascii=False)
        self.app.state.database.save_snapshot(collections, recipes)
        steps = json.loads(self.client.get('/api/recipes/r1').json()['instructions_json'])[0]['steps']
        self.assertEqual(steps[0], '20 Min./100°C/Linkslauf/Sanftrührstufe kochen. Heiß servieren.')
        self.assertEqual(steps[1], 'Anbraten und Pürieren.')
        self.assertEqual(steps[2], 'Offenes Kochen/2 Min.')
        self.assertEqual(steps[3], '10 Min./100°C/Linkslauf/Stufe 1.')
        self.assertEqual(steps[4], 'Unbekannt [Thermomix-Symbol]')
        with self.app.state.database.connect() as db:
            stored = db.execute('SELECT instructions_json FROM recipes WHERE id=?', ('r1',)).fetchone()[0]
        self.assertEqual(json.loads(stored), original)

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
        self.service.creation_origins = AsyncMock(return_value={})

    async def asyncTearDown(self):
        await self.service.close()
        self.tmp.cleanup()

    async def test_cookidoo_actions_use_selected_version_and_pantry(self):
        category = self.db.pantry()['categories'][0]['id']
        self.db.save_pantry_item(category, 'Kreuzkümmel', '')
        items = [NS(id='a', name='Kreuzkümmel (Cumin), gemahlen', is_owned=False),
                 NS(id='b', name='Wasser', is_owned=False),
                 NS(id='c', name='Zwiebel', is_owned=False),
                 NS(id='d', name='Salz', is_owned=True)]
        client = NS(add_recipes_to_calendar=AsyncMock(), add_custom_recipes_to_calendar=AsyncMock(),
                    get_recipes_in_calendar_week=AsyncMock(side_effect=lambda day: [NS(id=day.isoformat(), recipes=[NS(id='r1')], customer_recipe_ids=['abc'])]),
                    add_ingredient_items_for_recipes=AsyncMock(return_value=items),
                    add_ingredient_items_for_custom_recipes=AsyncMock(return_value=[]),
                    edit_ingredient_items_ownership=AsyncMock(side_effect=lambda items: items))
        self.service.client = client
        result = await self.service.recipe_action('r1', 'plan')
        self.assertTrue(result['verified'])
        client.add_recipes_to_calendar.assert_awaited_once()
        self.assertEqual(client.add_recipes_to_calendar.await_args.args[0].isoformat(), result['date'])
        self.assertTrue((await self.service.recipe_action('creation:abc', 'plan'))['verified'])
        client.get_recipes_in_calendar_week.return_value = []
        client.get_recipes_in_calendar_week.side_effect = None
        self.assertFalse((await self.service.recipe_action('r2', 'plan'))['verified'])
        self.assertEqual(client.add_custom_recipes_to_calendar.await_args.args[1], ['abc'])
        with self.assertRaises(ValueError):
            await self.service.recipe_action('r1', 'shopping')
        client.add_ingredient_items_for_recipes.assert_not_awaited()

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

    async def test_created_recipes_import_with_details_and_stable_identity(self):
        class Fake(EmptyBookmarks):
            async def count_custom_collections(self): return (0, 0)
            async def count_managed_collections(self): return (0, 0)
            async def list_custom_recipes(self): return [NS(id='abc', name='Eigenes Rezept', total_time=600)]
            async def get_custom_recipe(self, recipe_id):
                return NS(name='Eigenes Rezept', total_time=600, active_time=300, serving_size=2, ingredients=['2 Eier'], instructions=['Verruehren'], hints=['Eigener Tipp'], image=None, thumbnail=None)
        self.service.client = Fake()
        self.service.begin()
        await self.service.task
        self.assertEqual(self.service.state['phase'], 'done')
        self.assertEqual(self.db.collections()[0]['name'], 'Meine Kreationen')
        recipe = self.db.recipe('creation:abc')
        self.assertEqual(json.loads(recipe['ingredients_json']), ['2 Eier'])
        self.assertEqual(json.loads(recipe['instructions_json']), ['Verruehren'])
        self.assertEqual(json.loads(recipe['tips_json']), ['Eigener Tipp'])
        self.assertIn('/created-recipes/de-DE/abc/edit', recipe['source_url'])

    async def test_creation_origins_only_accept_trusted_cookidoo_links(self):
        class Fake:
            api_endpoint = URL('https://cookidoo.de')
            _cfg = NS(localization=NS(language='de-DE'))
            async def _ensure_endpoints(self): pass
            def _path(self, name): return 'created-recipes/{language}'
            async def _request_json(self, *args, **kwargs):
                return {'items': [
                    {'recipeId': 'c1', 'recipeContent': {'isBasedOn': 'https://cookidoo.de/recipes/recipe/de-DE/r1'}},
                    {'recipeId': 'c2', 'recipeContent': {'isBasedOn': 'https://evil.example/recipes/recipe/de-DE/r2'}},
                    {'recipeId': 'c3', 'recipeContent': {'isBasedOn': ''}},
                ]}
        self.service.client = Fake()
        result = await SyncService.creation_origins(self.service)
        self.assertEqual(result, {'c1': 'r1'})

    async def test_catalogue_details_refresh_cached_recipe_and_store_plain_steps(self):
        collections, recipes = snapshot()
        recipes['r1'].update(image_file='a' * 40 + '.webp', detail_updated_at=now())
        self.db.save_snapshot(collections, recipes)
        (self.service.images / ('a' * 40 + '.webp')).touch()
        class Fake(EmptyBookmarks):
            async def count_custom_collections(self): return (0, 0)
            async def count_managed_collections(self): return (0, 0)
            async def _request_json(self, *args, **kwargs):
                return {'bookmarks': [{'recipe': {'id': 'r1', 'title': 'Test'}}], 'page': {'totalPages': 1}}
            async def get_recipe_details(self, recipe_id):
                return NS(name='Test', total_time=600, active_time=300, serving_size=2, difficulty='easy', ingredients=[NS(description='2 Eier')], image=None, thumbnail=None, step_groups=[NS(title='Teig', recipe_steps=[NS(formatted_text='<b>Gut</b> verrühren &amp; backen')])])
        self.service.client = Fake()
        self.service.begin()
        await self.service.task
        self.assertEqual(self.service.state['phase'], 'done')
        self.assertEqual(json.loads(self.db.recipe('r1')['instructions_json']), [{'title': 'Teig', 'steps': ['Gut verrühren & backen']}])

    async def test_created_recipes_failure_preserves_previous_snapshot(self):
        self.db.save_snapshot(*snapshot())
        class Fake(EmptyBookmarks):
            async def count_custom_collections(self): return (0, 0)
            async def count_managed_collections(self): return (0, 0)
            async def list_custom_recipes(self): raise RuntimeError('unavailable')
        self.service.client = Fake()
        self.service.begin()
        await self.service.task
        self.assertEqual(self.service.state['phase'], 'error')
        self.assertEqual(self.db.stats()['recipes'], 2)

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

    async def test_parallel_calendar_image_requests_share_one_download(self):
        url = 'https://assets.tmecosys.com/week.jpg'
        filename = self.service.calendar_image_reference(url)
        async def fetch(source, http):
            await asyncio.sleep(.02)
            Image.new('RGB', (20, 20), 'green').save(self.service.images / filename, 'WEBP')
            return filename
        self.service.cache_image = AsyncMock(side_effect=fetch)
        result = await asyncio.gather(*(self.service.ensure_calendar_image(filename) for _ in range(5)))
        self.assertEqual(result, [True] * 5)
        self.service.cache_image.assert_awaited_once()

    async def test_calendar_shelf_removal_and_return_are_verified(self):
        service = self.service
        day = lambda ids: NS(id='2026-01-06', recipes=[NS(id=value, is_custom=False) for value in ids], customer_recipe_ids=[])
        client = NS(get_recipes_in_calendar_week=AsyncMock(side_effect=[[day(['r1'])], [day([])], [day([])], [day(['r1'])]]),
                    remove_recipe_from_calendar=AsyncMock(), add_recipes_to_calendar=AsyncMock())
        service.client = client
        base = {'week':'2026-01-05', 'recipe_id':'r1', 'custom':False}
        result = await service.apply_calendar_placement({**base, 'source':'2026-01-06', 'target':'shelf'})
        self.assertEqual(result['status'], 'moved')
        result = await service.apply_calendar_placement({**base, 'source':'shelf', 'target':'2026-01-06'})
        self.assertEqual(result['status'], 'moved')
        client.remove_recipe_from_calendar.assert_awaited_once()
        client.add_recipes_to_calendar.assert_awaited_once()

    async def test_manual_sync_respects_removal_undo_window(self):
        from datetime import date, datetime, timezone
        service = self.service; service.client = NS()
        service.enqueue_calendar_placement(date(2026,1,5), '2026-01-06', 'trash', 'r1', False, 'delete-1', {'name':'Test'})
        service.synchronize = AsyncMock()
        service.apply_calendar_placement = AsyncMock(return_value={'status':'moved'})
        self.assertTrue(service.begin(manual=True))
        await service.task
        service.state['running'] = False
        await service.process_due_calendar_moves()
        self.assertEqual(service.calendar_queue()['phase'], 'waiting')
        self.assertGreater(datetime.fromisoformat(service.calendar_queue()['due']), datetime.now(timezone.utc))
        service.apply_calendar_placement.assert_not_awaited()
        service.undo_calendar_removal('delete-1')
        self.assertEqual(service.calendar_queue()['phase'], 'idle')

    async def test_manual_sync_expedites_pending_week_but_not_failed_or_automatic(self):
        from datetime import date, datetime, timezone
        service = self.service
        service.client = NS()
        service.synchronize = AsyncMock()
        service.enqueue_calendar_move(date(2026, 1, 5), date(2026, 1, 6), 'r1', False, 'one')
        original = service.calendar_queue()['due']
        self.assertTrue(service.begin())
        await service.task
        self.assertEqual(service.calendar_queue()['due'], original)
        service.state['running'] = False
        before = datetime.now(timezone.utc)
        self.assertTrue(service.begin(manual=True))
        await service.task
        self.assertGreaterEqual(datetime.fromisoformat(service.calendar_queue()['due']), before)
        self.assertLess((datetime.fromisoformat(service.calendar_queue()['due']) - before).total_seconds(), 2)
        service.state['running'] = False
        service.move_calendar_recipe = AsyncMock(return_value={'status':'moved'})
        await service.process_due_calendar_moves()
        self.assertEqual(service.calendar_queue()['phase'], 'idle')
        service.move_calendar_recipe.assert_awaited_once()
        service.enqueue_calendar_move(date(2026, 1, 5), date(2026, 1, 6), 'r1', False, 'two')
        def fail(queue):
            queue['phase'] = 'error'
            queue['error'] = 'unconfirmed'
            return queue
        self.db.calendar_queue_update(fail)
        failed = service.calendar_queue()
        self.assertTrue(service.begin(manual=True))
        await service.task
        self.assertEqual(service.calendar_queue(), failed)

    async def test_queued_calendar_moves_wait_and_survive_service_restart(self):
        from datetime import date
        service = self.service
        service.client = NS()
        service.move_calendar_recipe = AsyncMock(return_value={'status':'moved'})
        service.enqueue_calendar_move(date(2026,1,5), date(2026,1,6), 'r1', False, 'one')
        service.enqueue_calendar_move(date(2026,1,6), date(2026,1,7), 'r1', False, 'two')
        await service.process_due_calendar_moves()
        service.move_calendar_recipe.assert_not_awaited()
        restored = SyncService(self.db, service.vault)
        self.assertEqual(len(restored.calendar_queue()['items']), 2)
        def due(queue):
            queue['due'] = '2000-01-01T00:00:00+00:00'
            return queue
        self.db.calendar_queue_update(due)
        await service.process_due_calendar_moves()
        self.assertEqual(service.move_calendar_recipe.await_count, 2)
        self.assertEqual(service.calendar_queue()['phase'], 'idle')

    async def test_uncertain_queued_calendar_move_is_not_retried(self):
        from datetime import date
        service = self.service
        service.client = NS()
        service.move_calendar_recipe = AsyncMock(return_value={'status':'uncertain', 'message':'Bitte Cookidoo prüfen.'})
        service.enqueue_calendar_move(date(2026,1,5), date(2026,1,6), 'r1', False, 'one')
        def due(queue):
            queue['due'] = '2000-01-01T00:00:00+00:00'
            return queue
        self.db.calendar_queue_update(due)
        await service.process_due_calendar_moves()
        self.assertEqual(service.calendar_queue()['phase'], 'error')
        await service.process_due_calendar_moves()
        service.move_calendar_recipe.assert_awaited_once()
        self.assertEqual(service.discard_failed_calendar_moves()['phase'], 'idle')

    async def test_interrupted_calendar_move_requires_manual_review(self):
        from datetime import date
        service = self.service
        service.client = NS()
        service.enqueue_calendar_move(date(2026,1,5), date(2026,1,6), 'r1', False, 'one')
        def interrupted(queue):
            queue['phase'] = 'processing'
            return queue
        self.db.calendar_queue_update(interrupted)
        restored = SyncService(self.db, service.vault)
        restored.recover_calendar_queue()
        self.assertEqual(restored.calendar_queue()['phase'], 'error')
        self.assertEqual(len(restored.calendar_queue()['items']), 1)

    async def test_calendar_scheduler_runs_due_queue_without_a_browser(self):
        from datetime import date
        service = self.service
        service.client = NS()
        service.move_calendar_recipe = AsyncMock(return_value={'status':'moved'})
        service.enqueue_calendar_move(date(2026,1,5), date(2026,1,6), 'r1', False, 'one')
        def due(queue):
            queue['due'] = '2000-01-01T00:00:00+00:00'
            return queue
        self.db.calendar_queue_update(due)
        await service.start()
        for _ in range(30):
            if service.calendar_queue()['phase'] == 'idle':
                break
            await asyncio.sleep(.1)
        self.assertEqual(service.calendar_queue()['phase'], 'idle')
        service.move_calendar_recipe.assert_awaited_once()

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

    async def test_first_connection_adopts_unassigned_cart_but_account_change_does_not(self):
        class Fake:
            def __init__(self, session, cfg, on_auth_data_update): pass
            async def login(self): pass
        unassigned = self.service.cart_owner()
        self.db.cart_add(unassigned, 'additional', {'name':'Milch', 'owned':False})
        with patch('app.sync.Cookidoo', Fake):
            await self.service.connect('first@example.invalid', 'test-password', 'de')
            first = self.service.cart_owner()
            self.assertEqual(len(self.db.cart(first)), 1)
            await self.service.connect('second@example.invalid', 'test-password', 'de')
            self.assertEqual(self.db.cart(self.service.cart_owner()), [])
            self.assertEqual(len(self.db.cart(first)), 1)


if __name__ == '__main__':
    unittest.main()
