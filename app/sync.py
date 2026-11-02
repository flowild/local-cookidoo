import asyncio
import dataclasses
import hashlib
import io
import json
import logging
import os
import re
import tempfile
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import quote, urlparse
from zoneinfo import ZoneInfo

import aiohttp
import httpx
from cookidoo_api import Cookidoo
from cookidoo_api.const import CUSTOM_RECIPES_PATH_ACCEPT
from cookidoo_api.types import CookidooAuthData, CookidooConfig, CookidooLocalizationConfig
from PIL import Image, ImageOps

from .storage import now
from .cart import remote_recipe_snapshot
from .ingredients import ingredient_available, ingredient_name
from .recipe_text import readable_instructions

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


class TextOnly(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


def plain_step(value):
    parser = TextOnly()
    parser.feed(value or '')
    return ''.join(parser.parts).strip()


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
        self.thumbnail_semaphore = asyncio.Semaphore(4)
        self.calendar_image_semaphore = asyncio.Semaphore(4)
        self.calendar_image_sources = {}
        self.calendar_image_tasks = {}
        self.lock = asyncio.Lock()
        self.cart_transferring = False
        self.task = None
        self.scheduler = None
        self.calendar_scheduler = None
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
        self.recover_calendar_queue()
        self.calendar_scheduler = asyncio.create_task(self.schedule_calendar_moves())

    async def close(self):
        for task in (self.scheduler, self.calendar_scheduler, self.task):
            if task and not task.done():
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
        image_tasks = list(self.calendar_image_tasks.values())
        for task in image_tasks:
            task.cancel()
        if image_tasks:
            await asyncio.gather(*image_tasks, return_exceptions=True)
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
            old_account = self.database.get('account')
            last_cart_owner = self.database.get('cart_last_owner')
            unassigned_owner = hashlib.sha256(b'\0').hexdigest()
            new_owner = hashlib.sha256((region + '\0' + email).encode()).hexdigest()
            if not old_account and not last_cart_owner:
                self.database.cart_adopt_unassigned(unassigned_owner, new_owner)
            self.database.set('account', {'email': email, 'region': region})
            self.database.set('cart_last_owner', new_owner)
            self.state['message'] = ''

    async def disconnect(self):
        if self.lock.locked() or self.state['running']:
            raise ValueError('Bitte warte, bis die aktuelle Synchronisierung fertig ist.')
        async with self.lock:
            self.vault.clear()
            if self.database.get('account'):
                self.database.set('cart_last_owner', self.week_collection_owner())
            self.database.set('account', None)
            self.client = None
            if self.session:
                await self.session.close()
                self.session = None

    async def _recipe_note_request(self, method, source_id, payload=None):
        """Use the existing token without logging personal note response bodies."""
        region = (self.database.get('account') or {}).get('region', 'de')
        language = REGIONS[region][0]
        base = self.client.api_endpoint / f'recipe-notes/{language}/recipes'
        url = base if method == 'post' else base / source_id
        await self.client._ensure_token()
        headers = {**self.client._api_headers, 'Accept': 'application/json'}
        async with self.client._session.request(method, url, headers=headers, json=payload, allow_redirects=False) as response:
            if response.status == 404:
                return None
            if response.status not in (200, 201, 204):
                raise RuntimeError('Cookidoo note request failed')
            if response.status == 204 or method == 'delete':
                return None
            return await response.json()

    async def _read_recipe_note(self, source_id):
        result = await self._recipe_note_request('get', source_id)
        if result is None:
            return None
        if not isinstance(result, dict) or not isinstance(result.get('text'), str):
            raise RuntimeError('Invalid Cookidoo note response')
        return result['text']

    async def recipe_note(self, recipe_id, text=None, expected=None, save=False):
        if self.lock.locked() or self.state['running']:
            raise ValueError('Bitte warte, bis die aktuelle Synchronisierung fertig ist.')
        source_id = recipe_id.removeprefix('creation:')
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', source_id):
            raise ValueError('Ungültige Rezeptkennung.')
        async with self.lock:
            if not self.client:
                raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
            current = await self._read_recipe_note(source_id)
            if not save:
                return {'text': current or ''}
            if (current or '') != expected:
                raise ValueError('Die Notiz wurde inzwischen in Cookidoo geändert. Bitte lade sie erneut, bevor du speicherst.')
            if text == (current or ''):
                return {'text': text}
            try:
                if not text:
                    await self._recipe_note_request('delete', source_id)
                elif current is None:
                    await self._recipe_note_request('post', source_id, {'recipeId': source_id, 'text': text})
                else:
                    await self._recipe_note_request('put', source_id, {'text': text})
                confirmed = await self._read_recipe_note(source_id)
                if (confirmed or '') != text:
                    raise RuntimeError('Cookidoo note verification failed')
            except Exception as error:
                logger.warning('Cookidoo note write or verification failed: %s', type(error).__name__)
                raise RuntimeError('Die Notiz konnte nicht bestätigt werden. Bitte prüfe sie in Cookidoo, bevor du erneut speicherst.') from None
            return {'text': text}

    def week_collection_owner(self):
        account = self.database.get('account') or {}
        return hashlib.sha256((account.get('region', '') + '\0' + account.get('email', '')).encode()).hexdigest()

    def cart_owner(self):
        if self.database.get('account'):
            return self.week_collection_owner()
        return self.database.get('cart_last_owner') or self.week_collection_owner()

    def calendar_queue(self):
        queue = self.database.get('calendar_move_queue') or {}
        if not queue.get('items'):
            return {'phase': 'idle', 'items': [], 'due': None, 'error': None}
        if queue.get('owner') != self.week_collection_owner():
            return {'phase': 'error', 'items': [], 'due': None, 'error': 'Vorgemerkte Änderungen gehören zu einem anderen Cookidoo-Konto. Bitte verbinde das ursprüngliche Konto erneut.'}
        return {key: queue.get(key) for key in ('phase', 'items', 'due', 'error')}

    def enqueue_calendar_move(self, source, target, recipe_id, custom, move_id=None):
        if not self.client:
            raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
        if source == target or source - timedelta(days=source.weekday()) != target - timedelta(days=target.weekday()):
            raise ValueError('Bitte wähle einen anderen Tag derselben Woche.')
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', recipe_id):
            raise ValueError('Ungültige Rezeptkennung.')
        owner = self.week_collection_owner()
        due = (datetime.now(timezone.utc) + timedelta(minutes=5)).isoformat()
        item = {'source': source.isoformat(), 'target': target.isoformat(), 'recipe_id': recipe_id, 'custom': custom, 'move_id': move_id}
        def update(queue):
            queue = queue or {}
            if queue.get('items') and queue.get('owner') != owner:
                raise ValueError('Vorgemerkte Änderungen gehören zu einem anderen Cookidoo-Konto.')
            if queue.get('items') and queue.get('phase') == 'error':
                raise ValueError('Bitte prüfe zuerst den fehlgeschlagenen Wochenabgleich.')
            if queue.get('phase') == 'processing':
                raise ValueError('Der Wochenabgleich läuft gerade. Bitte versuche es gleich erneut.')
            items = queue.get('items') or []
            if move_id and any(existing.get('move_id') == move_id for existing in items):
                return queue
            if len(items) >= 1000:
                raise ValueError('Zu viele vorgemerkte Änderungen. Bitte warte auf den Abgleich.')
            return {**queue, 'owner': owner, 'phase': 'waiting', 'items': [*items, item], 'due': due, 'error': None}
        self.database.calendar_queue_update(update)
        return self.calendar_queue()

    def enqueue_calendar_placement(self, week, source, target, recipe_id, custom, move_id, recipe):
        if not self.client:
            raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
        monday = week - timedelta(days=week.weekday())
        dates = {(monday + timedelta(days=i)).isoformat() for i in range(7)}
        if source not in dates | {'shelf', 'library'} or target not in dates | {'shelf', 'trash'} or source == target or (source == 'library' and target != 'shelf'):
            raise ValueError('Ungültiges Ziel für diese Woche.')
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', recipe_id):
            raise ValueError('Ungültige Rezeptkennung.')
        if source == 'library':
            local_id = ('creation:' if custom else '') + recipe_id
            with self.database.connect() as db:
                in_local_list = db.execute("SELECT 1 FROM members m JOIN collections c ON c.id=m.collection_id WHERE c.kind='local' AND m.recipe_id=? LIMIT 1", (local_id,)).fetchone()
            recipe = self.database.recipe(local_id) if in_local_list else None
            if not recipe:
                raise ValueError('Das Rezept ist nicht mehr in einer lokalen Liste.')
        owner = self.week_collection_owner()
        # Only retain the display fields needed by the week view.
        snapshot = {'id': ('creation:' if custom else '') + recipe_id, 'calendar_id': recipe_id,
                    'custom': custom, 'name': str(recipe.get('name') or 'Rezept')[:300],
                    'image_file': recipe.get('image_file') if isinstance(recipe.get('image_file'), str) and len(recipe['image_file']) <= 2048 else None,
                    'total_seconds': recipe.get('total_seconds') if isinstance(recipe.get('total_seconds'), (int, float)) else None,
                    'servings': str(recipe.get('servings') or '')[:80], 'has_note': bool(recipe.get('has_note'))}
        item = {'source': source, 'target': target, 'week': monday.isoformat(), 'recipe_id': recipe_id,
                'custom': custom, 'move_id': move_id, 'recipe': snapshot}
        created = datetime.now(timezone.utc)
        due = (created + timedelta(minutes=5)).isoformat()
        if target == 'trash' and source != 'shelf':
            item['not_before'] = (created + timedelta(seconds=10)).isoformat()
        def update(queue):
            queue = queue or {}
            if queue.get('items') and queue.get('owner') != owner:
                raise ValueError('Vorgemerkte Änderungen gehören zu einem anderen Cookidoo-Konto.')
            if queue.get('phase') in ('error', 'processing'):
                raise ValueError('Bitte prüfe zuerst den Wochenabgleich.')
            if move_id in queue.get('recent_placements', []):
                return queue
            items = queue.get('items') or []
            if len(items) >= 1000:
                raise ValueError('Zu viele vorgemerkte Änderungen. Bitte warte auf den Abgleich.')
            shelves = queue.setdefault('shelves', {}).setdefault(owner, {})
            shelf = shelves.setdefault(monday.isoformat(), [])
            match = next((i for i, entry in enumerate(shelf) if entry['calendar_id'] == recipe_id and entry['custom'] == custom), None)
            if source == 'shelf':
                if match is None:
                    raise ValueError('Das Rezept liegt nicht mehr in der Ablage.')
                snapshot.update(shelf.pop(match))
            if target == 'shelf':
                if match is not None:
                    raise ValueError('Das Rezept liegt bereits in der Ablage.')
                shelf.append(snapshot)
            if source != 'library' and (source != 'shelf' or target != 'trash'):
                items.append(item)
                queue.update(owner=owner, phase='waiting', items=items, due=due, error=None)
            elif items:
                queue['due'] = due
            if target == 'trash':
                records = [entry for entry in queue.get('undo_removals', []) if entry.get('expires', '') > created.isoformat()]
                records.append({'owner': owner, 'move_id': move_id, 'week': monday.isoformat(), 'source': source,
                                'recipe': snapshot, 'expires': (created + timedelta(seconds=30)).isoformat()})
                queue['undo_removals'] = records[-100:]
            queue['recent_placements'] = (queue.get('recent_placements', []) + [move_id])[-100:]
            return queue
        self.database.calendar_queue_update(update)
        return self.calendar_queue()

    def undo_calendar_removal(self, move_id):
        owner = self.week_collection_owner()
        current_time = datetime.now(timezone.utc)
        def update(queue):
            queue = queue or {}
            records = queue.get('undo_removals', [])
            record = next((entry for entry in records if entry.get('move_id') == move_id and entry.get('owner') == owner), None)
            if not record or datetime.fromisoformat(record['expires']) < current_time:
                raise ValueError('Das Entfernen kann nicht mehr rückgängig gemacht werden.')
            if queue.get('phase') in ('processing', 'error') or (queue.get('items') and queue.get('owner') != owner):
                raise ValueError('Der Wochenabgleich läuft bereits oder muss zuerst geprüft werden.')
            recipe = record['recipe']
            items = queue.get('items') or []
            if record['source'] == 'shelf':
                shelf = queue.setdefault('shelves', {}).setdefault(owner, {}).setdefault(record['week'], [])
                if any(entry['calendar_id'] == recipe['calendar_id'] and entry['custom'] == recipe['custom'] for entry in shelf):
                    raise ValueError('Das Rezept liegt bereits in der Ablage.')
                shelf.append(recipe)
            else:
                position = next((i for i, item in enumerate(items) if item.get('move_id') == move_id and item.get('target') == 'trash'), None)
                if position is None:
                    raise ValueError('Das Entfernen wurde bereits abgeglichen. Bitte prüfe die Woche in Cookidoo.')
                if any(item.get('recipe_id') == recipe['calendar_id'] and item.get('custom') == recipe['custom'] and item.get('week') == record['week'] for item in items[position + 1:]):
                    raise ValueError('Das Rezept wurde inzwischen weiter verändert. Bitte prüfe die Woche.')
                items.pop(position)
                queue['items'] = items
                if not items:
                    queue.update(phase='idle', due=None, error=None)
            if items:
                queue['due'] = (current_time + timedelta(minutes=5)).isoformat()
            queue['undo_removals'] = [entry for entry in records if entry is not record and entry.get('expires', '') > current_time.isoformat()]
            return queue
        self.database.calendar_queue_update(update)
        return self.calendar_queue()

    def discard_failed_calendar_moves(self):
        def update(queue):
            if not queue or queue.get('phase') != 'error':
                raise ValueError('Es gibt keinen fehlgeschlagenen Wochenabgleich zum Verwerfen.')
            if queue.get('owner') != self.week_collection_owner():
                raise ValueError('Diese Änderungen gehören zu einem anderen Cookidoo-Konto und können hier nicht verworfen werden.')
            return {**queue, 'owner': self.week_collection_owner(), 'phase': 'idle', 'items': [], 'due': None, 'error': None}
        self.database.calendar_queue_update(update)
        return self.calendar_queue()

    def recover_calendar_queue(self):
        def update(queue):
            queue = queue or {}
            if queue.get('phase') == 'processing' and queue.get('items'):
                queue['phase'] = 'error'
                queue['error'] = 'Der Wochenabgleich wurde unterbrochen. Bitte prüfe die Einträge in Cookidoo.'
            return queue
        self.database.calendar_queue_update(update)

    async def schedule_calendar_moves(self):
        while True:
            await asyncio.sleep(1)
            try:
                await self.process_due_calendar_moves()
            except Exception as error:
                logger.warning('Scheduled calendar move failed: %s', type(error).__name__)

    async def process_due_calendar_moves(self):
        if not self.client or self.lock.locked() or self.state['running']:
            return
        owner = self.week_collection_owner()
        pending = self.database.get('calendar_move_queue') or {}
        if pending.get('phase') != 'waiting' or not pending.get('items') or pending.get('owner') != owner:
            return
        if datetime.fromisoformat(pending['due']) > datetime.now(timezone.utc):
            return
        claimed = False
        def claim(queue):
            nonlocal claimed
            queue = queue or {}
            if queue.get('phase') != 'waiting' or not queue.get('items'):
                return queue
            if queue.get('owner') != owner:
                return queue
            if datetime.fromisoformat(queue['due']) > datetime.now(timezone.utc):
                return queue
            queue['phase'] = 'processing'
            claimed = True
            return queue
        queue = self.database.calendar_queue_update(claim)
        if not claimed:
            return
        while queue.get('items'):
            if self.lock.locked() or self.state['running']:
                def defer(current):
                    current['phase'] = 'waiting'
                    current['due'] = datetime.now(timezone.utc).isoformat()
                    return current
                self.database.calendar_queue_update(defer)
                return
            item = queue['items'][0]
            if item.get('not_before') and datetime.fromisoformat(item['not_before']) > datetime.now(timezone.utc):
                def wait_for_undo(current):
                    current['phase'] = 'waiting'
                    current['due'] = item['not_before']
                    return current
                self.database.calendar_queue_update(wait_for_undo)
                return
            try:
                if item['source'] == 'shelf' or item['target'] in ('shelf', 'trash'):
                    result = await self.apply_calendar_placement(item)
                else:
                    result = await self.move_calendar_recipe(datetime.fromisoformat(item['source']).date(), datetime.fromisoformat(item['target']).date(), item['recipe_id'], item['custom'])
                failure = None if result.get('status') == 'moved' else result.get('message', 'Der Wochenabgleich konnte nicht bestätigt werden.')
            except Exception as error:
                logger.warning('Calendar queue operation failed: %s', type(error).__name__)
                failure = 'Der Wochenabgleich konnte nicht abgeschlossen werden. Bitte prüfe die Einträge in Cookidoo.'
            def advance(current):
                if failure:
                    current['phase'] = 'error'; current['error'] = failure
                else:
                    current['items'] = current['items'][1:]
                    if not current['items']:
                        current['phase'] = 'idle'; current['due'] = None; current['error'] = None
                return current
            queue = self.database.calendar_queue_update(advance)
            if failure:
                return

    async def calendar_week(self, requested_day=None):
        """Read the Berlin calendar week directly from the shared Cookidoo client."""
        if self.lock.locked() or self.state['running']:
            raise ValueError('Bitte warte, bis die aktuelle Synchronisierung fertig ist.')
        async with self.lock:
            if not self.client:
                raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
            today = datetime.now(ZoneInfo('Europe/Berlin')).date()
            selected = requested_day or today
            monday = selected - timedelta(days=selected.weekday())
            entries = await self.client.get_recipes_in_calendar_week(monday)
            days = { (monday + timedelta(days=i)).isoformat(): [] for i in range(7) }
            region = (self.database.get('account') or {}).get('region', 'de')
            language, _, website = REGIONS[region]

            async def calendar_recipe(identifier, custom, remote):
                source_id = str(identifier)
                local_id = ('creation:' if custom else '') + source_id
                local = self.database.recipe(local_id)
                name = (local or {}).get('name') or getattr(remote, 'name', None)
                image_file = (local or {}).get('image_file')
                if custom and (not name or not image_file) and not remote:
                    try:
                        remote = await self.client.get_custom_recipe(source_id)
                        name = name or remote.name
                    except Exception as error:
                        logger.warning('Calendar custom recipe lookup failed: %s', type(error).__name__)
                if image_file and not (self.images / image_file).is_file():
                    image_file = None
                if not image_file and remote:
                    image_file = self.calendar_image_reference(getattr(remote, 'thumbnail', None) or getattr(remote, 'image', None))
                safe_id = quote(source_id, safe='')
                source_url = (f'{website}/created-recipes/{language}/{safe_id}/edit' if custom else f'{website}/recipes/recipe/{language}/{safe_id}')
                return {'id': local_id, 'calendar_id': source_id, 'custom': custom, 'name': name or ('Eigene Kreation' if custom else 'Rezept'), 'image_file': image_file, 'source_url': source_url, 'unfiled': not custom and not (local or {}).get('collections'), 'total_seconds': (local or {}).get('total_seconds') or seconds(getattr(remote, 'total_time', None)), 'servings': (local or {}).get('servings') or getattr(remote, 'serving_size', None)}

            for entry in entries:
                day = str(entry.id)
                if day not in days:
                    continue
                seen = set()
                for recipe in entry.recipes:
                    custom = getattr(recipe, 'is_custom', False)
                    days[day].append(await calendar_recipe(recipe.id, custom, recipe))
                    seen.add(str(recipe.id))
                for identifier in entry.customer_recipe_ids:
                    if str(identifier) in seen:
                        continue
                    days[day].append(await calendar_recipe(identifier, True, None))
            tracked = self.database.get('week_unfiled_collection') or {}
            needs_setup = tracked.get('owner') != self.week_collection_owner() or not tracked.get('id')
            stored = self.database.get('calendar_move_queue') or {}
            shelf = stored.get('shelves', {}).get(self.week_collection_owner(), {}).get(monday.isoformat(), [])
            return {'today': today.isoformat(), 'days': [{'date': day, 'recipes': recipes} for day, recipes in days.items()], 'shelf': shelf, 'needs_collection_setup': needs_setup}

    async def calendar_badges(self, recipe_ids):
        """Fetch note presence and missing recipe metadata without exposing note text."""
        if self.lock.locked() or self.state['running']:
            raise ValueError('Bitte warte, bis die aktuelle Synchronisierung fertig ist.')
        if len(recipe_ids) > 100 or any(not re.fullmatch(r'(?:creation:)?[A-Za-z0-9_-]{1,120}', item) for item in recipe_ids):
            raise ValueError('Ungültige Rezeptauswahl.')
        async with self.lock:
            if not self.client:
                raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
            limit = asyncio.Semaphore(4)

            async def badges(recipe_id):
                async with limit:
                    custom = recipe_id.startswith('creation:')
                    source_id = recipe_id.removeprefix('creation:') if custom else recipe_id
                    local = self.database.recipe(recipe_id) or {}
                    total_seconds = local.get('total_seconds')
                    servings = local.get('servings')
                    has_note = None
                    try:
                        note = await self._read_recipe_note(source_id)
                        has_note = bool(note and note.strip())
                    except Exception as error:
                        logger.warning('Calendar note presence unavailable: %s', type(error).__name__)
                    if not total_seconds or not servings:
                        try:
                            detail = await (self.client.get_custom_recipe(source_id) if custom else self.client.get_recipe_details(source_id))
                            total_seconds = total_seconds or seconds(detail.total_time)
                            servings = servings or (str(detail.serving_size) if detail.serving_size else None)
                        except Exception as error:
                            logger.warning('Calendar recipe metadata unavailable: %s', type(error).__name__)
                    return {'id': recipe_id, 'has_note': has_note, 'total_seconds': total_seconds, 'servings': servings}

            return {'items': await asyncio.gather(*(badges(item) for item in dict.fromkeys(recipe_ids)))}

    async def save_unfiled_calendar_recipes(self, day):
        """Save unfiled catalogue recipes from a viewed week in a Cookidoo list."""
        if self.lock.locked() or self.state['running']:
            raise ValueError('Bitte warte, bis die aktuelle Synchronisierung fertig ist.')
        should_sync = False
        async with self.lock:
            if not self.client:
                raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
            monday = day - timedelta(days=day.weekday())
            entries = await self.client.get_recipes_in_calendar_week(monday)
            candidates = set()
            for entry in entries:
                for item in entry.recipes:
                    source_id = str(item.id)
                    if getattr(item, 'is_custom', False) or not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', source_id):
                        continue
                    local = self.database.recipe(source_id)
                    if not local or not local['collections']:
                        candidates.add(source_id)
            owner = self.week_collection_owner()
            tracked = self.database.get('week_unfiled_collection') or {}
            if tracked.get('owner') != owner:
                tracked = {}
            if not candidates and tracked.get('id'):
                return {'added': 0}
            # Use a complete live snapshot before deciding that a recipe is unfiled.
            collections = await self.collections()
            assigned = {member['id'] for collection in collections for member in collection['members']}
            missing = sorted(candidates - assigned)
            custom_lists = [collection for collection in collections if collection['kind'] == 'custom']
            target = next((item for item in custom_lists if item['source_id'] == tracked.get('id')), None)
            if target is None and tracked.get('pending'):
                matches = [item for item in custom_lists if item['name'] == tracked['pending']]
                if len(matches) != 1:
                    raise ValueError('Die Erstellung der Cookidoo-Liste konnte nicht bestätigt werden. Bitte prüfe deine Listen in Cookidoo.')
                target = matches[0]
            if target is None:
                name = 'Rezeptgarten – Wochenrezepte ohne Liste'
                names = {item['name'] for item in custom_lists}
                candidate = name
                suffix = 2
                while candidate in names:
                    candidate = f'{name} ({suffix})'
                    suffix += 1
                self.database.set('week_unfiled_collection', {'owner': owner, 'pending': candidate})
                created = await self.client.add_custom_collection(candidate)
                if not isinstance(created.id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', created.id):
                    raise ValueError('Die Erstellung der Cookidoo-Liste konnte nicht bestätigt werden. Bitte prüfe deine Listen in Cookidoo.')
                target = {'source_id': created.id, 'name': candidate}
                should_sync = True
            self.database.set('week_unfiled_collection', {'owner': owner, 'id': target['source_id']})
            if missing:
                updated = await self.client.add_recipes_to_custom_collection(target['source_id'], missing)
                confirmed = {str(recipe.id) for chapter in (updated.chapters or []) for recipe in (chapter.recipes or [])}
                if not set(missing).issubset(confirmed):
                    raise ValueError('Die Cookidoo-Liste wurde geändert, aber die Rezepte konnten nicht bestätigt werden. Bitte prüfe die Liste in Cookidoo.')
                should_sync = True
            elif candidates:
                # Refresh the local snapshot if Cookidoo already has these recipes in a list.
                should_sync = True
        if should_sync:
            self.begin()
        return {'added': len(missing), 'sync_started': should_sync}

    async def calendar_recipe_details(self, recipe_id):
        """Load a calendar recipe without changing the local library."""
        custom = recipe_id.startswith('creation:')
        source_id = recipe_id.removeprefix('creation:') if custom else recipe_id
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', source_id):
            raise ValueError('Ungültige Rezeptkennung.')
        if self.lock.locked() or self.state['running']:
            raise ValueError('Bitte warte, bis die aktuelle Synchronisierung fertig ist.')
        async with self.lock:
            if not self.client:
                raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
            detail = await (self.client.get_custom_recipe(source_id) if custom else self.client.get_recipe_details(source_id))
            ingredients = [dataclasses.asdict(item) if dataclasses.is_dataclass(item) else item for item in detail.ingredients]
            if custom:
                instructions = readable_instructions([dataclasses.asdict(item) if dataclasses.is_dataclass(item) else item for item in detail.instructions])
            else:
                instructions = [{'title': group.title, 'steps': [plain_step(step.formatted_text) for step in group.recipe_steps]} for group in getattr(detail, 'step_groups', [])]
                instructions = readable_instructions(instructions)
            image_file = None
            try:
                async with httpx.AsyncClient(timeout=25, follow_redirects=False, trust_env=False) as http:
                    image_file = await self.cache_image(detail.image or detail.thumbnail, http)
            except Exception as error:
                logger.warning('Calendar recipe detail image unavailable: %s', type(error).__name__)
            pantry_names = [item['name'] for item in self.database.pantry()['items']]
            availability = {}
            for index, ingredient in enumerate(ingredients):
                name = ingredient_name(ingredient)
                if name:
                    availability[str(index)] = ingredient_available(name, pantry_names)
            region = (self.database.get('account') or {}).get('region', 'de')
            language, _, website = REGIONS[region]
            safe_id = quote(source_id, safe='')
            source_url = (f'{website}/created-recipes/{language}/{safe_id}/edit' if custom else f'{website}/recipes/recipe/{language}/{safe_id}')
            return {'id': recipe_id, 'name': detail.name or 'Rezept', 'image_file': image_file, 'source_url': source_url,
                    'total_seconds': seconds(detail.total_time), 'active_seconds': seconds(detail.active_time),
                    'servings': str(detail.serving_size) if detail.serving_size else None,
                    'difficulty': str(getattr(detail, 'difficulty', '') or '') or None,
                    'ingredients_json': json.dumps(ingredients, ensure_ascii=False),
                    'instructions_json': json.dumps(instructions, ensure_ascii=False),
                    'ingredient_availability': availability, 'collections': [], 'versions': [], 'is_local': False}

    async def apply_calendar_placement(self, item):
        """Apply one add or removal and verify the resulting Cookidoo calendar."""
        if self.lock.locked() or self.state['running']:
            raise ValueError('Bitte warte, bis die aktuelle Synchronisierung fertig ist.')
        async with self.lock:
            if not self.client:
                raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
            monday = datetime.fromisoformat(item['week']).date()
            day = item['target'] if item['source'] == 'shelf' else item['source']
            adding = item['source'] == 'shelf'
            identifier, custom = item['recipe_id'], item['custom']
            async def present():
                entries = await self.client.get_recipes_in_calendar_week(monday)
                for entry in entries:
                    if str(entry.id) == day:
                        return any(str(recipe.id) == identifier and bool(getattr(recipe, 'is_custom', False)) == custom for recipe in entry.recipes) or (custom and identifier in [str(value) for value in entry.customer_recipe_ids])
                return False
            if await present() == adding:
                raise ValueError('Die Woche hat sich in Cookidoo geändert. Bitte prüfe die Einträge.')
            method = (self.client.add_custom_recipes_to_calendar if custom else self.client.add_recipes_to_calendar) if adding else (self.client.remove_custom_recipe_from_calendar if custom else self.client.remove_recipe_from_calendar)
            try:
                await method(datetime.fromisoformat(day).date(), [identifier] if adding else identifier)
                if await present() == adding:
                    return {'status': 'moved'}
            except Exception as error:
                logger.warning('Calendar placement failed: %s', type(error).__name__)
            return {'status': 'uncertain', 'message': 'Die Änderung konnte nicht bestätigt werden. Bitte prüfe die Woche in Cookidoo.'}

    async def move_calendar_recipe(self, source, target, recipe_id, custom):
        """Add and verify before removing; never silently discard an entry."""
        if self.lock.locked() or self.state['running']:
            raise ValueError('Bitte warte, bis die aktuelle Synchronisierung fertig ist.')
        if source == target or source - timedelta(days=source.weekday()) != target - timedelta(days=target.weekday()):
            raise ValueError('Bitte wähle einen anderen Tag derselben Woche.')
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', recipe_id):
            raise ValueError('Ungültige Rezeptkennung.')
        async with self.lock:
            if not self.client:
                raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
            monday = source - timedelta(days=source.weekday())

            async def present():
                entries = await self.client.get_recipes_in_calendar_week(monday)
                result = set()
                for day in entries:
                    ids = ([str(item.id) for item in day.recipes if bool(getattr(item, 'is_custom', False)) == custom]
                           + ([str(item) for item in day.customer_recipe_ids] if custom else []))
                    if recipe_id in ids:
                        result.add(str(day.id))
                return result

            existing = await present()
            if source.isoformat() not in existing:
                raise ValueError('Das Rezept ist am ursprünglichen Tag nicht mehr eingeplant. Bitte lade die Woche neu.')
            if target.isoformat() in existing:
                raise ValueError('Das Rezept ist am Zieltag bereits eingeplant.')
            add = self.client.add_custom_recipes_to_calendar if custom else self.client.add_recipes_to_calendar
            remove = self.client.remove_custom_recipe_from_calendar if custom else self.client.remove_recipe_from_calendar
            try:
                await add(target, [recipe_id])
                if target.isoformat() not in await present():
                    return {'status': 'uncertain', 'message': 'Das Hinzufügen am Zieltag konnte nicht bestätigt werden. Der ursprüngliche Eintrag wurde nicht entfernt. Bitte prüfe Cookidoo.'}
            except Exception as error:
                logger.warning('Calendar move add or verification failed: %s', type(error).__name__)
                return {'status': 'uncertain', 'message': 'Das Hinzufügen am Zieltag konnte nicht bestätigt werden. Der ursprüngliche Eintrag wurde nicht entfernt. Bitte prüfe Cookidoo.'}
            try:
                await remove(source, recipe_id)
                after = await present()
                if source.isoformat() not in after and target.isoformat() in after:
                    return {'status': 'moved'}
            except Exception as error:
                logger.warning('Calendar move removal or verification failed: %s', type(error).__name__)
            return {'status': 'uncertain', 'message': 'Das Rezept wurde am Zieltag bestätigt. Ob der ursprüngliche Eintrag entfernt wurde, konnte nicht bestätigt werden. Bitte prüfe Cookidoo.'}

    async def add_week_to_shopping(self, selected_day):
        """Add future recipes from one week and mark pantry ingredients owned."""
        if self.lock.locked() or self.state['running']:
            raise ValueError('Bitte warte, bis die aktuelle Synchronisierung fertig ist.')
        async with self.lock:
            if not self.client:
                raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
            today = datetime.now(ZoneInfo('Europe/Berlin')).date()
            monday = selected_day - timedelta(days=selected_day.weekday())
            sunday = monday + timedelta(days=6)
            if sunday < today:
                return {'status': 'empty', 'added': 0, 'existing': 0, 'marked': 0}
            queue = self.calendar_queue()
            if queue['phase'] in ('processing', 'error'):
                raise ValueError('Bitte warte auf den Wochenabgleich beziehungsweise prüfe zuerst dessen Fehlermeldung.')
            entries = await self.client.get_recipes_in_calendar_week(monday)
            days = {(monday + timedelta(days=i)).isoformat(): [] for i in range(7)}
            for entry in entries:
                items = days.get(str(entry.id))
                if items is None:
                    continue
                for recipe in entry.recipes:
                    identifier = str(recipe.id)
                    if re.fullmatch(r'[A-Za-z0-9_-]{1,120}', identifier):
                        key = (identifier, bool(getattr(recipe, 'is_custom', False)))
                        if key not in items:
                            items.append(key)
                for identifier in entry.customer_recipe_ids:
                    identifier = str(identifier)
                    if re.fullmatch(r'[A-Za-z0-9_-]{1,120}', identifier) and (identifier, True) not in items:
                        items.append((identifier, True))
            for move in queue['items']:
                source, target = days.get(move['source']), days.get(move['target'])
                if move.get('week') and move['week'] != monday.isoformat():
                    continue
                key = (move['recipe_id'], move['custom'])
                if source is None and move['source'] != 'shelf':
                    continue
                if target is None and move['target'] not in ('shelf', 'trash'):
                    continue
                if (source is not None and key not in source) or (target is not None and key in target):
                    raise ValueError('Die vorgemerkte Woche stimmt nicht mehr mit Cookidoo überein. Bitte prüfe die Planung.')
                if source is not None:
                    source.remove(key)
                if target is not None:
                    target.append(key)
            selected = []
            for day, items in days.items():
                if day >= today.isoformat():
                    for item in items:
                        if item not in selected:
                            selected.append(item)
            stored = self.database.get('calendar_move_queue') or {}
            shelf = stored.get('shelves', {}).get(self.week_collection_owner(), {}).get(monday.isoformat(), [])
            for recipe in shelf:
                key = (recipe['calendar_id'], recipe['custom'])
                if key not in selected:
                    selected.append(key)
            if not selected:
                return {'status': 'empty', 'added': 0, 'existing': 0, 'marked': 0}
            pantry_names = [item['name'] for item in self.database.pantry()['items']]
            owner = self.week_collection_owner()
            recipes = [await remote_recipe_snapshot(self, identifier, custom, pantry_names) for identifier, custom in selected]
            if self.calendar_queue() != queue or (self.database.get('calendar_move_queue') or {}).get('shelves', {}).get(owner, {}).get(monday.isoformat(), []) != shelf:
                raise ValueError('Die Wochenplanung wurde gerade geändert. Bitte versuche es erneut.')
            added = self.database.cart_add_recipes(self.cart_owner(), recipes)
            return {'status': 'ok', 'added': added, 'existing': len(recipes) - added}

    async def recipe_action(self, recipe_id, action):
        if action != 'plan':
            raise ValueError('Diese Rezeptaktion wird nicht unterstützt.')
        if self.lock.locked() or self.state['running']:
            raise ValueError('Bitte warte, bis die aktuelle Synchronisierung fertig ist.')
        async with self.lock:
            if not self.client:
                raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
            custom = recipe_id.startswith('creation:')
            source_id = recipe_id.removeprefix('creation:') if custom else recipe_id
            if action == 'plan':
                day = datetime.now(ZoneInfo('Europe/Berlin')).date()
                method = self.client.add_custom_recipes_to_calendar if custom else self.client.add_recipes_to_calendar
                await method(day, [source_id])
                try:
                    days = await self.client.get_recipes_in_calendar_week(day)
                    today = next((item for item in days if str(item.id) == day.isoformat()), None)
                    ids = ([recipe.id for recipe in today.recipes] + list(today.customer_recipe_ids)) if today else []
                    verified = source_id in ids
                except Exception as error:
                    logger.warning('Calendar verification failed: %s', type(error).__name__)
                    verified = False
                return {'date': day.isoformat(), 'verified': verified}

    async def schedule(self):
        while True:
            await asyncio.sleep(60)
            hours = self.database.get('sync_hours', 6)
            if not hours or not self.client or self.state['running']:
                continue
            last = self.database.get('last_attempt')
            if not last or datetime.now(timezone.utc) - datetime.fromisoformat(last) >= timedelta(hours=hours):
                self.begin()

    def begin(self, manual=False):
        if self.state['running']:
            return False
        if not self.client:
            raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
        if manual:
            owner = self.week_collection_owner()
            def expedite(queue):
                queue = queue or {}
                if queue.get('owner') == owner and queue.get('phase') == 'waiting' and queue.get('items'):
                    queue['due'] = datetime.now(timezone.utc).isoformat()
                return queue
            self.database.calendar_queue_update(expedite)
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
        creations = await self.client.list_custom_recipes()
        origins = await self.creation_origins()
        members = []
        seen = set()
        for creation in creations:
            if not isinstance(creation.id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', creation.id):
                raise ValueError('Invalid created recipe ID')
            if creation.id in seen:
                continue
            seen.add(creation.id)
            members.append({'id': 'creation:' + creation.id, 'name': creation.name or creation.id, 'total_seconds': seconds(creation.total_time), 'chapter': '', 'origin_recipe_id': origins.get(creation.id)})
        if members:
            result.insert(0, {'id': 'creations:default', 'source_id': 'creations', 'kind': 'creations', 'name': 'Meine Kreationen', 'description': 'Deine eigenen Cookidoo-Rezepte.', 'members': members})
        bookmarks = await self.bookmarks()
        if bookmarks:
            result.insert(0, bookmarks)
        return result

    async def creation_origins(self):
        """Read Cookidoo's explicit source link; names are not reliable identities."""
        await self.client._ensure_endpoints()
        path = self.client._path('customer-recipes:recipe-create').format(**self.client._cfg.localization.__dict__)
        payload = await self.client._request_json('get', self.client.api_endpoint / path, 'loading creation origins', headers={'ACCEPT': CUSTOM_RECIPES_PATH_ACCEPT})
        if not isinstance(payload, dict) or not isinstance(payload.get('items'), list):
            raise ValueError('Invalid creation response')
        region = (self.database.get('account') or {}).get('region', 'de')
        website = urlparse(REGIONS[region][2])
        origins = {}
        for item in payload['items']:
            if not isinstance(item, dict) or not isinstance(item.get('recipeContent'), dict):
                raise ValueError('Invalid creation entry')
            creation_id = item.get('recipeId')
            origin = item['recipeContent'].get('isBasedOn')
            if not isinstance(creation_id, str) or not isinstance(origin, str) or not origin:
                continue
            parsed = urlparse(origin)
            match = re.fullmatch(r'/recipes/recipe/[A-Za-z]{2}(?:-[A-Za-z]{2})?/([A-Za-z0-9_-]{1,120})/?', parsed.path)
            if parsed.scheme == 'https' and parsed.hostname == website.hostname and not parsed.username and not parsed.password and parsed.port in (None, 443) and match:
                origins[creation_id] = match.group(1)
        return origins

    def calendar_image_reference(self, url):
        if not url:
            return None
        url = str(url)
        try:
            parsed = urlparse(url)
            host = (parsed.hostname or '').lower()
            if parsed.scheme != 'https' or parsed.username or parsed.password or parsed.port not in (None, 443) or not (host == 'assets.tmecosys.com' or host.endswith('.tmecosys.com')):
                return None
        except ValueError:
            return None
        filename = hashlib.sha256(url.encode()).hexdigest()[:40] + '.webp'
        if not (self.images / filename).is_file():
            if len(self.calendar_image_sources) >= 2000 and filename not in self.calendar_image_sources:
                self.calendar_image_sources.pop(next(iter(self.calendar_image_sources)))
            self.calendar_image_sources[filename] = url
        return filename

    async def ensure_calendar_image(self, filename):
        if (self.images / filename).is_file():
            return True
        url = self.calendar_image_sources.get(filename)
        if not url:
            return False
        task = self.calendar_image_tasks.get(filename)
        if task is None:
            async def download():
                async with self.calendar_image_semaphore:
                    async with httpx.AsyncClient(timeout=25, follow_redirects=False, trust_env=False) as http:
                        return await self.cache_image(url, http)
            task = asyncio.create_task(download())
            self.calendar_image_tasks[filename] = task
            task.add_done_callback(lambda done: self.calendar_image_tasks.pop(filename, None))
        try:
            return bool(await asyncio.shield(task))
        except Exception as error:
            logger.warning('Calendar image download failed: %s', type(error).__name__)
            return False

    async def thumbnail(self, filename):
        """Create a smaller local preview without modifying the original image."""
        source = self.images / filename
        directory = self.images / 'thumbnails'
        target = directory / filename
        if target.is_file():
            return target
        async with self.thumbnail_semaphore:
            if target.is_file():
                return target
            directory.mkdir(exist_ok=True, mode=0o750)

            def create():
                temporary = None
                try:
                    with tempfile.NamedTemporaryFile(dir=directory, suffix='.tmp', delete=False) as output:
                        temporary = Path(output.name)
                    with Image.open(source) as original:
                        image = ImageOps.exif_transpose(original).convert('RGB')
                        image.thumbnail((480, 480))
                        image.save(temporary, format='WEBP', quality=80)
                    os.chmod(temporary, 0o600)
                    os.replace(temporary, target)
                finally:
                    if temporary is not None:
                        temporary.unlink(missing_ok=True)

            await asyncio.to_thread(create)
            return target

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
                temporary = None
                try:
                    with tempfile.NamedTemporaryFile(dir=self.images, suffix='.tmp', delete=False) as output:
                        temporary = Path(output.name)
                    with Image.open(io.BytesIO(image_bytes)) as original:
                        image = ImageOps.exif_transpose(original).convert('RGB')
                        image.thumbnail((960, 960))
                        image.save(temporary, format='WEBP', quality=84)
                    os.chmod(temporary, 0o600)
                    os.replace(temporary, target)
                finally:
                    if temporary is not None:
                        temporary.unlink(missing_ok=True)
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
                        recipes.setdefault(member['id'], {'id': member['id'], 'name': member['name'] or member['id'], 'total_seconds': member.get('total_seconds'), 'source_url': (f'{website}/created-recipes/{language}/{quote(member["id"][9:])}/edit' if collection['kind'] == 'creations' else f'{website}/recipes/recipe/{language}/{quote(member["id"])}'), 'updated_at': now()})
                        if collection['kind'] == 'creations':
                            recipes[member['id']]['origin_recipe_id'] = member.get('origin_recipe_id')
                self.state.update(phase='recipes', total=len(recipes), message='Rezeptdetails und Bilder werden gespeichert …')
                with self.database.connect() as db:
                    existing = {row['id']: dict(row) for row in db.execute('SELECT * FROM recipes')}
                async with httpx.AsyncClient(timeout=25, follow_redirects=False, trust_env=False) as http:
                    for recipe_id, recipe in recipes.items():
                        previous = existing.get(recipe_id)
                        # A cached image and details can be reused for fourteen days.
                        recent = previous and previous.get('detail_updated_at') and datetime.now(timezone.utc) - datetime.fromisoformat(previous['detail_updated_at']) < timedelta(days=14)
                        is_creation = recipe_id.startswith('creation:')
                        if not is_creation and recent and previous.get('instructions_json') is not None and previous.get('image_file') and (self.images / previous['image_file']).exists():
                            for key in ('image_file', 'active_seconds', 'servings', 'difficulty', 'ingredients_json', 'instructions_json', 'detail_updated_at'):
                                recipe[key] = previous[key]
                        else:
                            try:
                                detail = await (self.client.get_custom_recipe(recipe_id[9:]) if is_creation else self.client.get_recipe_details(recipe_id))
                                recipe.update(name=detail.name or recipe['name'], total_seconds=seconds(detail.total_time), active_seconds=seconds(detail.active_time), servings=str(detail.serving_size) if detail.serving_size else None, difficulty=str(getattr(detail, 'difficulty', '') or '') or None, ingredients_json=json.dumps(detail.ingredients, default=lambda value: dataclasses.asdict(value) if dataclasses.is_dataclass(value) else str(value), ensure_ascii=False), detail_updated_at=now())
                                if is_creation:
                                    recipe['instructions_json'] = json.dumps(detail.instructions, default=lambda value: dataclasses.asdict(value) if dataclasses.is_dataclass(value) else str(value), ensure_ascii=False)
                                else:
                                    groups = [{'title': group.title, 'steps': [plain_step(step.formatted_text) for step in group.recipe_steps]} for group in getattr(detail, 'step_groups', [])]
                                    recipe['instructions_json'] = json.dumps(groups, ensure_ascii=False)
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
