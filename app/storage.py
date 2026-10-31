import contextlib
import json
import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


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
            ''')

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=20)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        db.execute('PRAGMA busy_timeout=20000')
        db.create_function('casefold', 1, lambda value: (value or '').casefold(), deterministic=True)
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

    def set(self, key, value):
        with self.connect() as db:
            self.write_setting(db, key, value)

    @staticmethod
    def write_setting(db, key, value):
        db.execute('INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', (key, json.dumps(value)))

    def stats(self):
        with self.connect() as db:
            counts = {
                'collections': db.execute('SELECT count(*) FROM collections').fetchone()[0],
                'recipes': db.execute('SELECT count(*) FROM recipes WHERE id IN (SELECT recipe_id FROM members)').fetchone()[0],
                'images': db.execute('SELECT count(*) FROM recipes WHERE image_file IS NOT NULL AND id IN (SELECT recipe_id FROM members)').fetchone()[0],
            }
        return {**counts, 'last_sync': self.get('last_sync')}

    def collections(self):
        with self.connect() as db:
            rows = db.execute('SELECT c.*,count(m.recipe_id) AS recipe_count FROM collections c LEFT JOIN members m ON m.collection_id=c.id GROUP BY c.id ORDER BY c.position').fetchall()
            results = []
            for row in rows:
                item = dict(row)
                item['images'] = [r['image_file'] for r in db.execute('SELECT r.image_file FROM members m JOIN recipes r ON r.id=m.recipe_id WHERE m.collection_id=? AND r.image_file IS NOT NULL ORDER BY m.position LIMIT 3', (row['id'],))]
                results.append(item)
        return results

    def recipes(self, collection=None, query='', sort='name', offset=0, limit=48):
        clauses = ['EXISTS(SELECT 1 FROM members WHERE recipe_id=r.id)']
        params = []
        if collection:
            clauses.append('EXISTS(SELECT 1 FROM members WHERE recipe_id=r.id AND collection_id=?)')
            params.append(collection)
        if query:
            clauses.append("casefold(r.name) LIKE ? ESCAPE '\\'")
            params.append('%' + query.casefold().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%')
        where = ' AND '.join(clauses)
        order = 'r.total_seconds IS NULL,r.total_seconds,casefold(r.name)' if sort == 'time' else 'casefold(r.name),r.id'
        with self.connect() as db:
            total = db.execute(f'SELECT count(*) FROM recipes r WHERE {where}', params).fetchone()[0]
            rows = db.execute(f'SELECT r.id,r.name,r.image_file,r.source_url,r.total_seconds,r.active_seconds,r.servings,r.difficulty FROM recipes r WHERE {where} ORDER BY {order} LIMIT ? OFFSET ?', [*params, limit, offset]).fetchall()
        return {'items': [dict(row) for row in rows], 'total': total, 'offset': offset, 'limit': limit}

    def recipe(self, recipe_id):
        with self.connect() as db:
            row = db.execute('SELECT id,name,image_file,source_url,total_seconds,active_seconds,servings,difficulty FROM recipes WHERE id=?', (recipe_id,)).fetchone()
            if not row:
                return None
            item = dict(row)
            item['collections'] = [dict(r) for r in db.execute('SELECT c.id,c.name FROM collections c JOIN members m ON m.collection_id=c.id WHERE m.recipe_id=? ORDER BY c.position', (recipe_id,))]
        return item

    def save_snapshot(self, collections, recipes):
        with self.connect() as db:
            for recipe in recipes.values():
                columns = list(recipe)
                updates = ','.join(f'{column}=COALESCE(excluded.{column},recipes.{column})' for column in columns if column != 'id')
                db.execute(f'INSERT INTO recipes({",".join(columns)}) VALUES({",".join("?" for _ in columns)}) ON CONFLICT(id) DO UPDATE SET {updates}', list(recipe.values()))
            db.execute('DELETE FROM collections')
            for position, collection in enumerate(collections):
                db.execute('INSERT INTO collections(id,source_id,kind,name,description,position) VALUES(?,?,?,?,?,?)', (collection['id'], collection['source_id'], collection['kind'], collection['name'], collection.get('description') or '', position))
                for index, member in enumerate(collection['members']):
                    db.execute('INSERT OR IGNORE INTO members(collection_id,recipe_id,position,chapter) VALUES(?,?,?,?)', (collection['id'], member['id'], index, member.get('chapter') or ''))
            db.execute('DELETE FROM recipes WHERE id NOT IN (SELECT recipe_id FROM members)')
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
        return {'format': 'rezeptgarten-v1', 'exported_at': now(), 'collections': self.collections(), 'recipes': recipes, 'members': members}
