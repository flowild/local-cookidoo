import asyncio
import dataclasses
import hashlib
import io
import json
import logging
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import quote, urlparse

import aiohttp
import httpx
from cookidoo_api import Cookidoo
from cookidoo_api.types import CookidooAuthData, CookidooConfig, CookidooLocalizationConfig
from PIL import Image, ImageOps

from .storage import now

logger = logging.getLogger(__name__)
Image.MAX_IMAGE_PIXELS = 24_000_000
REGIONS = {
    'de': ('de-DE', 'https://cookidoo.de/foundation/de-DE', 'https://cookidoo.de'),
    'at': ('de-AT', 'https://cookidoo.at/foundation/de-AT', 'https://cookidoo.at'),
    'ch': ('de-CH', 'https://cookidoo.ch/foundation/de-CH', 'https://cookidoo.ch'),
}


def seconds(value):
    if isinstance(value, timedelta):
        return max(0, int(value.total_seconds()))
    if isinstance(value, (int, float)):
        return max(0, int(value))
    return None


def friendly_error(error):
    current = error
    while current:
        if getattr(current, 'status', None) == 429:
            return 'Cookidoo begrenzt gerade die Anfragen. Bitte versuche es später erneut.'
        current = current.__cause__
    if 'Auth' in type(error).__name__:
        return 'Die Cookidoo-Anmeldung ist abgelaufen oder wurde abgelehnt. Bitte verbinde dein Konto erneut.'
    return 'Cookidoo konnte nicht vollständig erreicht werden. Deine bisherige Sammlung bleibt erhalten. Bitte versuche es erneut.'


class SyncService:
    def __init__(self, database, vault):
        self.database = database
        self.vault = vault
        self.images = database.directory / 'images'
        self.images.mkdir(exist_ok=True, mode=0o750)
        self.lock = asyncio.Lock()
        self.task = None
        self.scheduler = None
        self.session = None
        self.client = None
        self.state = {'running': False, 'phase': 'idle', 'done': 0, 'total': 0, 'message': '', 'warnings': 0}

    def make_client(self, email, password, region, session):
        language, foundation, _ = REGIONS[region]
        cfg = CookidooConfig(email=email, password=password, localization=CookidooLocalizationConfig(country_code=region, language=language, url=foundation))

        def persist(auth):
            self.vault.write({'email': email, 'region': region, 'auth': dataclasses.asdict(auth)})

        return Cookidoo(session, cfg=cfg, on_auth_data_update=persist), cfg

    async def start(self):
        try:
            saved = self.vault.read()
            if saved:
                self.session = aiohttp.ClientSession(cookie_jar=aiohttp.CookieJar(unsafe=True), timeout=aiohttp.ClientTimeout(total=45))
                self.client, _ = self.make_client(saved['email'], '', saved['region'], self.session)
                self.client.apply_auth_data(CookidooAuthData(**saved['auth']))
        except Exception as error:
            logger.warning('Cannot restore Cookidoo session: %s', type(error).__name__)
            self.state['message'] = 'Bitte verbinde dein Cookidoo-Konto erneut.'
            self.client = None
        self.scheduler = asyncio.create_task(self.schedule())

    async def close(self):
        for task in (self.scheduler, self.task):
            if task and not task.done():
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
        if self.session:
            await self.session.close()

    async def connect(self, email, password, region):
        if self.lock.locked() or self.state['running']:
            raise ValueError('Bitte warte, bis die aktuelle Synchronisierung fertig ist.')
        async with self.lock:
            session = aiohttp.ClientSession(cookie_jar=aiohttp.CookieJar(unsafe=True), timeout=aiohttp.ClientTimeout(total=45))
            # Preserve the previous working token when a new login fails.
            previous = self.vault.read()
            client, config = self.make_client(email, password, region, session)
            try:
                await client.login()
            except BaseException:
                config.password = ''
                await session.close()
                if previous:
                    self.vault.write(previous)
                else:
                    self.vault.clear()
                raise
            config.password = ''
            if self.session:
                await self.session.close()
            self.client, self.session = client, session
            self.database.set('account', {'email': email, 'region': region})
            self.state['message'] = ''

    async def disconnect(self):
        if self.lock.locked() or self.state['running']:
            raise ValueError('Bitte warte, bis die aktuelle Synchronisierung fertig ist.')
        async with self.lock:
            self.vault.clear()
            self.database.set('account', None)
            self.client = None
            if self.session:
                await self.session.close()
                self.session = None

    async def schedule(self):
        while True:
            await asyncio.sleep(60)
            hours = self.database.get('sync_hours', 6)
            if not hours or not self.client or self.state['running']:
                continue
            last = self.database.get('last_attempt')
            if not last or datetime.now(timezone.utc) - datetime.fromisoformat(last) >= timedelta(hours=hours):
                self.begin()

    def begin(self):
        if self.state['running']:
            return False
        if not self.client:
            raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
        self.state = {'running': True, 'phase': 'lists', 'done': 0, 'total': 0, 'message': 'Rezeptlisten werden geladen …', 'warnings': 0}
        self.task = asyncio.create_task(self.synchronize())
        return True

    async def bookmarks(self):
        """Adapt the bookmark endpoint missing from cookidoo-api 0.19's public API."""
        region = (self.database.get('account') or {}).get('region', 'de')
        language = REGIONS[region][0]
        members = []
        seen = set()
        page = 0
        pages = 1
        while page < pages:
            payload = await self.client._request_json(
                'get', self.client.api_endpoint / f'organize/{language}/api/bookmark',
                'loading bookmarks', params={'page': str(page)},
                headers={'ACCEPT': 'application/vnd.vorwerk.organize.bookmark.mobile+json'},
            )
            if not isinstance(payload, dict) or not isinstance(payload.get('bookmarks'), list):
                raise ValueError('Invalid bookmark response')
            pagination = payload.get('page') or {}
            pages = max(1, int(pagination.get('totalPages', 1)))
            if pages > 10000:
                raise ValueError('Invalid bookmark pagination')
            for item in payload['bookmarks']:
                if not isinstance(item, dict):
                    continue
                recipe = item.get('recipe')
                recipe = recipe if isinstance(recipe, dict) else item
                recipe_id = recipe.get('id') or recipe.get('recipeId')
                if not isinstance(recipe_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', recipe_id) or recipe_id in seen:
                    continue
                name = recipe.get('title') or recipe.get('name') or recipe_id
                members.append({'id': recipe_id, 'name': name if isinstance(name, str) else recipe_id, 'total_seconds': seconds(recipe.get('totalTime')), 'chapter': ''})
                seen.add(recipe_id)
            page += 1
            if page < pages:
                await asyncio.sleep(.15)
        if not members:
            return None
        return {'id': 'bookmarks:default', 'source_id': 'bookmark', 'kind': 'bookmarks', 'name': 'Merkliste', 'description': 'Deine in Cookidoo gemerkten Rezepte.', 'members': members}

    async def collections(self):
        result = []
        for kind in ('custom', 'managed'):
            count_method = getattr(self.client, f'count_{kind}_collections')
            _, pages = await count_method()
            for page in range(pages):
                fetch_method = getattr(self.client, f'get_{kind}_collections')
                for collection in await fetch_method(page=page):
                    members = []
                    for chapter in collection.chapters or []:
                        for recipe in chapter.recipes or []:
                            if not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', recipe.id):
                                continue
                            members.append({'id': recipe.id, 'name': recipe.name, 'total_seconds': seconds(recipe.total_time), 'chapter': chapter.name})
                    result.append({'id': kind + ':' + collection.id, 'source_id': collection.id, 'kind': kind, 'name': collection.name, 'description': collection.description, 'members': members})
                await asyncio.sleep(.15)
        bookmarks = await self.bookmarks()
        if bookmarks:
            result.insert(0, bookmarks)
        return result

    async def cache_image(self, url, http):
        if not url:
            return None
        url = str(url)
        filename = hashlib.sha256(url.encode()).hexdigest()[:40] + '.webp'
        target = self.images / filename
        if target.exists():
            return filename
        # Never forward Cookidoo credentials to image hosts or arbitrary URLs.
        for _ in range(4):
            parsed = urlparse(url)
            host = (parsed.hostname or '').lower()
            if parsed.scheme != 'https' or parsed.username or parsed.password or parsed.port not in (None, 443) or not (host == 'assets.tmecosys.com' or host.endswith('.tmecosys.com')):
                return None
            async with http.stream('GET', url) as response:
                if response.is_redirect:
                    url = str(response.url.join(response.headers['location']))
                    continue
                response.raise_for_status()
                data = bytearray()
                async for chunk in response.aiter_bytes():
                    data.extend(chunk)
                    if len(data) > 10 * 1024 * 1024:
                        return None
                image_bytes = bytes(data)
            def convert():
                with Image.open(io.BytesIO(image_bytes)) as original:
                    image = ImageOps.exif_transpose(original).convert('RGB')
                    image.thumbnail((960, 960))
                    temporary = target.with_suffix('.tmp')
                    image.save(temporary, format='WEBP', quality=84)
                    os.replace(temporary, target)
            await asyncio.to_thread(convert)
            return filename
        return None

    async def synchronize(self):
        async with self.lock:
            self.database.set('last_attempt', now())
            try:
                collections = await self.collections()
                recipes = {}
                account = self.database.get('account') or {}
                region = account.get('region', 'de')
                language, _, website = REGIONS[region]
                for collection in collections:
                    for member in collection['members']:
                        recipes.setdefault(member['id'], {'id': member['id'], 'name': member['name'] or member['id'], 'total_seconds': member.get('total_seconds'), 'source_url': f'{website}/recipes/recipe/{language}/{quote(member["id"])}', 'updated_at': now()})
                self.state.update(phase='recipes', total=len(recipes), message='Rezeptdetails und Bilder werden gespeichert …')
                with self.database.connect() as db:
                    existing = {row['id']: dict(row) for row in db.execute('SELECT * FROM recipes')}
                async with httpx.AsyncClient(timeout=25, follow_redirects=False, trust_env=False) as http:
                    for recipe_id, recipe in recipes.items():
                        previous = existing.get(recipe_id)
                        # A cached image and details can be reused for fourteen days.
                        recent = previous and previous.get('detail_updated_at') and datetime.now(timezone.utc) - datetime.fromisoformat(previous['detail_updated_at']) < timedelta(days=14)
                        if recent and previous.get('image_file') and (self.images / previous['image_file']).exists():
                            for key in ('image_file', 'active_seconds', 'servings', 'difficulty', 'ingredients_json', 'detail_updated_at'):
                                recipe[key] = previous[key]
                        else:
                            try:
                                detail = await self.client.get_recipe_details(recipe_id)
                                recipe.update(name=detail.name or recipe['name'], total_seconds=seconds(detail.total_time), active_seconds=seconds(detail.active_time), servings=str(detail.serving_size) if detail.serving_size else None, difficulty=str(detail.difficulty) if detail.difficulty else None, ingredients_json=json.dumps(detail.ingredients, default=lambda value: dataclasses.asdict(value) if dataclasses.is_dataclass(value) else str(value), ensure_ascii=False), detail_updated_at=now())
                                try:
                                    recipe['image_file'] = await self.cache_image(detail.image or detail.thumbnail, http)
                                    if not recipe['image_file']:
                                        self.state['warnings'] += 1
                                except Exception as error:
                                    logger.warning('Recipe image unavailable: %s', type(error).__name__)
                                    self.state['warnings'] += 1
                            except Exception as error:
                                if 'Auth' in type(error).__name__:
                                    raise
                                logger.warning('Recipe details unavailable: %s', type(error).__name__)
                                self.state['warnings'] += 1
                            await asyncio.sleep(.2)
                        self.state['done'] += 1
                # One transaction replaces list membership only after every list was read.
                self.database.backup()
                self.database.save_snapshot(collections, recipes)
                message = 'Deine Sammlung ist aktuell.' if not self.state['warnings'] else 'Listen gespeichert. Einige Rezeptdetails oder Bilder waren nicht verfügbar.'
                if not collections:
                    message = 'Cookidoo hat keine Rezeptlisten, Kollektionen oder gemerkten Rezepte zurückgegeben. Bitte prüfe das verbundene Konto und dessen Land.'
                self.state.update(phase='done', message=message)
                self.database.set('last_result', {**self.state, 'running': False, 'finished_at': now()})
            except asyncio.CancelledError:
                self.state.update(phase='error', message='Synchronisierung unterbrochen. Deine bisherige Sammlung bleibt erhalten.')
                raise
            except Exception as error:
                logger.warning('Cookidoo synchronization failed: %s', type(error).__name__)
                self.state.update(phase='error', message=friendly_error(error))
                self.database.set('last_result', {**self.state, 'running': False, 'finished_at': now()})
            finally:
                self.state['running'] = False
