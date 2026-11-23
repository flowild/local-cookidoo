"""Authenticated JSON transport for the Android endpoints used over Telegram."""
import base64
import json
import os
import re
import zlib
from urllib.parse import unquote, urlsplit

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

MAX_REQUEST = 64 * 1024
MAX_RESPONSE = 8 * 1024 * 1024
_recipe = r'[A-Za-z0-9_:-]{1,140}'
_item = r'[A-Za-z0-9_-]{1,140}'
_routes = {
    'GET': (
        r'/api/(?:status|featured-recipe|collections|pantry|cart|recipes)',
        r'/api/calendar/(?:week|badges|cooking-days)',
        r'/api/ingredients/suggestions',
        rf'/api/collections/{_recipe}/filter-options',
        rf'/api/recipes/{_recipe}(?:/tips)?',
        rf'/api/notes/{_recipe}',
    ),
    'POST': (
        r'/api/(?:sync|local-collections|featured-recipe/shuffle)',
        r'/api/calendar/(?:placement|undo-removal|save-unfiled|shopping)',
        r'/api/cart/(?:recipes|items|transfer)',
        rf'/api/cart/{_item}/resolve',
        r'/api/pantry/(?:categories|items)',
        rf'/api/recipes/{_recipe}/plan-week',
    ),
    'PUT': (
        r'/api/calendar/placeholders',
        rf'/api/notes/{_recipe}',
        rf'/api/local-collections/{_recipe}(?:/recipes/{_recipe})?',
        rf'/api/cart/{_item}/(?:owned|ingredients/[0-9]+)',
        r'/api/pantry/(?:categories/(?:order|[0-9]+)|items/[0-9]+)',
    ),
    'DELETE': (
        r'/api/calendar/queue',
        rf'/api/(?:cart(?:/{_item})?|local-collections/{_recipe})',
        r'/api/pantry/(?:categories|items)/[0-9]+',
    ),
}


def open_request(pair, nonce, encoded):
    packed = base64.b64decode(encoded, validate=True)
    cipher = AESGCM(base64.b64decode(pair['cart_key'], validate=True))
    compressed = cipher.decrypt(packed[:12], packed[12:], b'request:' + nonce.encode())
    decoder = zlib.decompressobj()
    plain = decoder.decompress(compressed, MAX_REQUEST + 1)
    if len(plain) > MAX_REQUEST or not decoder.eof or decoder.unused_data:
        raise ValueError('invalid request')
    payload = json.loads(plain)
    if not isinstance(payload, dict):
        raise ValueError('invalid request')
    return payload


def route_allowed(method, target):
    if not isinstance(method, str) or not isinstance(target, str) or len(target) > 12000:
        return False
    if any(ord(char) < 33 or ord(char) > 126 for char in target):
        return False
    url = urlsplit(target)
    if url.scheme or url.netloc or '#' in target or not target.startswith('/api/'):
        return False
    path = unquote(url.path, errors='strict')
    return any(re.fullmatch(pattern, path) for pattern in _routes.get(method, ()))


def encrypt_response(pair, nonce, status, payload, owner=None, revision=None):
    response = {'status': status, 'body': payload, 'owner': owner}
    if revision is not None:
        response['revision'] = revision
    data = json.dumps(response, ensure_ascii=False, separators=(',', ':')).encode()
    compressed = zlib.compress(data)
    if len(data) > MAX_RESPONSE or len(compressed) > 1000000:
        return encrypt_response(pair, nonce, 413, {'detail': 'Die Telegram-Antwort ist zu groß.'})
    iv = os.urandom(12)
    cipher = AESGCM(base64.b64decode(pair['cart_key'], validate=True))
    sealed = cipher.encrypt(iv, compressed, b'response:' + nonce.encode())
    return base64.b64encode(iv + sealed).decode()
