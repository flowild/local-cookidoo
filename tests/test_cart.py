import json
import tempfile
import unittest
import base64
import os
import zlib
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from types import SimpleNamespace as NS
from unittest.mock import AsyncMock

from fastapi.testclient import TestClient

from app.main import create_app
from app.storage import now
from app.security import Vault
from app.telegram_cart import encrypted_snapshot

ORIGIN = {'Origin': 'https://testserver'}


class CartTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.app = create_app(self.tmp.name)
        self.db = self.app.state.database
        self.db.set('account', {'email': 'test@example.invalid', 'region': 'de'})
        ingredients = [{'name':'Zwiebel', 'description':'2 Zwiebeln'}, {'name':'Mehl', 'description':'100 g Mehl'}]
        recipes = {'r1': {'id':'r1', 'name':'Testrezept', 'ingredients_json':json.dumps(ingredients), 'updated_at':now()}}
        self.db.save_snapshot([{'id':'c1', 'source_id':'c1', 'kind':'custom', 'name':'Liste', 'members':[{'id':'r1'}]}], recipes)
        category = self.db.pantry()['categories'][0]['id']
        self.db.save_pantry_item(category, 'Zwiebel', '')
        self.client = TestClient(self.app, base_url='https://testserver')
        self.client.__enter__()

    def tearDown(self):
        self.client.__exit__(None, None, None)
        self.tmp.cleanup()

    def add_recipe(self):
        return self.client.post('/api/recipes/r1/shopping', headers=ORIGIN).json()

    def test_status_counts_only_recipes_of_the_current_cart(self):
        self.assertEqual(self.client.get('/api/status').json()['cart_recipe_count'], 0)
        self.add_recipe()
        self.add_recipe()
        self.client.post('/api/cart/items', json={'name':'Milch'}, headers=ORIGIN)
        self.assertEqual(self.client.get('/api/status').json()['cart_recipe_count'], 1)
        self.db.set('account', {'email':'other@example.invalid', 'region':'de'})
        self.assertEqual(self.client.get('/api/status').json()['cart_recipe_count'], 0)
        self.db.set('account', {'email':'test@example.invalid', 'region':'de'})
        self.client.delete('/api/cart', headers=ORIGIN)
        self.assertEqual(self.client.get('/api/status').json()['cart_recipe_count'], 0)

    def cart(self):
        return self.client.get('/api/cart').json()['items']

    def test_telegram_cart_is_encrypted_read_only_and_bound_to_account(self):
        self.add_recipe()
        self.client.post('/api/cart/items', json={'name': 'Milch'}, headers=ORIGIN)
        self.client.post('/api/cart/items', json={'name': 'Wasser'}, headers=ORIGIN)
        key = os.urandom(32)
        owner = self.app.state.sync.cart_owner()
        Vault(self.tmp.name, 'telegram-server-bot.enc').write({'cart_key':base64.b64encode(key).decode(), 'cart_owner':owner})
        nonce = 'a' * 32
        encoded = encrypted_snapshot(self.tmp.name, nonce)
        self.assertNotIn('Milch', encoded)
        packed = base64.b64decode(encoded)
        result = json.loads(AESGCM(key).decrypt(packed[:12], packed[12:], nonce.encode()))
        self.assertEqual([i['name'] for i in result['items']], ['Testrezept', 'Milch'])
        self.assertEqual([i['text'] for i in result['items'][0]['ingredients']], ['2 Zwiebeln', '100 g Mehl'])
        self.assertEqual(len(self.cart()), 3)
        compressed = base64.b64decode(encrypted_snapshot(self.tmp.name, nonce, compress=True))
        decoded = AESGCM(key).decrypt(compressed[:12], compressed[12:], nonce.encode())
        self.assertEqual(json.loads(zlib.decompress(decoded)), result)
        self.db.set('account', {'email':'other@example.invalid', 'region':'de'})
        with self.assertRaises(ValueError):
            encrypted_snapshot(self.tmp.name, nonce)

    def test_local_add_deduplicates_survives_library_sync_and_scopes_account(self):
        self.assertEqual(self.client.post('/api/recipes/r1/shopping').status_code, 403)
        self.assertTrue(self.add_recipe()['added'])
        self.assertFalse(self.add_recipe()['added'])
        entry = self.cart()[0]
        self.assertTrue(entry['data']['ingredients'][0]['owned'])
        self.assertFalse(entry['data']['ingredients'][1]['owned'])
        self.db.save_snapshot([], {})
        self.assertEqual(self.cart()[0]['data']['name'], 'Testrezept')
        self.db.set('account', {'email':'other@example.invalid', 'region':'de'})
        self.assertEqual(self.cart(), [])
        self.db.set('account', {'email':'test@example.invalid', 'region':'de'})
        self.assertEqual(len(self.cart()), 1)
        self.assertEqual(len(self.db.export()['cart']), 1)

    def test_cart_recipe_duration_snapshot_and_older_entries(self):
        self.db.save_snapshot([{'id':'c1', 'source_id':'c1', 'kind':'custom', 'name':'Liste', 'members':[{'id':'r1'}]}],
                              {'r1': {'id':'r1', 'name':'Testrezept', 'total_seconds':3000, 'difficulty':'easy', 'ingredients_json':'[]', 'updated_at':now()}})
        self.add_recipe()
        data = self.cart()[0]['data']
        self.assertEqual((data['total_seconds'], data['difficulty']), (3000, 'easy'))
        self.db.cart_update(self.app.state.sync.cart_owner(), self.cart()[0]['id'], data={**data, 'total_seconds':None, 'difficulty':None})
        legacy = self.cart()[0]['data']
        self.assertEqual((legacy['total_seconds'], legacy['difficulty']), (3000, 'easy'))
        self.assertIsNone(self.db.cart(self.app.state.sync.cart_owner())[0]['data']['total_seconds'])

    def test_existing_cart_spaghetti_group_uses_current_alias(self):
        owner = self.app.state.sync.cart_owner()
        self.db.cart_add(owner, 'recipe', {'id':'old', 'name':'Test', 'ingredients':[{'name':'Spaghetti', 'key':'spaghetti', 'text':'100 g Spaghetti', 'owned':False}]}, 'old')
        self.assertEqual(self.cart()[0]['data']['ingredients'][0]['key'], 'nudeln')
        self.assertEqual(self.db.cart(owner)[0]['data']['ingredients'][0]['key'], 'spaghetti')

    def test_cart_ingredient_categories_and_water_are_display_metadata(self):
        category = self.db.add_pantry_category('Eigene Gruppe')
        self.db.save_pantry_item(category, 'Zwiebel', '')
        ingredients = [{'name':'Zwiebeln', 'description':'2 Zwiebeln'}, {'name':'Ghee', 'description':'40 g Ghee'}, {'name':'Wasser', 'description':'500 g Wasser'}, {'name':'Kokoswasser', 'description':'50 g Kokoswasser'}, {'name':'Unbekanntes Lebensmittel', 'description':'1 Unbekanntes Lebensmittel'}]
        self.db.save_snapshot([{'id':'c1', 'source_id':'c1', 'kind':'custom', 'name':'Liste', 'members':[{'id':'r1'}]}],
                              {'r1': {'id':'r1', 'name':'Testrezept', 'ingredients_json':json.dumps(ingredients), 'updated_at':now()}})
        self.add_recipe()
        values = {item['name']: item for item in self.cart()[0]['data']['ingredients']}
        self.assertEqual(values['Zwiebeln']['category'], 'Eigene Gruppe')
        self.assertEqual(values['Ghee']['category'], 'Öle und Fette')
        self.assertEqual(values['Unbekanntes Lebensmittel']['category'], 'Sonstiges')
        self.assertTrue(values['Wasser']['is_water'])
        self.assertFalse(values['Kokoswasser']['is_water'])
        stored = self.db.cart(self.app.state.sync.cart_owner())[0]['data']['ingredients']
        self.assertNotIn('category', stored[0])
        self.assertEqual(len(stored), 5)

    def test_water_hidden_in_ingredients_and_suggestions_preserves_positions(self):
        ingredients = ['500 g Wasser', {'name':'Kokoswasser','description':'100 g Kokoswasser'}, {'name':'heißes Wasser','description':'200 g heißes Wasser'}, {'name':'Zwiebel','description':'1 Zwiebel'}]
        self.db.save_snapshot([{'id':'c1', 'source_id':'c1', 'kind':'custom', 'name':'Liste', 'members':[{'id':'r1'}]}],
                              {'r1': {'id':'r1', 'name':'Testrezept', 'ingredients_json':json.dumps(ingredients), 'updated_at':now()}})
        result = self.client.get('/api/recipes/r1').json()
        self.assertEqual(result['hidden_ingredient_positions'], [0, 2])
        self.assertEqual(json.loads(result['ingredients_json']), ingredients)
        options = self.client.get('/api/collections/c1/filter-options').json()['ingredients']
        self.assertIn('Kokoswasser', options)
        self.assertNotIn('Wasser', options)
        suggestions = self.client.get('/api/ingredients/suggestions?q=wasser').json()['items']
        self.assertEqual([item['name'] for item in suggestions], ['Kokoswasser'])
        category = self.db.pantry()['categories'][0]['id']
        self.db.save_pantry_item(category, 'Wasser', '')
        self.assertFalse(any(item['name'] == 'Wasser' for item in self.client.get('/api/pantry').json()['items']))
        self.assertTrue(any(item['name'] == 'Wasser' for item in self.db.pantry()['items']))

    def test_remote_recipe_also_hides_water_without_shifting_ingredients(self):
        data = {'id':'remote', 'ingredients_json':json.dumps(['Wasser', 'Kokoswasser']), 'is_local':False}
        self.app.state.sync.calendar_recipe_details = AsyncMock(return_value=data)
        result = self.client.get('/api/recipes/remote?calendar=true').json()
        self.assertEqual(result['hidden_ingredient_positions'], [0])
        self.assertFalse(result['is_local'])

    def test_confirmed_transfer_does_not_repeat_and_preserves_existing(self):
        self.add_recipe()
        entry = self.cart()[0]
        water = NS(id='i1', name='Zwiebel', is_owned=False, description='2 Zwiebeln')
        client = NS(get_shopping_list_recipes=AsyncMock(side_effect=[[], [NS(id='r1')], [NS(id='r1')]]),
                    add_ingredient_items_for_recipes=AsyncMock(return_value=[water]),
                    edit_ingredient_items_ownership=AsyncMock(side_effect=lambda values: values))
        self.app.state.sync.client = client
        response = self.client.post('/api/cart/transfer', headers=ORIGIN)
        self.assertEqual(response.json()['status'], 'ok')
        self.assertEqual(self.cart()[0]['status'], 'done')
        self.assertTrue(water.is_owned)
        self.client.post('/api/cart/transfer', headers=ORIGIN)
        client.add_ingredient_items_for_recipes.assert_awaited_once_with(['r1'])
        self.assertEqual(self.client.put(f"/api/cart/{entry['id']}/ingredients/0", json={'owned':False}, headers=ORIGIN).status_code, 409)

    def test_unconfirmed_write_is_durable_and_never_retried_automatically(self):
        self.add_recipe()
        client = NS(get_shopping_list_recipes=AsyncMock(return_value=[]),
                    add_ingredient_items_for_recipes=AsyncMock(side_effect=RuntimeError('timeout')))
        self.app.state.sync.client = client
        response = self.client.post('/api/cart/transfer', headers=ORIGIN)
        self.assertEqual(response.json()['status'], 'partial')
        entry = self.cart()[0]
        self.assertEqual(entry['status'], 'uncertain')
        self.assertEqual(self.client.post('/api/cart/transfer', headers=ORIGIN).status_code, 409)
        client.add_ingredient_items_for_recipes.assert_awaited_once()
        self.assertEqual(self.client.post(f"/api/cart/{entry['id']}/resolve", json={'status':'done'}, headers=ORIGIN).status_code, 200)
        self.assertEqual(self.cart()[0]['status'], 'done')

    def test_extras_and_interrupted_transfer_recovery(self):
        self.client.post('/api/cart/items', json={'name':'Milch'}, headers=ORIGIN)
        entry = self.cart()[0]
        self.client.put(f"/api/cart/{entry['id']}/owned", json={'owned':True}, headers=ORIGIN)
        extra = NS(id='extra1', name='Milch', is_owned=False)
        client = NS(get_shopping_list_recipes=AsyncMock(return_value=[]), add_additional_items=AsyncMock(return_value=[extra]),
                    edit_additional_items_ownership=AsyncMock(side_effect=lambda values: values))
        self.app.state.sync.client = client
        self.assertEqual(self.client.post('/api/cart/transfer', headers=ORIGIN).json()['status'], 'ok')
        self.assertTrue(extra.is_owned)
        self.assertEqual(self.cart()[0]['status'], 'done')
        self.db.cart_update(self.app.state.sync.week_collection_owner(), entry['id'], status='processing')
        self.assertEqual(self.cart()[0]['status'], 'uncertain')

    def test_existing_cookidoo_recipe_is_not_overwritten(self):
        self.add_recipe()
        client = NS(get_shopping_list_recipes=AsyncMock(return_value=[NS(id='r1')]),
                    add_ingredient_items_for_recipes=AsyncMock(), edit_ingredient_items_ownership=AsyncMock())
        self.app.state.sync.client = client
        self.assertEqual(self.client.post('/api/cart/transfer', headers=ORIGIN).json()['status'], 'ok')
        self.assertEqual(self.cart()[0]['status'], 'existing')
        client.add_ingredient_items_for_recipes.assert_not_awaited()
        client.edit_ingredient_items_ownership.assert_not_awaited()

    def test_partial_transfer_keeps_confirmed_entries_and_stops(self):
        self.add_recipe()
        self.client.post('/api/cart/items', json={'name':'Milch'}, headers=ORIGIN)
        onion = NS(id='i1', name='Zwiebel', is_owned=False, description='2 Zwiebeln')
        client = NS(get_shopping_list_recipes=AsyncMock(side_effect=[[], [NS(id='r1')]]),
                    add_ingredient_items_for_recipes=AsyncMock(return_value=[onion]),
                    edit_ingredient_items_ownership=AsyncMock(side_effect=lambda values: values),
                    add_additional_items=AsyncMock(side_effect=RuntimeError('timeout')))
        self.app.state.sync.client = client
        self.assertEqual(self.client.post('/api/cart/transfer', headers=ORIGIN).json()['status'], 'partial')
        self.assertEqual([entry['status'] for entry in self.cart()], ['done', 'uncertain'])
        self.assertEqual(self.client.post('/api/cart/transfer', headers=ORIGIN).status_code, 409)
        client.add_ingredient_items_for_recipes.assert_awaited_once()
        client.add_additional_items.assert_awaited_once()

    def test_unconfirmed_ownership_requires_manual_review(self):
        self.add_recipe()
        onion = NS(id='i1', name='Zwiebel', is_owned=False, description='2 Zwiebeln')
        client = NS(get_shopping_list_recipes=AsyncMock(side_effect=[[], [NS(id='r1')]]),
                    add_ingredient_items_for_recipes=AsyncMock(return_value=[onion]),
                    edit_ingredient_items_ownership=AsyncMock(return_value=[]))
        self.app.state.sync.client = client
        self.assertEqual(self.client.post('/api/cart/transfer', headers=ORIGIN).json()['status'], 'partial')
        self.assertEqual(self.cart()[0]['status'], 'uncertain')
        self.assertEqual(self.client.post('/api/cart/transfer', headers=ORIGIN).status_code, 409)
        client.add_ingredient_items_for_recipes.assert_awaited_once()

    def test_creation_uses_custom_recipe_interface(self):
        self.db.cart_add(self.app.state.sync.cart_owner(), 'recipe',
                         {'id':'creation:abc', 'name':'Eigenes Rezept', 'ingredients':[], 'ingredients_complete':True}, 'creation:abc')
        client = NS(get_shopping_list_recipes=AsyncMock(side_effect=[[], [NS(id='abc')]]),
                    add_ingredient_items_for_custom_recipes=AsyncMock(return_value=[]))
        self.app.state.sync.client = client
        self.assertEqual(self.client.post('/api/cart/transfer', headers=ORIGIN).json()['status'], 'ok')
        client.add_ingredient_items_for_custom_recipes.assert_awaited_once_with(['abc'])

    def test_missing_ingredients_block_transfer_before_any_write(self):
        self.db.cart_add(self.app.state.sync.cart_owner(), 'recipe',
                         {'id':'missing', 'name':'Missing', 'ingredients':[], 'ingredients_complete':False}, 'missing')
        client = NS(get_shopping_list_recipes=AsyncMock(return_value=[]), add_ingredient_items_for_recipes=AsyncMock())
        self.app.state.sync.client = client
        self.assertEqual(self.client.post('/api/cart/transfer', headers=ORIGIN).status_code, 409)
        client.add_ingredient_items_for_recipes.assert_not_awaited()

    def test_cart_stays_accessible_after_disconnect_and_scoped_after_account_change(self):
        self.add_recipe()
        self.db.set('cart_last_owner', self.app.state.sync.cart_owner())
        self.db.set('account', None)
        self.assertEqual(len(self.cart()), 1)
        self.db.set('account', {'email':'different@example.invalid', 'region':'de'})
        self.assertEqual(self.cart(), [])

    def test_vanilla_extract_is_marked_available_from_bio_vanilla(self):
        category = self.db.pantry()['categories'][0]['id']
        self.db.save_pantry_item(category, 'Bio-Vanille', '')
        data = {'r2': {'id':'r2', 'name':'Test', 'ingredients_json':json.dumps([{'name':'Vanilleextrakt', 'description':'1 TL Vanilleextrakt'}]), 'updated_at':now()}}
        self.db.save_snapshot([{'id':'c2', 'source_id':'c2', 'kind':'custom', 'name':'Liste', 'members':[{'id':'r2'}]}], data)
        self.assertTrue(self.client.post('/api/recipes/r2/shopping', headers=ORIGIN).json()['added'])
        self.assertTrue(self.cart()[0]['data']['ingredients'][0]['owned'])
