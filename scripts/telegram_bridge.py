"""Respond to explicitly paired Telegram bot pings on the Proxmox host."""
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

STATE = Path('/var/lib/rezeptgarten-telegram/offset.json')
CONFIG_READER = "import sys; sys.path.insert(0, '/opt/cookidoo-manager/source'); from app.security import Vault; import json; print(json.dumps(Vault('/var/lib/cookidoo-manager', 'telegram-server-bot.enc').read()))"


def config():
    result = subprocess.run(['pct', 'exec', '103', '--', '/opt/cookidoo-manager/.venv/bin/python', '-c', CONFIG_READER],
                            capture_output=True, timeout=15, check=True)
    value = json.loads(result.stdout)
    if not isinstance(value, dict) or not isinstance(value.get('token'), str) or not isinstance(value.get('client_id'), int):
        return None
    return value


def call(token, method, payload):
    body = urllib.parse.urlencode(payload).encode()
    request = urllib.request.Request('https://api.telegram.org/bot' + token + '/' + method, data=body)
    with urllib.request.urlopen(request, timeout=35) as response:
        result = json.load(response)
    if not result.get('ok'):
        raise ValueError('Telegram request failed')
    return result['result']


def reply_for(update, client_id, now):
    message = update.get('message') or {}
    sender = message.get('from') or {}
    chat = message.get('chat') or {}
    text = message.get('text') or ''
    match = re.fullmatch(r'rezeptgarten-ping ([a-f0-9]{32})', text)
    if (not match or sender.get('id') != client_id or not sender.get('is_bot')
            or chat.get('type') != 'private' or chat.get('id') != client_id
            or not isinstance(message.get('date'), int) or abs(now - message['date']) > 120):
        return None
    return 'rezeptgarten-pong ' + match.group(1)


def main():
    STATE.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    offset, last_token, last_reply = 0, None, 0.0
    try:
        saved = json.loads(STATE.read_text())
        offset, last_token = saved['offset'], saved['identity']
    except (OSError, ValueError, KeyError, TypeError):
        pass
    import hashlib
    while True:
        try:
            value = config()
            if not value:
                time.sleep(10)
                continue
            token, client_id = value['token'], value['client_id']
            identity = hashlib.sha256(token.encode()).hexdigest()
            if identity != last_token:
                offset, last_token = 0, identity
            updates = call(token, 'getUpdates', {'offset': offset, 'timeout': 20, 'allowed_updates': '["message"]'})
            for update in updates:
                update_id = update.get('update_id')
                if not isinstance(update_id, int):
                    continue
                reply = reply_for(update, client_id, int(time.time()))
                if reply and time.monotonic() - last_reply >= 1:
                    # Recheck pairing after the long poll before sending anything.
                    if config() == value:
                        call(token, 'sendMessage', {'chat_id': client_id, 'text': reply})
                        last_reply = time.monotonic()
                offset = max(offset, update_id + 1)
                temporary = STATE.with_suffix('.tmp')
                temporary.write_text(json.dumps({'offset': offset, 'identity': identity}))
                os.chmod(temporary, 0o600)
                temporary.replace(STATE)
        except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, urllib.error.URLError):
            # Do not log tokens, Telegram URLs, message content or subprocess output.
            time.sleep(10)


if __name__ == '__main__':
    main()
