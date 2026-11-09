"""Respond to explicitly paired Telegram bot pings on the Proxmox host."""
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

STATE = Path('/var/lib/rezeptgarten-telegram/offset.json')
CONFIG_READER = "import sys; sys.path.insert(0, '/opt/cookidoo-manager/source'); from app.security import Vault; import json; v=Vault('/var/lib/cookidoo-manager', 'telegram-server-bot.enc').read() or {}; print(json.dumps({k:v.get(k) for k in ('token','client_id')}))"
CART_READER = "import sys; sys.path.insert(0, '/opt/cookidoo-manager/source'); from app.telegram_cart import encrypted_snapshot; print(encrypted_snapshot('/var/lib/cookidoo-manager', sys.argv[1], sys.argv[2] == 'compressed'))"
WEEK_READER = "import sys,json,urllib.parse,urllib.request; q=urllib.parse.urlencode({'nonce':sys.argv[1],'day':sys.argv[2],'compressed':sys.argv[3]}); r=urllib.request.urlopen('http://127.0.0.1:8000/api/telegram-week?'+q,timeout=45); print(json.load(r)['data'])"


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
    match = re.fullmatch(r'rezeptgarten-(ping|cart|cartz|week|weekz) ([a-f0-9]{32})(?: (\d{4}-\d{2}-\d{2}))?', text)
    if (not match or sender.get('id') != client_id or not sender.get('is_bot')
            or chat.get('type') != 'private' or chat.get('id') != client_id
            or not isinstance(message.get('date'), int) or abs(now - message['date']) > 120):
        return None
    command, nonce, day = match.groups()
    if command in ('week', 'weekz'):
        try:
            if not day or date.fromisoformat(day).weekday() != 0:
                return None
        except ValueError:
            return None
        return f'rezeptgarten-{command} {nonce} {day}'
    if day:
        return None
    if command == 'ping':
        return 'rezeptgarten-pong ' + nonce
    return 'rezeptgarten-' + command + ' ' + nonce


def cart_messages(nonce, compress=False):
    result = subprocess.run(['pct', 'exec', '103', '--', '/opt/cookidoo-manager/.venv/bin/python', '-c', CART_READER, nonce, 'compressed' if compress else 'plain'],
                            capture_output=True, timeout=20, check=True)
    encoded = result.stdout.decode('ascii').strip()
    if not re.fullmatch(r'[A-Za-z0-9+/=]{1,54000}', encoded):
        raise ValueError('invalid encrypted response')
    pieces = [encoded[i:i + 3000] for i in range(0, len(encoded), 3000)]
    return [f'rezeptgarten-cart-part {nonce} {i + 1}/{len(pieces)} {piece}' for i, piece in enumerate(pieces)]


def week_messages(nonce, day, compress=False):
    result = subprocess.run(['pct', 'exec', '103', '--', '/opt/cookidoo-manager/.venv/bin/python', '-c', WEEK_READER, nonce, day, 'true' if compress else 'false'],
                            capture_output=True, timeout=50, check=True)
    encoded = result.stdout.decode('ascii').strip()
    if not re.fullmatch(r'[A-Za-z0-9+/=]{1,54000}', encoded):
        raise ValueError('invalid encrypted response')
    pieces = [encoded[i:i + 3000] for i in range(0, len(encoded), 3000)]
    return [f'rezeptgarten-week-part {nonce} {i + 1}/{len(pieces)} {piece}' for i, piece in enumerate(pieces)]


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
                if reply:
                    time.sleep(max(0, 1 - (time.monotonic() - last_reply)))
                    # Recheck pairing after the long poll before sending anything.
                    if config() == value:
                        if reply.startswith(('rezeptgarten-cart ', 'rezeptgarten-cartz ')):
                            nonce = reply.split(' ')[1]
                            try:
                                messages = cart_messages(nonce, compress=reply.startswith('rezeptgarten-cartz '))
                            except (OSError, ValueError, subprocess.SubprocessError):
                                messages = ['rezeptgarten-cart-error ' + nonce]
                        elif reply.startswith(('rezeptgarten-week ', 'rezeptgarten-weekz ')):
                            _, nonce, day = reply.split(' ')
                            try:
                                messages = week_messages(nonce, day, compress=reply.startswith('rezeptgarten-weekz '))
                            except (OSError, ValueError, subprocess.SubprocessError):
                                messages = ['rezeptgarten-week-error ' + nonce]
                        else:
                            messages = [reply]
                        for index, message in enumerate(messages):
                            if index:
                                time.sleep(1.1)
                            if config() != value:
                                break
                            call(token, 'sendMessage', {'chat_id': client_id, 'text': message})
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
