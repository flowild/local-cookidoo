"""Choose the Telegram pairing for an explicitly identified client bot."""
import hashlib
import json


def select_pair(config, client_id=None):
    # The top-level pairing remains readable by the existing browser bridge.
    if client_id is None or client_id == config.get('client_id'):
        return config
    android = config.get('android_pair')
    if isinstance(android, dict) and client_id == android.get('client_id'):
        return android
    return {}


def bridge_config(config):
    clients = {}
    android = config.get('android_pair')
    for pair in (config, android):
        if not isinstance(pair, dict):
            continue
        client_id = pair.get('client_id')
        if type(client_id) is not int or not 0 < client_id < 2**53:
            continue
        # Compare complete pairings across a long poll without copying raw keys
        # to the Proxmox host.
        identity = {key: pair.get(key) for key in ('cart_key', 'cart_owner')}
        clients[str(client_id)] = hashlib.sha256(json.dumps(identity).encode()).hexdigest()
    return {'token': config.get('token'), 'clients': clients}
