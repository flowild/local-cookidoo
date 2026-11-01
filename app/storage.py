import contextlib
import json
import os
import secrets
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

from .ingredients import ingredient_aliases, ingredient_available, ingredient_display_name, ingredient_group_key, ingredient_key, ingredient_name, ingredient_search_text
from .recipe_text import readable_instructions


def now():
    return datetime.now(timezone.utc).isoformat()


class Database:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o750)
        self.path = self.directory / 'library.sqlite3'
        with self.connect() as db:
            db.execute('PRAGMA journal_mode=WAL')
            db.executescript('''
                CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS sessions (token_hash TEXT PRIMARY KEY, expires REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS collections (
                    id TEXT PRIMARY KEY, source_id TEXT NOT NULL, kind TEXT NOT NULL,
                    name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', position INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS recipes (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL, image_file TEXT,
                    source_url TEXT NOT NULL DEFAULT '', total_seconds INTEGER,
                    active_seconds INTEGER, servings TEXT, difficulty TEXT,
                    ingredients_json TEXT, detail_updated_at TEXT, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS members (
                    collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
                    recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL, chapter TEXT NOT NULL DEFAULT '',
                    PRIMARY KEY (collection_id, recipe_id)
                );
                CREATE INDEX IF NOT EXISTS members_recipe ON members(recipe_id);
                CREATE TABLE IF NOT EXISTS pantry_categories (
                    id INTEGER PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS pantry_items (
                    id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL REFERENCES pantry_categories(id),
                    name TEXT NOT NULL, quantity TEXT NOT NULL DEFAULT ''
                );
                CREATE TABLE IF NOT EXISTS ingredient_catalog (
                    id INTEGER PRIMARY KEY, name TEXT NOT NULL, name_key TEXT NOT NULL UNIQUE
                );
                CREATE TABLE IF NOT EXISTS recipe_ingredients (
                    recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL, ingredient_id INTEGER NOT NULL REFERENCES ingredient_catalog(id),
                    original_json TEXT NOT NULL, PRIMARY KEY(recipe_id,position)
                );
                CREATE INDEX IF NOT EXISTS recipe_ingredient_catalog ON recipe_ingredients(ingredient_id);
            ''')
            if not db.execute('SELECT 1 FROM pantry_categories LIMIT 1').fetchone():
                db.executemany('INSERT INTO pantry_categories(name,position) VALUES(?,?)', [(name, index) for index, name in enumerate(('Gewürze', 'Gemüse', 'Obst', 'Fleisch', 'Fisch', 'Soßen', 'Öle und Fette', 'Milchprodukte', 'Vorräte und Konserven', 'Backzutaten', 'Getränke', 'Sonstiges'))])
            columns = {row['name'] for row in db.execute('PRAGMA table_info(recipes)')}
            if 'instructions_json' not in columns:
                db.execute('ALTER TABLE recipes ADD COLUMN instructions_json TEXT')
            if 'origin_recipe_id' not in columns:
                db.execute('ALTER TABLE recipes ADD COLUMN origin_recipe_id TEXT')
            pantry_columns = {row['name'] for row in db.execute('PRAGMA table_info(pantry_items)')}
            if 'ingredient_id' not in pantry_columns:
                db.execute('ALTER TABLE pantry_items ADD COLUMN ingredient_id INTEGER REFERENCES ingredient_catalog(id)')
            self.rebuild_ingredients(db)
            for item in db.execute('SELECT id,name FROM pantry_items WHERE ingredient_id IS NULL').fetchall():
                db.execute('UPDATE pantry_items SET ingredient_id=? WHERE id=?', (self.catalog_id(db, item['name']), item['id']))

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=20)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        db.execute('PRAGMA busy_timeout=20000')
        db.create_function('casefold', 1, lambda value: (value or '').casefold(), deterministic=True)
        db.create_function('ingredient_group_key', 1, lambda value: ingredient_group_key(value or ''), deterministic=True)
        db.create_function('ingredient_search_text', 1, lambda value: ingredient_search_text(value or ''), deterministic=True)
        try:
            yield db
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()

    def get(self, key, default=None):
        with self.connect() as db:
            row = db.execute('SELECT value FROM settings WHERE key=?', (key,)).fetchone()
        return json.loads(row['value']) if row else default

    def pantry(self):
        with self.connect() as db:
            categories = [dict(row) for row in db.execute('SELECT id,name FROM pantry_categories ORDER BY position,id')]
            items = [dict(row) for row in db.execute('SELECT id,category_id,name,quantity,ingredient_id FROM pantry_items ORDER BY casefold(name),id')]
        return {'categories': categories, 'items': items}

    @staticmethod
    def catalog_id(db, name):
        key = ingredient_key(name)
        if not key:
            return None
        db.execute('INSERT INTO ingredient_catalog(name,name_key) VALUES(?,?) ON CONFLICT(name_key) DO NOTHING', (name, key))
        return db.execute('SELECT id FROM ingredient_catalog WHERE name_key=?', (key,)).fetchone()['id']

    @classmethod
    def rebuild_ingredients(cls, db):
        db.execute('DELETE FROM recipe_ingredients')
        for row in db.execute('SELECT id,ingredients_json FROM recipes WHERE ingredients_json IS NOT NULL').fetchall():
            try:
                ingredients = json.loads(row['ingredients_json'])
            except (TypeError, ValueError):
                continue
            if not isinstance(ingredients, list):
                continue
            for position, ingredient in enumerate(ingredients):
                name = ingredient_name(ingredient)
                if not name or len(name) > 200:
                    continue
                identifier = cls.catalog_id(db, name)
                cls.catalog_id(db, ingredient_display_name(name))
                db.execute('INSERT INTO recipe_ingredients(recipe_id,position,ingredient_id,original_json) VALUES(?,?,?,?)', (row['id'], position, identifier, json.dumps(ingredient, ensure_ascii=False)))

    def ingredient_suggestions(self, query, limit=20):
        query = ingredient_key(query)
        with self.connect() as db:
            rows = db.execute("""SELECT c.name,ri.recipe_id FROM ingredient_catalog c
                JOIN recipe_ingredients ri ON ri.ingredient_id=c.id
                JOIN recipes r ON r.id=ri.recipe_id
                WHERE EXISTS (SELECT 1 FROM members m WHERE m.recipe_id=r.id)""").fetchall()
            groups = {}
            for row in rows:
                name = row['name']
                key = ingredient_group_key(name)
                if not key:
                    continue
                group = groups.setdefault(key, {'name': ingredient_display_name(name), 'variants': set(), 'recipes': set()})
                group['variants'].add(ingredient_key(name))
                group['recipes'].add(row['recipe_id'])
            candidates = [group for group in groups.values() if query in ingredient_search_text(group['name']) or any(query in variant for variant in group['variants'])]
            candidates.sort(key=lambda group: (not ingredient_key(group['name']).startswith(query), ingredient_key(group['name'])))
            results = []
            for group in candidates[:limit]:
                row = db.execute('SELECT id FROM ingredient_catalog WHERE name_key=?', (ingredient_key(group['name']),)).fetchone()
                if row:
                    results.append({'id':row['id'], 'name':group['name'], 'recipe_count':len(group['recipes'])})
            return results

    def add_pantry_category(self, name):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            if db.execute('SELECT 1 FROM pantry_categories WHERE casefold(name)=casefold(?)', (name,)).fetchone():
                return None
            return db.execute('INSERT INTO pantry_categories(name,position) VALUES(?,COALESCE((SELECT MAX(position)+1 FROM pantry_categories),0))', (name,)).lastrowid

    def reorder_pantry_categories(self, category_ids):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            existing = {row['id'] for row in db.execute('SELECT id FROM pantry_categories')}
            if len(category_ids) != len(existing) or set(category_ids) != existing:
                return False
            db.executemany('UPDATE pantry_categories SET position=? WHERE id=?', [(position, category_id) for position, category_id in enumerate(category_ids)])
        return True

    def save_pantry_item(self, category_id, name, quantity, item_id=None, ingredient_id=None):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            if not db.execute('SELECT 1 FROM pantry_categories WHERE id=?', (category_id,)).fetchone():
                return None
            if db.execute('SELECT 1 FROM pantry_items WHERE category_id=? AND casefold(name)=casefold(?) AND id!=?', (category_id, name, item_id or 0)).fetchone():
                raise ValueError('Diese Zutat steht bereits in dieser Kategorie.')
            if ingredient_id is not None:
                match = db.execute('SELECT name_key FROM ingredient_catalog WHERE id=?', (ingredient_id,)).fetchone()
                if not match or match['name_key'] != ingredient_key(name):
                    raise ValueError('Bitte wähle die Zutat erneut aus den Vorschlägen aus.')
            else:
                ingredient_id = self.catalog_id(db, name)
            if item_id is None:
                return db.execute('INSERT INTO pantry_items(category_id,name,quantity,ingredient_id) VALUES(?,?,?,?)', (category_id, name, quantity, ingredient_id)).lastrowid
            result = db.execute('UPDATE pantry_items SET category_id=?,name=?,quantity=?,ingredient_id=? WHERE id=?', (category_id, name, quantity, ingredient_id, item_id))
            return item_id if result.rowcount else None

    def delete_pantry_item(self, item_id):
        with self.connect() as db:
            return bool(db.execute('DELETE FROM pantry_items WHERE id=?', (item_id,)).rowcount)

    def set(self, key, value):
        with self.connect() as db:
            self.write_setting(db, key, value)

    def calendar_queue_update(self, update):
        """Atomically update the persisted calendar queue."""
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute("SELECT value FROM settings WHERE key='calendar_move_queue'").fetchone()
            current = json.loads(row['value']) if row else None
            result = update(current)
            self.write_setting(db, 'calendar_move_queue', result)
            return result

    @staticmethod
    def write_setting(db, key, value):
        db.execute('INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', (key, json.dumps(value)))

    def stats(self):
        with self.connect() as db:
            counts = {
                'collections': db.execute('SELECT count(*) FROM collections').fetchone()[0],
                'recipes': db.execute('SELECT count(DISTINCT COALESCE(origin_recipe_id,id)) FROM recipes WHERE id IN (SELECT recipe_id FROM members)').fetchone()[0],
                'images': db.execute('SELECT count(*) FROM recipes WHERE image_file IS NOT NULL AND id IN (SELECT recipe_id FROM members)').fetchone()[0],
            }
        return {**counts, 'last_sync': self.get('last_sync')}

    def featured_recipe(self, refresh=False, day=None):
        day = day or datetime.now(ZoneInfo('Europe/Berlin')).date().isoformat()
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            rows = db.execute('''WITH ranked AS (
                SELECT r.id,r.name,r.image_file,r.total_seconds,r.servings,
                    COALESCE(r.origin_recipe_id,r.id) AS family,
                    ROW_NUMBER() OVER (PARTITION BY COALESCE(r.origin_recipe_id,r.id)
                        ORDER BY (r.origin_recipe_id IS NOT NULL),r.id) AS number
                FROM recipes r WHERE EXISTS(SELECT 1 FROM members m WHERE m.recipe_id=r.id))
                SELECT id,name,image_file,total_seconds,servings,family FROM ranked WHERE number=1 ORDER BY family''').fetchall()
            if not rows:
                return {'date':day, 'recipe':None, 'can_shuffle':False}
            stored = db.execute("SELECT value FROM settings WHERE key='featured_recipe'").fetchone()
            try:
                previous = json.loads(stored['value']) if stored else {}
            except (TypeError, ValueError):
                previous = {}
            if not isinstance(previous, dict):
                previous = {}
            current = next((row for row in rows if row['family'] == previous.get('family')), None)
            if refresh or previous.get('date') != day or current is None:
                choices = [row for row in rows if row['family'] != previous.get('family')]
                current = secrets.choice(choices or rows)
                self.write_setting(db, 'featured_recipe', {'date':day, 'family':current['family']})
            item = dict(current)
            item.pop('family')
            return {'date':day, 'recipe':item, 'can_shuffle':len(rows)>1}

    def collections(self):
        with self.connect() as db:
            rows = db.execute('SELECT c.*,count(DISTINCT COALESCE(r.origin_recipe_id,r.id)) AS recipe_count FROM collections c LEFT JOIN members m ON m.collection_id=c.id LEFT JOIN recipes r ON r.id=m.recipe_id GROUP BY c.id ORDER BY c.position').fetchall()
            results = []
            for row in rows:
                item = dict(row)
                item['images'] = [r['image_file'] for r in db.execute('SELECT r.image_file FROM members m JOIN recipes r ON r.id=m.recipe_id WHERE m.collection_id=? AND r.image_file IS NOT NULL ORDER BY m.position LIMIT 3', (row['id'],))]
                results.append(item)
        return results

    def recipes(self, collection=None, query='', sort='name', offset=0, limit=48, exclude_collection=None, ingredient='', min_servings=None, max_minutes=None, show_all=False, candidate_query=''):
        clauses = ['EXISTS(SELECT 1 FROM members WHERE recipe_id=r.id)']
        params = []
        matches = []
        match_params = []
        if collection:
            clauses.append('EXISTS(SELECT 1 FROM members WHERE recipe_id=r.id AND collection_id=?)')
            params.append(collection)
        if exclude_collection:
            clauses.append('NOT EXISTS(SELECT 1 FROM members m JOIN recipes related ON related.id=m.recipe_id WHERE m.collection_id=? AND COALESCE(related.origin_recipe_id,related.id)=COALESCE(r.origin_recipe_id,r.id))')
            params.append(exclude_collection)
        if candidate_query:
            clauses.append("casefold(r.name) LIKE ? ESCAPE '\\'")
            params.append('%' + candidate_query.casefold().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%')
        if query:
            title_match = "casefold(r.name) LIKE ? ESCAPE '\\'"
            ingredient_match = "EXISTS(SELECT 1 FROM recipe_ingredients ri JOIN ingredient_catalog ic ON ic.id=ri.ingredient_id WHERE ri.recipe_id=r.id AND (ic.name_key LIKE ? ESCAPE '\\' OR ingredient_search_text(ic.name) LIKE ? ESCAPE '\\'))"
            title_needle = '%' + query.casefold().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%'
            ingredient_needle = '%' + ingredient_key(query).replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%'
            search_params = [title_needle, ingredient_needle, ingredient_needle]
            matches.append(f'({title_match} OR {ingredient_match})')
            match_params.extend(search_params)
            search_rank = f'CASE WHEN {title_match} THEN 2 WHEN {ingredient_match} THEN 1 ELSE 0 END'
        else:
            search_rank, search_params = '0', []
        terms = [ingredient] if isinstance(ingredient, str) else ingredient or []
        for term in terms:
            if not term.strip():
                continue
            matches.append("EXISTS(SELECT 1 FROM recipe_ingredients ri JOIN ingredient_catalog ic ON ic.id=ri.ingredient_id WHERE ri.recipe_id=r.id AND (ic.name_key LIKE ? ESCAPE '\\' OR ingredient_search_text(ic.name) LIKE ? ESCAPE '\\'))")
            needle = '%' + ingredient_key(term.strip()).replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%'
            match_params.extend([needle, needle])
        if min_servings is not None:
            matches.append('CAST(r.servings AS REAL) >= ?')
            match_params.append(min_servings)
        if max_minutes is not None:
            matches.append('r.total_seconds <= ?')
            match_params.append(max_minutes * 60)
        where = ' AND '.join(clauses)
        orders = {
            'name': 'casefold(name),id',
            'time': 'total_seconds IS NULL,total_seconds,casefold(name),id',
            'servings': '(CAST(servings AS REAL) <= 0 OR servings IS NULL),CAST(servings AS REAL),casefold(name),id',
            'ingredients': '(ingredient_count=0),ingredient_count,casefold(name),id',
        }
        order = ('family_search_rank DESC,' if query else '') + orders.get(sort, orders['name'])
        with self.connect() as db:
            match_condition = ' AND '.join(matches) or '1=1'
            base = f'''WITH eligible AS (
                SELECT r.id,r.name,r.image_file,r.source_url,r.total_seconds,r.active_seconds,r.servings,r.difficulty,r.origin_recipe_id,
                (SELECT count(*) FROM recipe_ingredients ri WHERE ri.recipe_id=r.id) AS ingredient_count,
                CASE WHEN {match_condition} THEN 1 ELSE 0 END AS matches,
                {search_rank} AS search_rank
                FROM recipes r WHERE {where}), ranked AS (
                SELECT *,MAX(search_rank) OVER (PARTITION BY COALESCE(origin_recipe_id,id)) AS family_search_rank,
                ROW_NUMBER() OVER (PARTITION BY COALESCE(origin_recipe_id,id) ORDER BY matches DESC,search_rank DESC,(origin_recipe_id IS NOT NULL),id) AS family_position FROM eligible)'''
            selection = 'family_position=1' + ('' if show_all else ' AND matches=1')
            arguments = [*match_params, *search_params, *params]
            totals = db.execute(base + f' SELECT count(*) AS total,COALESCE(sum(matches),0) AS matching FROM ranked WHERE {selection}', arguments).fetchone()
            rows = db.execute(base + f' SELECT id,name,image_file,source_url,total_seconds,active_seconds,servings,difficulty,matches,origin_recipe_id FROM ranked WHERE {selection} ORDER BY {order} LIMIT ? OFFSET ?', [*arguments, limit, offset]).fetchall()
            families = list({row['origin_recipe_id'] or row['id'] for row in rows})
            portions = {family: [] for family in families}
            if families:
                placeholders = ','.join('?' for _ in families)
                versions = db.execute(f'''SELECT COALESCE(r.origin_recipe_id,r.id) AS family,r.servings FROM recipes r
                    WHERE COALESCE(r.origin_recipe_id,r.id) IN ({placeholders})
                    AND EXISTS(SELECT 1 FROM members m WHERE m.recipe_id=r.id)
                    ORDER BY (r.origin_recipe_id IS NOT NULL),r.id''', families)
                for version in versions:
                    value = (version['servings'] or '').strip()
                    if value and value not in portions[version['family']]:
                        portions[version['family']].append(value)
        items = []
        for row in rows:
            item = dict(row)
            family = item.pop('origin_recipe_id') or item['id']
            item['matches'] = bool(item['matches'])
            item['version_servings'] = portions[family]
            items.append(item)
        return {'items': items, 'total': totals['total'], 'match_total': totals['matching'], 'offset': offset, 'limit': limit}

    def recipe_filter_options(self, collection_id):
        with self.connect() as db:
            if not db.execute('SELECT 1 FROM collections WHERE id=?', (collection_id,)).fetchone():
                return None
            names = [r['name'] for r in db.execute('''SELECT DISTINCT c.name,c.name_key FROM members m
                JOIN recipe_ingredients ri ON ri.recipe_id=m.recipe_id
                JOIN ingredient_catalog c ON c.id=ri.ingredient_id
                WHERE m.collection_id=? ORDER BY c.name_key''', (collection_id,))]
            rows = db.execute('''SELECT r.servings,r.total_seconds FROM members m JOIN recipes r ON r.id=m.recipe_id
                WHERE m.collection_id=?''', (collection_id,)).fetchall()
        servings = set()
        minutes = set()
        for row in rows:
            value = (row['servings'] or '').strip()
            if value.isdigit() and 1 <= int(value) <= 1000:
                servings.add(int(value))
            if row['total_seconds'] is not None and 0 < row['total_seconds'] <= 10080 * 60:
                minutes.add((row['total_seconds'] + 59) // 60)
        grouped = {}
        for name in names:
            key = ingredient_group_key(name)
            if key:
                grouped.setdefault(key, ingredient_display_name(name))
        ingredients = sorted(grouped.values(), key=ingredient_key)
        return {'ingredients': ingredients, 'ingredient_aliases': {name: ingredient_aliases(name) for name in ingredients}, 'servings': sorted(servings), 'minutes': sorted(minutes)}

    def recipe(self, recipe_id):
        with self.connect() as db:
            row = db.execute('SELECT id,name,image_file,source_url,total_seconds,active_seconds,servings,difficulty,ingredients_json,instructions_json,origin_recipe_id FROM recipes WHERE id=?', (recipe_id,)).fetchone()
            if not row:
                return None
            item = dict(row)
            if item['instructions_json']:
                try:
                    item['instructions_json'] = json.dumps(readable_instructions(json.loads(item['instructions_json'])), ensure_ascii=False)
                except (TypeError, ValueError):
                    pass
            family = item['origin_recipe_id'] or recipe_id
            item['collections'] = [dict(r) for r in db.execute('''SELECT DISTINCT c.id,c.name,c.position FROM collections c JOIN members m ON m.collection_id=c.id
                JOIN recipes r ON r.id=m.recipe_id WHERE COALESCE(r.origin_recipe_id,r.id)=? ORDER BY c.position''', (family,))]
            item['versions'] = [dict(r) for r in db.execute('''SELECT r.id,r.name,r.servings,r.origin_recipe_id FROM recipes r
                WHERE COALESCE(r.origin_recipe_id,r.id)=? AND EXISTS(SELECT 1 FROM members m WHERE m.recipe_id=r.id)
                ORDER BY (r.origin_recipe_id IS NOT NULL),r.id''', (family,))]
            pantry_names = [r['name'] for r in db.execute('SELECT name FROM pantry_items')]
            item['ingredient_availability'] = {str(r['position']): ingredient_available(r['name'], pantry_names) for r in db.execute('''
                SELECT ri.position,c.name FROM recipe_ingredients ri
                JOIN ingredient_catalog c ON c.id=ri.ingredient_id WHERE ri.recipe_id=?''', (recipe_id,))}
        return item

    def create_local_collection(self, name):
        identifier = 'local:' + uuid.uuid4().hex
        with self.connect() as db:
            db.execute("INSERT INTO collections(id,source_id,kind,name,description,position) VALUES(?,?,'local',?,'',COALESCE((SELECT MAX(position)+1 FROM collections),0))", (identifier, identifier, name))
        return identifier

    def set_local_membership(self, collection_id, recipe_id, present):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            if not db.execute("SELECT 1 FROM collections WHERE id=? AND kind='local'", (collection_id,)).fetchone():
                return False
            row = db.execute('SELECT COALESCE(origin_recipe_id,id) AS family FROM recipes WHERE id=?', (recipe_id,)).fetchone()
            if not row:
                return False
            if present:
                if not db.execute('SELECT 1 FROM members m JOIN recipes r ON r.id=m.recipe_id WHERE m.collection_id=? AND COALESCE(r.origin_recipe_id,r.id)=?', (collection_id, row['family'])).fetchone():
                    db.execute('INSERT OR IGNORE INTO members(collection_id,recipe_id,position,chapter) VALUES(?,?,COALESCE((SELECT MAX(position)+1 FROM members WHERE collection_id=?),0),\'\')', (collection_id, recipe_id, collection_id))
            else:
                db.execute('DELETE FROM members WHERE collection_id=? AND recipe_id IN (SELECT id FROM recipes WHERE COALESCE(origin_recipe_id,id)=?)', (collection_id, row['family']))
                db.execute('DELETE FROM recipes WHERE COALESCE(origin_recipe_id,id)=? AND NOT EXISTS (SELECT 1 FROM members WHERE recipe_id=recipes.id)', (row['family'],))
        return True

    def save_snapshot(self, collections, recipes):
        with self.connect() as db:
            for recipe in recipes.values():
                columns = list(recipe)
                updates = ','.join(f'{column}=excluded.{column}' if column == 'origin_recipe_id' else f'{column}=COALESCE(excluded.{column},recipes.{column})' for column in columns if column != 'id')
                db.execute(f'INSERT INTO recipes({",".join(columns)}) VALUES({",".join("?" for _ in columns)}) ON CONFLICT(id) DO UPDATE SET {updates}', list(recipe.values()))
            db.execute("DELETE FROM collections WHERE kind != 'local'")
            for position, collection in enumerate(collections):
                db.execute('INSERT INTO collections(id,source_id,kind,name,description,position) VALUES(?,?,?,?,?,?)', (collection['id'], collection['source_id'], collection['kind'], collection['name'], collection.get('description') or '', position))
                for index, member in enumerate(collection['members']):
                    db.execute('INSERT OR IGNORE INTO members(collection_id,recipe_id,position,chapter) VALUES(?,?,?,?)', (collection['id'], member['id'], index, member.get('chapter') or ''))
            db.execute('DELETE FROM recipes WHERE id NOT IN (SELECT recipe_id FROM members)')
            self.rebuild_ingredients(db)
            self.write_setting(db, 'last_sync', now())

    def backup(self):
        target = self.directory / 'backups'
        target.mkdir(exist_ok=True, mode=0o750)
        stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S-%f')
        path = target / f'library-{stamp}.sqlite3'
        destination = sqlite3.connect(path)
        try:
            with self.connect() as source:
                source.backup(destination)
        finally:
            destination.close()
        os.chmod(path, 0o600)
        for old in sorted(target.glob('library-*.sqlite3'), reverse=True)[7:]:
            old.unlink()

    def export(self):
        with self.connect() as db:
            recipes = [dict(row) for row in db.execute('SELECT * FROM recipes')]
            members = [dict(row) for row in db.execute('SELECT * FROM members ORDER BY collection_id,position')]
        with self.connect() as db:
            catalog = [dict(row) for row in db.execute('SELECT id,name,name_key FROM ingredient_catalog')]
            recipe_ingredients = [dict(row) for row in db.execute('SELECT recipe_id,position,ingredient_id,original_json FROM recipe_ingredients')]
        return {'format': 'rezeptgarten-v1', 'exported_at': now(), 'collections': self.collections(), 'recipes': recipes, 'members': members, 'pantry': self.pantry(), 'ingredient_catalog': catalog, 'recipe_ingredients': recipe_ingredients}
