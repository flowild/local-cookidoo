"""Select the explicitly confirmed Telegram user pairing."""
import hashlib
import json


def select_pair(config, client_id=None):
    pair = config.get('android_user_pair')
    if isinstance(pair, dict) and type(client_id) is int and client_id == pair.get('client_id'):
        return pair
    return {}


def bridge_config(config):
    pair = config.get('android_user_pair')
    clients = {}
    if isinstance(pair, dict):
        client_id = pair.get('client_id')
        if type(client_id) is int and 0 < client_id < 2**53:
            identity = {key: pair.get(key) for key in ('cart_key', 'cart_owner')}
            clients[str(client_id)] = {
                'identity': hashlib.sha256(json.dumps(identity).encode()).hexdigest(),
                'is_bot': False,
            }
    return {'token': config.get('token'), 'clients': clients}
