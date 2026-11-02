import json
import tempfile
import unittest
from types import SimpleNamespace as NS
from unittest.mock import AsyncMock

from fastapi.testclient import TestClient

from app.main import create_app
from app.storage import now

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

    def cart(self):
        return self.client.get('/api/cart').json()['items']

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
