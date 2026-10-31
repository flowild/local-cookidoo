import asyncio
import json
import logging
import os
import re
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .security import Vault
from .storage import Database
from .sync import REGIONS, SyncService, friendly_error

STATIC = Path(__file__).parent / 'static'


class Connection(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=512)
    region: str = 'de'


class Settings(BaseModel):
    sync_hours: int


class LocalCollection(BaseModel):
    name: str = Field(min_length=1, max_length=100)


class Membership(BaseModel):
    present: bool


class PantryCategory(BaseModel):
    name: str = Field(min_length=1, max_length=60)


class PantryOrder(BaseModel):
    category_ids: list[int] = Field(max_length=1000)


class PantryItem(BaseModel):
    category_id: int = Field(gt=0)
    name: str = Field(min_length=1, max_length=100)
    quantity: str = Field(default='', max_length=80)
    ingredient_id: int | None = Field(default=None, gt=0)


def create_app(directory=None, secure_cookies=None):
    os.umask(0o077)
    database = Database(directory or os.environ.get('REZEPTGARTEN_DATA', './data'))
    vault = Vault(database.directory)
    google_key_vault = Vault(database.directory, 'google-api-key.enc')
    service = SyncService(database, vault)
    @asynccontextmanager
    async def lifespan(app):
        await service.start()
        yield
        await service.close()

    app = FastAPI(title='Rezeptgarten', docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)
    app.state.database = database
    app.state.sync = service

    @app.middleware('http')
    async def security_headers(request, call_next):
        if request.url.path.startswith('/api/') and request.method not in ('GET', 'HEAD', 'OPTIONS'):
            origin = request.headers.get('origin')
            expected = f'{request.url.scheme}://{request.headers.get("host", "")}'
            if origin != expected:
                return JSONResponse({'detail': 'Die Anfrage muss aus dieser App stammen.'}, status_code=403)
            content_length = request.headers.get('content-length', '0')
            try:
                if int(content_length) > 16384:
                    return JSONResponse({'detail': 'Die Anfrage ist zu groß.'}, status_code=413)
            except ValueError:
                return JSONResponse({'detail': 'Ungültige Anfrage.'}, status_code=400)
        response = await call_next(request)
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Referrer-Policy'] = 'no-referrer'
        response.headers['X-Frame-Options'] = 'DENY'
        response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'; worker-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
        if request.url.path.startswith('/api/'):
            response.headers['Cache-Control'] = 'no-store'
        return response

    @app.get('/api/health')
    def health():
        return {'ok': True, 'version': '0.1.0'}

    @app.get('/api/auth/status')
    def auth_status():
        # Compatibility for clients that have not yet reloaded the app shell.
        return {'configured': True, 'authenticated': True}

    @app.get('/api/status')
    def status():
        return {'stats': database.stats(), 'connected': service.client is not None, 'account': database.get('account'), 'sync': service.state, 'last_result': database.get('last_result'), 'sync_hours': database.get('sync_hours', 6), 'google_api_key_set': google_key_vault.path.is_file()}

    @app.post('/api/google-api-key')
    async def set_google_api_key(request: Request):
        try:
            payload = await request.json()
        except (ValueError, UnicodeDecodeError):
            raise HTTPException(400, 'Bitte gib einen gültigen API-Schlüssel ein.') from None
        key = payload.get('key') if isinstance(payload, dict) else None
        if not isinstance(key, str) or not key.strip() or len(key) > 512 or any(c.isspace() or ord(c) < 32 for c in key.strip()):
            raise HTTPException(400, 'Bitte gib einen gültigen API-Schlüssel ein.')
        google_key_vault.write({'key': key.strip()})
        return {'ok': True}

    @app.delete('/api/google-api-key')
    def delete_google_api_key():
        google_key_vault.clear()
        return {'ok': True}

    @app.get('/api/featured-recipe')
    def featured_recipe():
        return database.featured_recipe()

    @app.post('/api/featured-recipe/shuffle')
    def shuffle_featured_recipe():
        return database.featured_recipe(refresh=True)

    @app.get('/api/collections')
    def collections():
        return {'items': database.collections()}

    @app.get('/api/collections/{collection_id}/filter-options')
    def filter_options(collection_id: str):
        result = database.recipe_filter_options(collection_id)
        if result is None:
            raise HTTPException(404, 'Diese Rezeptliste wurde nicht gefunden.')
        return result

    @app.post('/api/local-collections')
    def create_local_collection(payload: LocalCollection):
        name = payload.name.strip()
        if not name:
            raise HTTPException(400, 'Bitte gib einen Namen für die Liste ein.')
        return {'id': database.create_local_collection(name)}

    @app.put('/api/local-collections/{collection_id}/recipes/{recipe_id}')
    def update_local_membership(collection_id: str, recipe_id: str, payload: Membership):
        if not database.set_local_membership(collection_id, recipe_id, payload.present):
            raise HTTPException(404, 'Liste oder Rezept wurde nicht gefunden.')
        return {'ok': True}

    @app.get('/api/pantry')
    def pantry():
        return database.pantry()

    @app.get('/api/ingredients/suggestions')
    def ingredient_suggestions(q: str = Query('', max_length=100)):
        if not q.strip():
            return {'items': []}
        return {'items': database.ingredient_suggestions(q.strip())}

    @app.post('/api/pantry/categories')
    def create_pantry_category(payload: PantryCategory):
        name = payload.name.strip()
        if not name:
            raise HTTPException(400, 'Bitte gib einen Kategorienamen ein.')
        identifier = database.add_pantry_category(name)
        if identifier is None:
            raise HTTPException(409, 'Diese Kategorie gibt es bereits.')
        return {'id': identifier}

    @app.put('/api/pantry/categories/order')
    def reorder_pantry_categories(payload: PantryOrder):
        if not database.reorder_pantry_categories(payload.category_ids):
            raise HTTPException(409, 'Die Kategorien haben sich geändert. Bitte lade den Vorrat neu.')
        return {'ok': True}

    def save_pantry(payload: PantryItem, item_id=None):
        name = payload.name.strip()
        if not name:
            raise HTTPException(400, 'Bitte gib einen Zutatennamen ein.')
        try:
            identifier = database.save_pantry_item(payload.category_id, name, payload.quantity.strip(), item_id, payload.ingredient_id)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        if identifier is None:
            raise HTTPException(404, 'Kategorie oder Zutat wurde nicht gefunden.')
        return {'id': identifier}

    @app.post('/api/pantry/items')
    def create_pantry_item(payload: PantryItem):
        return save_pantry(payload)

    @app.put('/api/pantry/items/{item_id}')
    def update_pantry_item(item_id: int, payload: PantryItem):
        return save_pantry(payload, item_id)

    @app.delete('/api/pantry/items/{item_id}')
    def delete_pantry_item(item_id: int):
        if not database.delete_pantry_item(item_id):
            raise HTTPException(404, 'Diese Zutat wurde nicht gefunden.')
        return {'ok': True}

    @app.get('/api/recipes')
    def recipes(collection: str | None = None, exclude_collection: str | None = None, q: str = Query('', max_length=200), sort: str = 'name', offset: int = Query(0, ge=0), limit: int = Query(48, ge=1, le=100), ingredient: list[str] = Query(default=[]), min_servings: int | None = Query(None, ge=1, le=1000), max_minutes: int | None = Query(None, ge=1, le=10080), show_all: bool = False, candidate_q: str = Query('', max_length=200)):
        if sort not in ('name', 'time', 'servings', 'ingredients'):
            raise HTTPException(400, 'Ungültige Sortierung.')
        if len(ingredient) > 20 or any(len(term) > 100 for term in ingredient):
            raise HTTPException(400, 'Bitte wähle höchstens 20 Zutaten mit je maximal 100 Zeichen.')
        return database.recipes(collection, q.strip(), sort, offset, limit, exclude_collection, ingredient, min_servings, max_minutes, show_all, candidate_q.strip())

    @app.get('/api/recipes/{recipe_id}')
    def recipe(recipe_id: str):
        result = database.recipe(recipe_id)
        if result is None:
            raise HTTPException(404, 'Dieses Rezept wurde nicht gefunden.')
        return result

    async def cookidoo_recipe_action(recipe_id: str, action: str):
        if database.recipe(recipe_id) is None:
            raise HTTPException(404, 'Dieses Rezept wurde nicht gefunden.')
        try:
            return await service.recipe_action(recipe_id, action)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Cookidoo recipe action failed: %s', type(error).__name__)
            raise HTTPException(502, 'Cookidoo konnte die Aktion nicht bestätigen. Bitte prüfe den Kalender oder die Einkaufsliste, bevor du es erneut versuchst.') from None

    @app.post('/api/recipes/{recipe_id}/plan-today')
    async def plan_today(recipe_id: str):
        return await cookidoo_recipe_action(recipe_id, 'plan')

    @app.post('/api/recipes/{recipe_id}/shopping')
    async def add_to_shopping(recipe_id: str):
        return await cookidoo_recipe_action(recipe_id, 'shopping')

    @app.get('/api/images/{filename}')
    def image(filename: str):
        if not re.fullmatch(r'[a-f0-9]{40}\.webp', filename):
            raise HTTPException(404)
        path = service.images / filename
        if not path.is_file():
            raise HTTPException(404)
        return FileResponse(path, media_type='image/webp', headers={'Cache-Control': 'private, max-age=86400'})

    @app.post('/api/connect')
    async def connect(payload: Connection):
        if payload.region not in REGIONS or '@' not in payload.email:
            raise HTTPException(400, 'Bitte prüfe E-Mail-Adresse und Land deines Cookidoo-Kontos.')
        try:
            await service.connect(payload.email.strip(), payload.password, payload.region)
            service.begin()
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Cookidoo login failed: %s', type(error).__name__)
            raise HTTPException(502, friendly_error(error)) from None
        return {'ok': True}

    @app.post('/api/disconnect')
    async def disconnect():
        try:
            await service.disconnect()
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        return {'ok': True}

    @app.post('/api/sync')
    async def sync():
        try:
            started = service.begin()
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        return {'started': started}

    @app.post('/api/settings')
    def settings(payload: Settings):
        if payload.sync_hours not in (0, 1, 6, 24):
            raise HTTPException(400, 'Ungültiges Synchronisierungsintervall.')
        database.set('sync_hours', payload.sync_hours)
        return {'ok': True}

    @app.get('/api/export')
    def export():
        return Response(json.dumps(database.export(), ensure_ascii=False, indent=2), media_type='application/json', headers={'Content-Disposition': 'attachment; filename="rezeptgarten-sammlung.json"', 'Cache-Control': 'no-store'})

    @app.get('/sw.js')
    def worker():
        return FileResponse(STATIC / 'sw.js', media_type='application/javascript', headers={'Cache-Control': 'no-cache', 'Service-Worker-Allowed': '/'})

    app.mount('/static', StaticFiles(directory=STATIC), name='static')

    @app.get('/')
    def index():
        return FileResponse(STATIC / 'index.html', headers={'Cache-Control': 'no-cache'})

    return app
