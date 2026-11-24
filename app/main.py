import asyncio
import hashlib
import json
import json
import logging
import os
import re
import base64
import secrets
import time
import zlib
import httpx
from cryptography.exceptions import InvalidTag
from contextlib import asynccontextmanager
from datetime import date, timedelta
from pathlib import Path
from threading import Lock
from typing import Literal

from fastapi import FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .catalog import CatalogUnavailable, RecipeCatalog
from .recipe_search import parse_recipe_search
from .security import Vault
from .storage import Database
from .sync import REGIONS, SyncService, cooking_days, friendly_error
from .cart import recipe_snapshot, transfer as transfer_cart
from .ingredients import ingredient_available, ingredient_group_key, ingredient_name, pantry_item_icons, shopping_category, shopping_category_icon
from .version import APP_VERSION
from .telegram_cart import encrypt_payload
from .telegram_week import snapshot as telegram_week_snapshot
from .telegram_pairs import select_pair
from .telegram_api import encrypt_response, open_request, route_allowed

STATIC = Path(__file__).parent / 'static'


class Connection(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=512)
    region: str = 'de'


class Settings(BaseModel):
    sync_hours: int


Symbol = Literal['🍎', '🥕', '🌿', '🧂', '🥩', '🐟', '🥛', '🥚', '🍞', '🍚', '🍝', '🥫',
                 '🧁', '🍲', '🥗', '☕', '🧊', '🛒', '📚', '⭐', '❤️', '🍽️', '🧺', '🍋',
                 '🥔', '🍅', '🧅', '🧄', '🫑', '🥦', '🥒', '🍄', '🥬', '🥑', '🌶️', '🫚',
                 '🍌', '🍊', '🍓', '🫐', '🌾', '🫘', '🥜', '🫒', '🧀', '🧈', '🍗', '🦐',
                 '🍯', '🍫', '🥤', '🫖', '🥐', '🍰', '🍕', '🥘', '🥣', '🍱', '🥡', '🧻',
                 '🧽', '🧼', '🧴', '🪥', '🗑️']


class LocalCollection(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    icon: Symbol | None = None


class Membership(BaseModel):
    present: bool


class PantryCategory(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    icon: Symbol | None = None


class PantryOrder(BaseModel):
    category_ids: list[int] = Field(max_length=1000)


class PantryItem(BaseModel):
    category_id: int = Field(gt=0)
    name: str = Field(min_length=1, max_length=100)
    quantity: str = Field(default='', max_length=80)
    ingredient_id: int | None = Field(default=None, gt=0)
    icon: Symbol | None = None


class CalendarMove(BaseModel):
    source: date
    target: date
    recipe_id: str = Field(min_length=1, max_length=120)
    custom: bool = False
    move_id: str | None = Field(default=None, max_length=80, pattern=r'^[A-Za-z0-9_-]+$')


class CalendarWeekSelection(BaseModel):
    day: date


class WeekPlaceholderPlacement(BaseModel):
    week: date
    placeholder: Literal['restaurant', 'fastfood', 'sushi', 'pasta', 'abendbrot', 'resteessen']
    present: bool
    target: str = Field(default='shelf', max_length=10)
    instance_id: str | None = Field(default=None, min_length=1, max_length=80, pattern=r'^[A-Za-z0-9_-]+$')
    create: bool = False


class CalendarUndo(BaseModel):
    move_id: str = Field(min_length=1, max_length=80, pattern=r'^[A-Za-z0-9_-]+$')


class CalendarPlacement(BaseModel):
    week: date
    source: str = Field(max_length=10)
    target: str = Field(max_length=10)
    recipe_id: str = Field(min_length=1, max_length=120)
    custom: bool = False
    move_id: str = Field(min_length=1, max_length=80, pattern=r'^[A-Za-z0-9_-]+$')
    recipe: dict


class RecipeNote(BaseModel):
    text: str = Field(max_length=5000)
    expected: str = Field(max_length=5000)


class CartRecipe(BaseModel):
    recipe_id: str = Field(min_length=1, max_length=129)
    calendar: bool = False


class CartItem(BaseModel):
    name: str = Field(min_length=1, max_length=100)


class CartOwned(BaseModel):
    owned: bool
    owned_revision: int | None = Field(default=None, ge=0)


class CartResolution(BaseModel):
    status: Literal['done', 'pending']


def create_app(directory=None, secure_cookies=None):
    os.umask(0o077)
    database = Database(directory or os.environ.get('REZEPTGARTEN_DATA', './data'))
    vault = Vault(database.directory)
    google_key_vault = Vault(database.directory, 'google-api-key.enc')
    telegram_vault = Vault(database.directory, 'telegram-server-bot.enc')
    telegram_lock = Lock()
    telegram_pending = {}
    telegram_account_lock = asyncio.Lock()
    service = SyncService(database, vault)
    catalog = RecipeCatalog(service)
    @asynccontextmanager
    async def lifespan(app):
        # Remove retired bot pairings while retaining the server token and user session.
        with telegram_lock:
            config = telegram_vault.read() or {}
            legacy_keys = ('client_id', 'cart_key', 'cart_owner', 'android_pair')
            if any(key in config for key in legacy_keys):
                for key in legacy_keys:
                    config.pop(key, None)
                telegram_vault.write(config)
        await service.start()
        yield
        await service.close()

    app = FastAPI(title='Rezeptgarten', version=APP_VERSION, docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)
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
                if request.url.path == '/api/telegram-api':
                    max_length = 92000
                else:
                    max_length = 48000 if request.method == 'PUT' and request.url.path.startswith('/api/notes/') else 16384
                if int(content_length) > max_length:
                    return JSONResponse({'detail': 'Die Anfrage ist zu groß.'}, status_code=413)
            except ValueError:
                return JSONResponse({'detail': 'Ungültige Anfrage.'}, status_code=400)
        if request.method != 'GET' and request.url.path in {
            '/api/connect', '/api/disconnect', '/api/telegram-server-bot',
            '/api/telegram-android-pair', '/api/telegram-android-confirm',
        }:
            async with telegram_account_lock:
                response = await call_next(request)
        else:
            response = await call_next(request)
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Referrer-Policy'] = 'no-referrer'
        response.headers['X-Frame-Options'] = 'DENY'
        response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'; worker-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
        if request.url.path.startswith('/api/'):
            is_image = bool(re.fullmatch(r'/api/(?:images|cookidoo/images)/[a-f0-9]{40}\.webp', request.url.path))
            if not (is_image and request.method == 'GET' and response.status_code == 200):
                response.headers['Cache-Control'] = 'no-store'
            elif 'Cache-Control' not in response.headers:
                response.headers['Cache-Control'] = 'no-store'
        return response

    @app.get('/api/health')
    def health():
        return {'ok': True, 'version': APP_VERSION}

    @app.get('/api/auth/status')
    def auth_status():
        # Compatibility for clients that have not yet reloaded the app shell.
        return {'configured': True, 'authenticated': True}

    @app.get('/api/android-images')
    def android_images(after: str = Query('', pattern=r'^(?:[a-f0-9]{40}\.webp)?$')):
        with database.connect() as connection:
            rows = connection.execute(
                'SELECT DISTINCT image_file FROM recipes '
                'WHERE image_file > ? AND id IN (SELECT recipe_id FROM members) '
                'ORDER BY image_file LIMIT 201', (after,),
            ).fetchall()
        images = [row['image_file'] for row in rows[:200]]
        return {'owner': service.week_collection_owner(), 'images': images,
                'next': images[-1] if len(rows) > 200 else None}

    @app.post('/api/telegram-api')
    async def telegram_api(request: Request):
        if not request.client or request.client.host != '127.0.0.1':
            raise HTTPException(403, 'Nur lokal verfügbar.')
        try:
            envelope = await request.json()
            client_id, nonce, encoded = (envelope[k] for k in ('client_id', 'nonce', 'data'))
            if (type(client_id) is not int or not isinstance(nonce, str)
                    or not re.fullmatch(r'[a-f0-9]{32}', nonce)
                    or not isinstance(encoded, str) or len(encoded) > 90000):
                raise ValueError()
        except (TypeError, ValueError, KeyError):
            raise HTTPException(400, 'Ungültige Anfrage.') from None
        async with telegram_account_lock:
            pair = select_pair(telegram_vault.read() or {}, client_id)
            try:
                payload = open_request(pair, nonce, encoded)
                method, target = payload['method'], payload['path']
                sent, body = payload['sent'], payload.get('body')
                now = time.time()
                if (type(sent) is not int or not now - 180 <= sent <= now + 30
                        or body is not None and not isinstance(body, dict)
                        or not route_allowed(method, target)):
                    raise ValueError()
            except (ValueError, KeyError, InvalidTag, TypeError, OverflowError, zlib.error):
                raise HTTPException(403, 'Ungültige Telegram-Anfrage.') from None
            owner = service.week_collection_owner()
            if (not database.get('account') or pair.get('cart_owner') != owner):
                return {'data': encrypt_response(pair, nonce, 409, {
                    'detail': 'Die Telegram-Kopplung gehört zu einem anderen Cookidoo-Konto. Bitte im Heimnetz erneut koppeln.',
                })}
            if method != 'GET':
                with database.connect() as connection:
                    connection.execute('DELETE FROM telegram_writes WHERE expires < ?', (now,))
                    inserted = connection.execute(
                        'INSERT OR IGNORE INTO telegram_writes VALUES (?,?)', (nonce, sent + 181),
                    ).rowcount
                if not inserted:
                    return {'data': encrypt_response(pair, nonce, 409, {
                        'detail': 'Diese Änderung wurde schon angefragt. Bitte lade den aktuellen Stand.',
                    }, owner)}
            origin = 'http://127.0.0.1:8000'
            try:
                async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app, raise_app_exceptions=False),
                                             base_url=origin, follow_redirects=False) as internal:
                    result = await internal.request(method, target, json=body, headers={'Origin': origin})
                content = result.json()
            except (ValueError, httpx.HTTPError):
                return {'data': encrypt_response(pair, nonce, 502, {
                    'detail': 'Das Ergebnis konnte nicht bestätigt werden. Bitte lade den aktuellen Stand.',
                }, owner)}
            status, revision = result.status_code, None
            if method == 'GET' and status == 200 and result.url.path.split('/')[:3] == ['', 'api', 'recipes']:
                revision = hashlib.sha256(result.content).hexdigest()
                if payload.get('revision') == revision:
                    status, content = 304, None
            return {'data': encrypt_response(pair, nonce, status, content, owner, revision)}

    @app.get('/api/status')
    def status():
        return {'stats': database.stats(), 'connected': service.client is not None, 'account': database.get('account'), 'sync': service.state, 'last_result': database.get('last_result'), 'sync_hours': database.get('sync_hours', 6), 'google_api_key_set': google_key_vault.path.is_file(), 'telegram_server_bot_set': telegram_vault.path.is_file(), 'calendar_queue': service.calendar_queue(), 'cart_recipe_count': database.cart_recipe_count(service.cart_owner())}

    @app.post('/api/telegram-server-bot')
    async def set_telegram_server_bot(request: Request):
        try:
            payload = await request.json()
        except (ValueError, UnicodeDecodeError):
            raise HTTPException(400, 'Bitte gib ein gültiges Bot-Token ein.') from None
        token = payload.get('token') if isinstance(payload, dict) else None
        if not isinstance(token, str) or not re.fullmatch(r'[0-9]{1,20}:[A-Za-z0-9_-]{20,200}', token.strip()):
            raise HTTPException(400, 'Bitte gib ein gültiges Bot-Token ein.')
        with telegram_lock:
            telegram_pending.clear()
            telegram_vault.write({'token': token.strip()})
        return {'ok': True}

    @app.delete('/api/telegram-server-bot')
    def delete_telegram_server_bot():
        with telegram_lock:
            telegram_pending.clear()
            telegram_vault.clear()
        return {'ok': True}

    @app.post('/api/telegram-android-pair')
    async def begin_telegram_android_pair(request: Request):
        try:
            payload = await request.json()
            client_id = payload['client_id']
            cart_key = payload['cart_key']
            if type(client_id) is not int or not 0 < client_id < 2**53:
                raise ValueError()
            if not isinstance(cart_key, str) or len(base64.b64decode(cart_key, validate=True)) != 32:
                raise ValueError()
        except (ValueError, KeyError, TypeError):
            raise HTTPException(400, 'Ungültige Telegram-Kopplung.') from None
        with telegram_lock:
            saved = telegram_vault.read() or {}
        token = saved.get('token')
        owner = service.cart_owner()
        if not token:
            raise HTTPException(409, 'Bitte zuerst das Server-Bot-Token speichern.')
        try:
            async with httpx.AsyncClient(timeout=10, follow_redirects=False) as telegram:
                response = await telegram.post('https://api.telegram.org/bot' + token + '/getMe')
                result = response.json()
            bot = result.get('result') if response.status_code == 200 and result.get('ok') else None
            if not isinstance(bot, dict) or bot.get('is_bot') is not True or type(bot.get('id')) is not int or not re.fullmatch(r'[A-Za-z0-9_]{5,32}', bot.get('username') or ''):
                raise ValueError()
        except (httpx.HTTPError, ValueError, TypeError, AttributeError):
            raise HTTPException(502, 'Server-Bot konnte bei Telegram nicht geprüft werden.') from None
        with telegram_lock:
            current = telegram_vault.read() or {}
            if current.get('token') != token or service.cart_owner() != owner:
                raise HTTPException(409, 'Server-Bot oder Cookidoo-Konto wurde inzwischen geändert.')
            if bot['id'] == client_id:
                raise HTTPException(409, 'Diese Telegram-Kennung ist bereits vergeben.')
            challenge = secrets.token_hex(32)
            telegram_pending.clear()
            telegram_pending.update({'challenge': challenge, 'expires': time.monotonic() + 120,
                                     'token': token, 'client_id': client_id, 'cart_key': cart_key,
                                     'cart_owner': owner})
        return {'challenge': challenge, 'username': bot['username'], 'id': bot['id']}

    @app.post('/api/telegram-android-confirm')
    async def confirm_telegram_android_pair(request: Request):
        if not request.client or request.client.host != '127.0.0.1':
            raise HTTPException(403, 'Nur lokal verfügbar.')
        try:
            payload = await request.json()
            client_id, challenge, token_hash = payload['client_id'], payload['challenge'], payload['token_hash']
        except (ValueError, KeyError, TypeError):
            raise HTTPException(400, 'Ungültige Telegram-Kopplung.') from None
        with telegram_lock:
            pending = telegram_pending
            current = telegram_vault.read() or {}
            if (type(client_id) is not int or not isinstance(challenge, str)
                    or not re.fullmatch(r'[a-f0-9]{64}', challenge)
                    or pending.get('client_id') != client_id
                    or not secrets.compare_digest(pending.get('challenge', ''), challenge)
                    or pending.get('expires', 0) < time.monotonic()
                    or pending.get('token') != current.get('token')
                    or not isinstance(token_hash, str)
                    or not re.fullmatch(r'[a-f0-9]{64}', token_hash)
                    or not secrets.compare_digest(hashlib.sha256(str(current.get('token', '')).encode()).hexdigest(), token_hash)
                    or pending.get('cart_owner') != service.cart_owner()):
                raise HTTPException(409, 'Telegram-Kopplung abgelaufen oder ungültig.')
            current['android_user_pair'] = {key: pending[key] for key in ('client_id', 'cart_key', 'cart_owner')}
            current.pop('android_pair', None)
            telegram_vault.write(current)
            telegram_pending.clear()
        return {'ok': True}

    @app.delete('/api/telegram-android-pair')
    def delete_telegram_android_pair():
        with telegram_lock:
            telegram_pending.clear()
            current = telegram_vault.read() or {}
            if current:
                current.pop('android_user_pair', None)
                current.pop('android_pair', None)
                telegram_vault.write(current)
        return {'ok': True}

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

    @app.get('/api/calendar/week')
    async def calendar_week(day: date | None = None):
        try:
            result = await service.calendar_week(day)
            placements = database.week_placeholder_shelf(service.week_collection_owner(), result['days'][0]['date'])
            result['placeholders'] = [item['placeholder'] for item in placements if item['target'] == 'shelf']
            result['placeholder_placements'] = placements
            return result
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Cookidoo calendar read failed: %s', type(error).__name__)
            raise HTTPException(502, 'Deine Woche konnte nicht von Cookidoo geladen werden. Bitte versuche es erneut.') from None

    @app.get('/api/telegram-week')
    async def telegram_week(request: Request, day: date, nonce: str, compressed: bool = False, client_id: int | None = None):
        if not request.client or request.client.host != '127.0.0.1':
            raise HTTPException(403, 'Nur lokal verfügbar.')
        config = select_pair(telegram_vault.read() or {}, client_id)
        owner = config.get('cart_owner')
        if not owner or owner != service.cart_owner() or owner != service.week_collection_owner():
            raise HTTPException(409, 'Die Bot-Kopplung gehört zu einem anderen Konto.')
        if not re.fullmatch(r'[a-f0-9]{32}', nonce):
            raise HTTPException(400, 'Ungültige Anfrage.')
        try:
            week = await service.calendar_week(day)
            if owner != service.cart_owner() or owner != service.week_collection_owner():
                raise ValueError('account changed')
            queue = service.calendar_queue()
            placements = database.week_placeholder_shelf(owner, week['days'][0]['date'])
            payload = telegram_week_snapshot(week, queue, placements)
            return {'data': encrypt_payload(config, nonce, payload, compressed)}
        except Exception:
            raise HTTPException(502, 'Die Woche konnte nicht geladen werden.') from None

    @app.put('/api/calendar/placeholders')
    def update_week_placeholder(payload: WeekPlaceholderPlacement):
        if payload.week.weekday() != 0:
            raise HTTPException(400, 'Bitte wähle eine gültige Kalenderwoche.')
        if payload.target != 'shelf' and payload.target not in {(payload.week + timedelta(days=i)).isoformat() for i in range(7)}:
            raise HTTPException(400, 'Bitte wähle einen Tag dieser Woche.')
        owner = service.week_collection_owner()
        changed = database.set_week_placeholder_shelf(owner, payload.week.isoformat(), payload.placeholder, payload.present, payload.target, payload.instance_id, payload.create)
        if not changed and payload.instance_id:
            raise HTTPException(404, 'Dieser Platzhalter wurde nicht gefunden. Bitte lade die Woche neu.')
        placements = database.week_placeholder_shelf(owner, payload.week.isoformat())
        return {'items': [item['placeholder'] for item in placements if item['target'] == 'shelf'], 'placements': placements}

    @app.get('/api/calendar/badges')
    async def calendar_badges(recipe_id: list[str] = Query(default=[]), notes_only: bool = False):
        try:
            return await service.calendar_badges(recipe_id, notes_only=notes_only)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Calendar badges failed: %s', type(error).__name__)
            raise HTTPException(502, 'Rezeptangaben konnten nicht aus Cookidoo geladen werden.') from None

    @app.post('/api/calendar/move')
    async def move_calendar_recipe(payload: CalendarMove):
        try:
            return await service.move_calendar_recipe(payload.source, payload.target, payload.recipe_id, payload.custom)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Cookidoo calendar move failed: %s', type(error).__name__)
            raise HTTPException(502, 'Die Woche konnte nicht geprüft werden. Bitte lade sie neu und versuche es erneut.') from None

    @app.post('/api/calendar/queue')
    def enqueue_calendar_move(payload: CalendarMove):
        try:
            return service.enqueue_calendar_move(payload.source, payload.target, payload.recipe_id, payload.custom, payload.move_id)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None

    @app.post('/api/calendar/placement')
    async def enqueue_calendar_placement(payload: CalendarPlacement):
        try:
            verified = None
            if payload.source == 'preview':
                owner = service.week_collection_owner()
                identifier = ('creation:' if payload.custom else '') + payload.recipe_id
                verified = database.recipe(identifier)
                if verified is None:
                    verified = await service.calendar_recipe_details(identifier)
                if owner != service.week_collection_owner():
                    raise ValueError('Das Cookidoo-Konto wurde inzwischen geändert.')
            return service.enqueue_calendar_placement(payload.week, payload.source, payload.target, payload.recipe_id, payload.custom, payload.move_id, payload.recipe, verified_preview=verified)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Week placement preparation failed: %s', type(error).__name__)
            raise HTTPException(502, 'Das Rezept konnte nicht für die Wochenablage geladen werden.') from None

    @app.post('/api/calendar/undo-removal')
    def undo_calendar_removal(payload: CalendarUndo):
        try:
            return service.undo_calendar_removal(payload.move_id)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None

    @app.delete('/api/calendar/queue')
    def discard_failed_calendar_moves():
        try:
            return service.discard_failed_calendar_moves()
        except ValueError as error:
            raise HTTPException(409, str(error)) from None

    @app.post('/api/calendar/save-unfiled')
    async def save_unfiled_calendar_recipes(payload: CalendarWeekSelection):
        try:
            return await service.save_unfiled_calendar_recipes(payload.day)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Cookidoo unfiled calendar save failed: %s', type(error).__name__)
            raise HTTPException(502, 'Die Wochenrezepte konnten nicht sicher in der Cookidoo-Liste gespeichert werden. Bitte prüfe deine Listen, bevor du es erneut versuchst.') from None

    @app.post('/api/calendar/shopping')
    async def add_week_to_shopping(payload: CalendarWeekSelection):
        if service.cart_transferring:
            raise HTTPException(409, 'Bitte warte, bis die Übertragung abgeschlossen ist.')
        try:
            return await service.add_week_to_shopping(payload.day)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Week shopping preparation failed: %s', type(error).__name__)
            raise HTTPException(502, 'Die Wochenplanung oder Rezeptzutaten konnten nicht geladen werden. Der Einkaufswagen wurde nicht verändert.') from None

    def cart_owner():
        return service.cart_owner()

    def cart_editable():
        if service.cart_transferring:
            raise HTTPException(409, 'Bitte warte, bis die Übertragung abgeschlossen ist.')

    @app.get('/api/cart')
    def get_cart():
        items = database.cart(cart_owner())
        pantry = database.pantry()
        pantry_names = [item['name'] for item in pantry['items']]
        item_icons = pantry_item_icons(pantry['items'])
        category_icons = {category['name']: category['icon'] for category in pantry['categories']}
        category_names = {category['id']: category['name'] for category in pantry['categories']}
        pantry_categories = {ingredient_group_key(item['name']): category_names[item['category_id']] for item in pantry['items'] if item['category_id'] in category_names}
        for item in items:
            if item['kind'] == 'recipe':
                for ingredient in item['data'].get('ingredients', []):
                    name = ingredient.get('name') or ingredient_name(ingredient.get('text', ''))
                    ingredient['key'] = ingredient_group_key(name) or ingredient.get('key', '')
                    ingredient['category'] = shopping_category(name, pantry_categories)
                    ingredient['icon'] = item_icons.get(ingredient['key'])
                    ingredient['category_icon'] = shopping_category_icon(ingredient['category'], category_icons)
                    ingredient['in_pantry'] = ingredient_available(name, pantry_names)
                    ingredient['is_water'] = ingredient_group_key(name) == 'wasser'
            elif item['kind'] == 'additional':
                name = item['data'].get('name', '')
                item['data']['category'] = shopping_category(name, pantry_categories)
                item['data']['icon'] = item_icons.get(ingredient_group_key(name))
                item['data']['category_icon'] = shopping_category_icon(item['data']['category'], category_icons)
                item['data']['is_water'] = ingredient_group_key(name) == 'wasser'
        for item in items:
            if item['kind'] == 'recipe':
                if item['data'].get('image_url'):
                    service.calendar_image_reference(item['data']['image_url'])
                if item['data'].get('total_seconds') is None or not item['data'].get('difficulty'):
                    recipe = database.recipe(item['recipe_id']) or {}
                    for key in ('total_seconds', 'difficulty'):
                        if item['data'].get(key) is None and recipe.get(key) is not None:
                            item['data'][key] = recipe[key]
        if not service.cart_transferring:
            for item in items:
                if item['status'] == 'processing':
                    database.cart_update(cart_owner(), item['id'], status='uncertain', expected='processing')
                    item['status'] = 'uncertain'
        return {'items': items, 'transferring': service.cart_transferring}

    async def add_cart_recipe(recipe_id, calendar=False):
        cart_editable()
        if not re.fullmatch(r'(?:creation:)?[A-Za-z0-9_-]{1,120}', recipe_id):
            raise HTTPException(400, 'Ungültige Rezeptkennung.')
        owner = cart_owner()
        recipe = database.recipe(recipe_id)
        if recipe is None:
            if not calendar:
                raise HTTPException(404, 'Dieses Rezept wurde nicht gefunden.')
            try:
                recipe = await service.calendar_recipe_details(recipe_id)
            except ValueError as error:
                raise HTTPException(409, str(error)) from None
            except Exception as error:
                logging.getLogger(__name__).warning('Cart recipe lookup failed: %s', type(error).__name__)
                raise HTTPException(502, 'Die Rezeptzutaten konnten nicht geladen werden.') from None
        cart_editable()
        if owner != cart_owner():
            raise HTTPException(409, 'Das Cookidoo-Konto wurde inzwischen geändert.')
        pantry_names = [item['name'] for item in database.pantry()['items']]
        added = database.cart_add(owner, 'recipe', recipe_snapshot(recipe, pantry_names), recipe_id)
        return {'added': added}

    @app.post('/api/cart/recipes')
    async def cart_add_recipe(payload: CartRecipe):
        return await add_cart_recipe(payload.recipe_id, payload.calendar)

    @app.post('/api/cart/items')
    def cart_add_item(payload: CartItem):
        cart_editable()
        name = payload.name.strip()
        if not name:
            raise HTTPException(400, 'Bitte gib einen Artikel ein.')
        database.cart_add(cart_owner(), 'additional', {'name': name, 'owned': False})
        return {'ok': True}

    def set_cart_owned(entry_id, position, payload, missing):
        cart_editable()
        try:
            result = database.cart_set_owned(cart_owner(), entry_id, position, payload.owned, payload.owned_revision)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        if result is None:
            raise HTTPException(404, missing)
        return {'ok': True, **result}

    @app.put('/api/cart/{entry_id}/ingredients/{position}')
    def cart_ingredient(entry_id: str, position: int, payload: CartOwned):
        return set_cart_owned(entry_id, position, payload, 'Diese Zutat wurde nicht gefunden.')

    @app.put('/api/cart/{entry_id}/owned')
    def cart_item_owned(entry_id: str, payload: CartOwned):
        return set_cart_owned(entry_id, None, payload, 'Dieser Artikel wurde nicht gefunden.')

    @app.post('/api/cart/{entry_id}/resolve')
    def cart_resolve(entry_id: str, payload: CartResolution):
        cart_editable()
        if not database.cart_update(cart_owner(), entry_id, status=payload.status, expected='uncertain'):
            raise HTTPException(409, 'Dieser Eintrag benötigt keine Bestätigung.')
        return {'ok': True}

    @app.delete('/api/cart/{entry_id}')
    def cart_remove(entry_id: str):
        cart_editable()
        if not database.cart_delete(cart_owner(), entry_id):
            raise HTTPException(404, 'Dieser Eintrag wurde nicht gefunden.')
        return {'ok': True}

    @app.delete('/api/cart')
    def cart_clear():
        cart_editable()
        database.cart_delete(cart_owner())
        return {'ok': True}

    @app.post('/api/cart/transfer')
    async def cart_transfer():
        try:
            return await transfer_cart(service)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Cart transfer preparation failed: %s', type(error).__name__)
            raise HTTPException(502, 'Cookidoo konnte nicht gelesen werden. Der Einkaufswagen bleibt erhalten.') from None

    @app.get('/api/notes/{recipe_id}')
    async def get_recipe_note(recipe_id: str):
        try:
            return await service.recipe_note(recipe_id)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Cookidoo note read failed: %s', type(error).__name__)
            raise HTTPException(502, 'Die Notiz konnte nicht aus Cookidoo geladen werden.') from None

    @app.put('/api/notes/{recipe_id}')
    async def save_recipe_note(recipe_id: str, payload: RecipeNote):
        try:
            return await service.recipe_note(recipe_id, payload.text, payload.expected, save=True)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Cookidoo note write failed: %s', type(error).__name__)
            raise HTTPException(502, 'Die Notiz konnte nicht bestätigt werden. Bitte prüfe sie in Cookidoo, bevor du erneut speicherst.') from None

    @app.get('/api/featured-recipe')
    def featured_recipe():
        return database.featured_recipe()

    @app.post('/api/featured-recipe/shuffle')
    def shuffle_featured_recipe():
        return database.featured_recipe(refresh=True)

    @app.get('/api/collections')
    def collections():
        items = database.collections()
        region = (database.get('account') or {}).get('region', 'de')
        language, _, website = REGIONS.get(region, REGIONS['de'])
        for item in items:
            if item['kind'] == 'local':
                continue
            source_id = item['source_id']
            if item['kind'] == 'managed' and re.fullmatch(r'col[0-9]+', source_id):
                item['source_url'] = f'{website}/collection/{language}/p/{source_id}'
            else:
                item['source_url'] = f'{website}/organize/{language}/my-recipes'
        return {'items': items}

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
        return {'id': database.create_local_collection(name, payload.icon)}

    @app.put('/api/local-collections/{collection_id}')
    def update_local_collection(collection_id: str, payload: LocalCollection):
        name = payload.name.strip()
        if not name:
            raise HTTPException(400, 'Bitte gib einen Namen für die Liste ein.')
        if not database.update_local_collection(collection_id, name, payload.icon):
            raise HTTPException(404, 'Diese lokale Rezeptliste wurde nicht gefunden.')
        return {'id': collection_id}

    @app.delete('/api/local-collections/{collection_id}')
    def delete_local_collection(collection_id: str):
        if not database.delete_local_collection(collection_id):
            raise HTTPException(404, 'Diese lokale Rezeptliste wurde nicht gefunden.')
        return {'ok': True}

    @app.put('/api/local-collections/{collection_id}/recipes/{recipe_id}')
    def update_local_membership(collection_id: str, recipe_id: str, payload: Membership):
        if not database.set_local_membership(collection_id, recipe_id, payload.present):
            raise HTTPException(404, 'Liste oder Rezept wurde nicht gefunden.')
        return {'ok': True}

    @app.get('/api/pantry')
    def pantry():
        result = database.pantry()
        result['items'] = [item for item in result['items'] if ingredient_group_key(item['name']) != 'wasser']
        return result

    @app.get('/api/ingredients/suggestions')
    def ingredient_suggestions(q: str = Query('', max_length=100)):
        if not q.strip():
            return {'items': []}
        return {'items': database.ingredient_suggestions(q.strip())}

    @app.delete('/api/pantry/categories/{category_id}')
    def delete_pantry_category(category_id: int):
        if not database.delete_pantry_category(category_id):
            raise HTTPException(404, 'Diese Vorratskategorie wurde nicht gefunden.')
        return {'ok': True}

    @app.post('/api/pantry/categories')
    def create_pantry_category(payload: PantryCategory):
        name = payload.name.strip()
        if not name:
            raise HTTPException(400, 'Bitte gib einen Kategorienamen ein.')
        identifier = database.add_pantry_category(name, payload.icon)
        if identifier is None:
            raise HTTPException(409, 'Diese Kategorie gibt es bereits.')
        return {'id': identifier}

    @app.put('/api/pantry/categories/order')
    def reorder_pantry_categories(payload: PantryOrder):
        if not database.reorder_pantry_categories(payload.category_ids):
            raise HTTPException(409, 'Die Kategorien haben sich geändert. Bitte lade den Vorrat neu.')
        return {'ok': True}

    @app.put('/api/pantry/categories/{category_id}')
    def update_pantry_category(category_id: int, payload: PantryCategory):
        name = payload.name.strip()
        if not name:
            raise HTTPException(400, 'Bitte gib einen Kategorienamen ein.')
        try:
            updated = database.update_pantry_category(category_id, name, payload.icon)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        if not updated:
            raise HTTPException(404, 'Diese Vorratskategorie wurde nicht gefunden.')
        return {'id': category_id}

    def save_pantry(payload: PantryItem, item_id=None):
        name = payload.name.strip()
        if not name:
            raise HTTPException(400, 'Bitte gib einen Zutatennamen ein.')
        try:
            icon = payload.icon if 'icon' in payload.model_fields_set else ...
            identifier = database.save_pantry_item(payload.category_id, name, payload.quantity.strip(), item_id, payload.ingredient_id, icon)
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

    def web_search_criteria(query):
        try:
            return parse_recipe_search(query)
        except ValueError as error:
            raise HTTPException(422, str(error)) from None

    @app.get('/api/search/local')
    def search_local(q: str = Query('', max_length=200), offset: int = Query(0, ge=0)):
        criteria = web_search_criteria(q)
        return database.recipes(query=criteria.text, ingredient=criteria.ingredients,
                                max_minutes=criteria.minutes, exact_servings=criteria.portions,
                                difficulty=criteria.difficulty, title_only=criteria.title_only, offset=offset, limit=48)

    @app.get('/api/recipe-filter-options')
    def library_filter_options():
        return database.recipe_filter_options()

    def recipe_ingredient_metadata(result):
        try:
            ingredients = json.loads(result.get('ingredients_json') or '[]')
        except (TypeError, ValueError):
            ingredients = []
        names = [ingredient_name(value) or (ingredient_name(value.get('description')) if isinstance(value, dict) else '')
                 for value in ingredients] if isinstance(ingredients, list) else []
        keys = [ingredient_group_key(name) for name in names]
        item_icons = pantry_item_icons(database.pantry()['items'])
        result['hidden_ingredient_positions'] = [index for index, key in enumerate(keys) if key == 'wasser']
        result['ingredient_icons'] = {index: item_icons[key] for index, key in enumerate(keys) if key in item_icons}
        return result

    @app.get('/api/recipes/{recipe_id}')
    async def recipe(recipe_id: str, calendar: bool = False):
        result = database.recipe(recipe_id)
        if result is None:
            if not calendar:
                raise HTTPException(404, 'Dieses Rezept wurde nicht gefunden.')
            try:
                result = await service.calendar_recipe_details(recipe_id)
            except ValueError as error:
                raise HTTPException(409, str(error)) from None
            except Exception as error:
                logging.getLogger(__name__).warning('Calendar recipe detail read failed: %s', type(error).__name__)
                raise HTTPException(502, 'Die Rezeptdetails konnten nicht aus Cookidoo geladen werden.') from None
        else:
            result['is_local'] = True
        return recipe_ingredient_metadata(result)

    async def read_catalog(request, message, timeout=12):
        try:
            return await asyncio.wait_for(request, timeout=timeout)
        except CatalogUnavailable as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Cookidoo catalogue read failed: %s', type(error).__name__)
            raise HTTPException(502, message) from None

    @app.get('/api/cookidoo/search')
    async def search_catalog(q: str = Query('', max_length=200),
                             page: int = Query(1, ge=1, le=RecipeCatalog.max_pages * 100)):
        criteria = web_search_criteria(q.strip())
        if criteria.filtered:
            return await read_catalog(catalog.search_filtered(criteria, page),
                                      'Cookidoo konnte gerade nicht durchsucht werden.', timeout=28)
        if page > RecipeCatalog.max_pages:
            raise HTTPException(422, 'Die Cookidoo-Seitenzahl ist ungültig.')
        return await read_catalog(catalog.search(criteria.text, page), 'Cookidoo konnte gerade nicht durchsucht werden.')

    @app.get('/api/cookidoo/recipes/{recipe_id}')
    async def catalog_recipe(recipe_id: str):
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', recipe_id):
            raise HTTPException(404, 'Dieses Cookidoo-Rezept wurde nicht gefunden.')
        result = await read_catalog(catalog.details(recipe_id), 'Dieses Rezept konnte gerade nicht aus Cookidoo geladen werden.')
        return recipe_ingredient_metadata(result)

    async def catalogue_suggestion(refresh=False):
        try:
            result = await asyncio.wait_for(catalog.featured(refresh=refresh), timeout=12)
            if result['recipe']:
                return {**result, 'source': 'cookidoo'}
            message = 'Cookidoo hat gerade keine Rezeptvorschläge geliefert.'
        except CatalogUnavailable as error:
            message = str(error)
        except Exception as error:
            logging.getLogger(__name__).warning('Cookidoo catalogue suggestion failed: %s', type(error).__name__)
            message = 'Der Cookidoo-Vorschlag konnte gerade nicht geladen werden.'
        return {**database.featured_recipe(), 'source': 'local', 'message': message}

    @app.get('/api/cookidoo/featured')
    async def catalogue_featured():
        return await catalogue_suggestion()

    @app.post('/api/cookidoo/featured/shuffle')
    async def shuffle_catalogue_featured():
        return await catalogue_suggestion(refresh=True)

    @app.get('/api/cookidoo/images/{filename}')
    async def catalogue_image(filename: str, size: Literal['thumb'] | None = None):
        if not re.fullmatch(r'[a-f0-9]{40}\.webp', filename):
            raise HTTPException(404)
        try:
            image = await asyncio.wait_for(catalog.image(filename[:-5], size == 'thumb'), timeout=12)
        except Exception:
            raise HTTPException(404) from None
        if image is None:
            raise HTTPException(404)
        return Response(image, media_type='image/webp', headers={'Cache-Control': 'private, max-age=120'})

    @app.get('/api/recipes/{recipe_id}/tips')
    async def recipe_tips(recipe_id: str):
        try:
            return await service.load_recipe_tips(recipe_id)
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Cookidoo recipe tips unavailable: %s', type(error).__name__)
            raise HTTPException(502, 'Die Tipps konnten nicht geladen werden. Bitte versuche es erneut.') from None

    class WeekPlan(BaseModel):
        days: list[date] = Field(min_length=1, max_length=7)

    @app.get('/api/calendar/cooking-days')
    def available_cooking_days():
        return {'days': cooking_days()}

    async def cookidoo_recipe_action(recipe_id: str, calendar: bool, days=None):
        if database.recipe(recipe_id) is None and not (calendar and re.fullmatch(r'(?:creation:)?[A-Za-z0-9_-]{1,120}', recipe_id)):
            raise HTTPException(404, 'Dieses Rezept wurde nicht gefunden.')
        try:
            if days is not None:
                return await service.plan_recipe_days(recipe_id, days)
            return await service.recipe_action(recipe_id, 'plan')
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Cookidoo recipe action failed: %s', type(error).__name__)
            raise HTTPException(502, 'Cookidoo konnte die Aktion nicht bestätigen. Bitte prüfe den Kalender oder die Einkaufsliste, bevor du es erneut versuchst.') from None

    @app.post('/api/recipes/{recipe_id}/plan-today')
    async def plan_today(recipe_id: str, calendar: bool = False):
        return await cookidoo_recipe_action(recipe_id, calendar)

    @app.post('/api/recipes/{recipe_id}/plan-week')
    async def plan_week(recipe_id: str, payload: WeekPlan, calendar: bool = False):
        return await cookidoo_recipe_action(recipe_id, calendar, payload.days)

    @app.post('/api/recipes/{recipe_id}/shopping')
    async def add_to_shopping(recipe_id: str, calendar: bool = False):
        return await add_cart_recipe(recipe_id, calendar)

    @app.get('/api/images/{filename}')
    async def image(filename: str, size: Literal['thumb'] | None = None):
        if not re.fullmatch(r'[a-f0-9]{40}\.webp', filename):
            raise HTTPException(404)
        path = service.images / filename
        if not path.is_file() and not await service.ensure_calendar_image(filename):
            raise HTTPException(404)
        if size == 'thumb':
            try:
                path = await service.thumbnail(filename)
            except Exception as error:
                logging.getLogger(__name__).warning('Image preview unavailable: %s', type(error).__name__)
                return FileResponse(path, media_type='image/webp', headers={'Cache-Control': 'private, max-age=300'})
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

    next_web_sync = 0.0

    @app.post('/api/sync')
    async def sync(automatic: bool = False):
        nonlocal next_web_sync
        now = time.monotonic()
        if automatic and (now < next_web_sync or service.lock.locked()):
            return {'started': False}
        try:
            started = service.begin(manual=not automatic)
            if started:
                next_web_sync = now + 300
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
        html = (STATIC / 'index.html').read_text(encoding='utf-8').replace('<!-- APP_VERSION -->', APP_VERSION)
        return Response(html, media_type='text/html', headers={'Cache-Control': 'no-cache'})

    return app
