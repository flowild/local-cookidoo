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
from unittest.mock import AsyncMock, patch

from yarl import URL

import httpx
from fastapi.testclient import TestClient
from PIL import Image

from app.main import create_app
from app.ingredients import ingredient_available, ingredient_display_name, ingredient_group_key, ingredient_name
from app.security import Vault
from app.storage import Database, now
from app.sync import SyncService

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
        self.assertEqual(image.headers['cache-control'], 'no-store')

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
                    edit_ingredient_items_ownership=AsyncMock())
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
        result = await self.service.recipe_action('r1', 'shopping')
        self.assertEqual(result, {'partial': False, 'marked': 2})
        self.assertEqual([i.id for i in client.edit_ingredient_items_ownership.await_args.args[0]], ['a', 'b'])
        self.assertFalse(items[2].is_owned)
        await self.service.recipe_action('creation:abc', 'shopping')
        client.add_ingredient_items_for_custom_recipes.assert_awaited_once_with(['abc'])

    async def test_cookidoo_shopping_partial_failure_and_busy_state(self):
        item = NS(id='a', name='Wasser', is_owned=False)
        self.service.client = NS(add_ingredient_items_for_recipes=AsyncMock(return_value=[item]),
                                 edit_ingredient_items_ownership=AsyncMock(side_effect=RuntimeError('failure')))
        self.assertEqual(await self.service.recipe_action('r1', 'shopping'), {'partial': True})
        self.service.state['running'] = True
        with self.assertRaises(ValueError):
            await self.service.recipe_action('r1', 'shopping')
        self.service.client.add_ingredient_items_for_recipes.assert_awaited_once()

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
                return NS(name='Eigenes Rezept', total_time=600, active_time=300, serving_size=2, ingredients=['2 Eier'], instructions=['Verruehren'], image=None, thumbnail=None)
        self.service.client = Fake()
        self.service.begin()
        await self.service.task
        self.assertEqual(self.service.state['phase'], 'done')
        self.assertEqual(self.db.collections()[0]['name'], 'Meine Kreationen')
        recipe = self.db.recipe('creation:abc')
        self.assertEqual(json.loads(recipe['ingredients_json']), ['2 Eier'])
        self.assertEqual(json.loads(recipe['instructions_json']), ['Verruehren'])
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
