"""Read-only access to the Cookidoo catalogue through the shared client."""
import asyncio
import hashlib
import io
import re
import secrets
import time
from datetime import datetime
from urllib.parse import quote
from zoneinfo import ZoneInfo

import httpx
from PIL import Image, ImageOps

from .sync import REGIONS, recipe_image_url


class CatalogUnavailable(Exception):
    pass


class RecipeCatalog:
    page_size = 20
    max_pages = 100
    max_age = 300

    def __init__(self, service):
        self.service = service
        self._owner = None
        self._pages = {}
        self._last_featured = None
        self._images = {}
        self._featured_lock = asyncio.Lock()

    def _account(self):
        service = self.service
        if service.client is None:
            raise CatalogUnavailable('Verbinde dein Cookidoo-Konto, um den Katalog zu öffnen.')
        owner = service.week_collection_owner()
        if owner != self._owner:
            self._owner = owner
            self._pages.clear()
            self._last_featured = None
            self._images.clear()
        return owner

    def _check_session(self, owner, client):
        if self.service.client is not client or self._account() != owner:
            raise CatalogUnavailable('Das Cookidoo-Konto wurde gewechselt. Bitte versuche es erneut.')

    def image_reference(self, url):
        url = recipe_image_url(url)
        if not url:
            return None
        token = hashlib.sha256((self._owner + '\0' + url).encode()).hexdigest()[:40]
        if len(self._images) >= 512 and token not in self._images:
            self._images.pop(next(iter(self._images)))
        self._images[token] = (time.monotonic() + 2 * self.max_age, url)
        return token

    async def image(self, token, thumb):
        owner = self._account()
        expires, url = self._images.get(token, (0, None))
        if time.monotonic() >= expires:
            self._images.pop(token, None)
            return None
        async with self.service.calendar_image_semaphore:
            async with httpx.AsyncClient(timeout=10, follow_redirects=False, trust_env=False) as http:
                data = await self.service.download_recipe_image(url, http)
        if data is None or self._account() != owner:
            return None

        def convert():
            output = io.BytesIO()
            size = 480 if thumb else 960
            with Image.open(io.BytesIO(data)) as original:
                image = ImageOps.exif_transpose(original).convert('RGB')
                image.thumbnail((size, size))
                image.save(output, format='WEBP', quality=84)
            return output.getvalue()

        image = await asyncio.to_thread(convert)
        return image if self._account() == owner else None

    async def search(self, query, page, *, owner=None):
        current_owner = self._account()
        if owner is not None and current_owner != owner:
            raise CatalogUnavailable('Das Cookidoo-Konto wurde gewechselt. Bitte versuche es erneut.')
        service = self.service
        client = service.client
        key = (query.casefold(), page)
        async with service.lock:
            self._check_session(current_owner, client)
            timestamp = time.monotonic()
            cached = self._pages.get(key)
            if cached and timestamp < cached[0]:
                total, recipes, upstream_count = cached[1:]
            else:
                region = (service.database.get('account') or {}).get('region', 'de')
                language, _, website = REGIONS.get(region, REGIONS['de'])
                result = await asyncio.wait_for(client.search_recipes(
                    query or None, languages=language.split('-')[0], page=page - 1,
                    page_size=self.page_size,
                ), timeout=8)
                total = result.total
                upstream_count = len(result.recipes)
                recipes = {}
                for hit in result.recipes:
                    if not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', hit.id):
                        continue
                    recipes.setdefault(hit.id, {
                        'id': hit.id, 'name': hit.name,
                        'source_url': f'{website}/recipes/recipe/{language}/{quote(hit.id, safe="")}',
                        'image_url': hit.thumbnail or hit.image,
                    })
                if len(self._pages) >= 64 and key not in self._pages:
                    self._pages.pop(next(iter(self._pages)))
                self._pages[key] = (timestamp + self.max_age, total, recipes, upstream_count)
        self._check_session(current_owner, client)
        items = [
            {**{key: value for key, value in recipe.items() if key != 'image_url'},
             'catalog_image': self.image_reference(recipe['image_url'])}
            for recipe in recipes.values()
        ]
        first = self._pages.get((key[0], 1))
        first_page_size = first[3] if first else self.page_size
        # Cookidoo can report only the size of the current page as its total.
        full_page = upstream_count >= max(self.page_size, first_page_size)
        has_more = bool(items) and page < self.max_pages and (
            full_page or page * max(first_page_size, 1) < total
        )
        return {'items': items, 'total': total, 'next_page': page + 1 if has_more else None}

    async def details(self, recipe_id):
        owner = self._account()
        client = self.service.client
        recipe = await self.service.remote_recipe_details(
            recipe_id, catalog_reference=self.image_reference, expected_client=client,
        )
        self._check_session(owner, client)
        return recipe

    async def featured(self, refresh=False):
        day = datetime.now(ZoneInfo('Europe/Berlin')).date().isoformat()
        async with self._featured_lock:
            owner = self._account()
            client = self.service.client
            database = self.service.database
            key = 'catalog_featured:' + owner
            previous = database.get(key) or {}
            if previous.get('date') == day and previous.get('id') and not refresh:
                cached = self._last_featured
                if cached and cached[0] > time.monotonic() and cached[1] == previous['id']:
                    return cached[2]
                result = {'date': day, 'recipe': await self.details(previous['id']),
                          'can_shuffle': previous.get('can_shuffle', True)}
                self._check_session(owner, client)
                self._last_featured = (time.monotonic() + self.max_age, previous['id'], result)
                return result
            first = await self.search('', 1, owner=owner)
            candidates = {recipe['id']: recipe for recipe in first['items']}
            first_page_size = self._pages.get(('', 1), (None, None, None, self.page_size))[3] or self.page_size
            last_page = min(self.max_pages, (first['total'] + first_page_size - 1) // first_page_size)
            if first['next_page']:
                page = 2 + secrets.randbelow(max(1, last_page - 1))
                sampled = await self.search('', page, owner=owner)
                candidates.update((recipe['id'], recipe) for recipe in sampled['items'])
            if not candidates:
                return {'date': day, 'recipe': None, 'can_shuffle': False}
            self._check_session(owner, client)
            local = database.catalogued_families(candidates)
            other = [identifier for identifier in candidates if identifier != previous.get('id')]
            unseen = [identifier for identifier in other if identifier not in local]
            selected = secrets.choice(unseen or other or list(candidates))
            recipe = await self.details(selected)
            self._check_session(owner, client)
            can_shuffle = len(candidates) > 1
            database.set(key, {'date': day, 'id': selected, 'can_shuffle': can_shuffle})
            result = {'date': day, 'recipe': recipe, 'can_shuffle': can_shuffle}
            self._last_featured = (time.monotonic() + self.max_age, selected, result)
            return result
