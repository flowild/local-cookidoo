"""Create a bounded, encrypted, read-only shopping snapshot for a paired browser."""
import base64
import hashlib
import json
import os
import re
import sqlite3
import sys
import zlib
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from .ingredients import ingredient_group_key, ingredient_name, shopping_category
from .security import Vault


class ReadOnlyCartDatabase:
    def __init__(self, connection):
        self.connection = connection

    def get(self, key):
        row = self.connection.execute('SELECT value FROM settings WHERE key=?', (key,)).fetchone()
        return json.loads(row['value']) if row else None

    def pantry(self):
        return {'categories': [dict(row) for row in self.connection.execute('SELECT id,name FROM pantry_categories')],
                'items': [dict(row) for row in self.connection.execute('SELECT category_id,name FROM pantry_items')]}

    def cart(self, owner):
        return [{'kind': row['kind'], 'data': json.loads(row['data'])} for row in
                self.connection.execute('SELECT kind,data FROM cart_entries WHERE owner=? ORDER BY created_at,id', (owner,))]


def snapshot(database, paired_owner):
    account = database.get('account') or {}
    current = hashlib.sha256((account.get('region', '') + '\0' + account.get('email', '')).encode()).hexdigest()
    owner = current if account else (database.get('cart_last_owner') or current)
    if owner != paired_owner:
        raise ValueError('account changed')
    pantry = database.pantry()
    categories = {c['id']: c['name'] for c in pantry['categories']}
    pantry_categories = {ingredient_group_key(i['name']): categories[i['category_id']] for i in pantry['items'] if i['category_id'] in categories}
    result = []
    for item in database.cart(owner):
        data = item['data']
        if item['kind'] == 'recipe':
            ingredients = []
            for ingredient in data.get('ingredients', []):
                name = ingredient.get('name') or ingredient_name(ingredient.get('text', ''))
                if ingredient_group_key(name) == 'wasser':
                    continue
                ingredients.append({'text': ingredient.get('text', ''), 'owned': bool(ingredient.get('owned')), 'category': shopping_category(name, pantry_categories)})
            result.append({'kind': 'recipe', 'name': data.get('name', ''), 'ingredients': ingredients})
        elif item['kind'] == 'additional' and ingredient_group_key(data.get('name', '')) != 'wasser':
            result.append({'kind': 'additional', 'name': data.get('name', ''), 'owned': bool(data.get('owned'))})
    return result


def encrypted_snapshot(directory, request_id, compress=False):
    if not re.fullmatch(r'[a-f0-9]{32}', request_id):
        raise ValueError('invalid request')
    root = Path(directory)
    if not (root / 'vault.key').is_file() or not (root / 'telegram-server-bot.enc').is_file():
        raise ValueError('not paired')
    config = Vault(directory, 'telegram-server-bot.enc').read() or {}
    if not config.get('cart_owner'):
        raise ValueError('not paired')
    connection = sqlite3.connect((root / 'library.sqlite3').resolve().as_uri() + '?mode=ro', uri=True)
    try:
        connection.row_factory = sqlite3.Row
        connection.execute('BEGIN')
        data = {'items': snapshot(ReadOnlyCartDatabase(connection), config['cart_owner'])}
    finally:
        connection.close()
    return encrypt_payload(config, request_id, data, compress)


def encrypt_payload(config, request_id, payload, compress=False):
    if not re.fullmatch(r'[a-f0-9]{32}', request_id):
        raise ValueError('invalid request')
    key = base64.b64decode(config.get('cart_key', ''), validate=True)
    if len(key) != 32:
        raise ValueError('not paired')
    data = json.dumps(payload, ensure_ascii=False, separators=(',', ':')).encode()
    if len(data) > 40000:
        raise ValueError('cart too large')
    if compress:
        data = zlib.compress(data)
    iv = os.urandom(12)
    ciphertext = AESGCM(key).encrypt(iv, data, request_id.encode())
    return base64.b64encode(iv + ciphertext).decode('ascii')


if __name__ == '__main__':
    try:
        print(encrypted_snapshot('/var/lib/cookidoo-manager', sys.argv[1]))
    except Exception:
        # No tokens, account data or shopping data in logs.
        sys.exit(1)
