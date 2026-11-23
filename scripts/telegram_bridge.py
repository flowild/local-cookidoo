"""Serve explicitly paired Telegram clients from the Proxmox host."""
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
CONFIG_READER = "import sys; sys.path.insert(0, '/opt/cookidoo-manager/source'); from app.security import Vault; from app.telegram_pairs import bridge_config; import json; v=Vault('/var/lib/cookidoo-manager', 'telegram-server-bot.enc').read() or {}; print(json.dumps(bridge_config(v)))"
CART_READER = "import sys; sys.path.insert(0, '/opt/cookidoo-manager/source'); from app.telegram_cart import encrypted_snapshot; print(encrypted_snapshot('/var/lib/cookidoo-manager', sys.argv[1], sys.argv[2] == 'compressed', int(sys.argv[3])))"
WEEK_READER = "import sys,json,urllib.parse,urllib.request; q=urllib.parse.urlencode({'nonce':sys.argv[1],'day':sys.argv[2],'compressed':sys.argv[3],'client_id':sys.argv[4]}); r=urllib.request.urlopen('http://127.0.0.1:8000/api/telegram-week?'+q,timeout=45); print(json.load(r)['data'])"
PAIR_CONFIRM = "import sys,urllib.request; data=sys.stdin.buffer.read(); req=urllib.request.Request('http://127.0.0.1:8000/api/telegram-android-confirm',data=data,headers={'Content-Type':'application/json','Origin':'http://127.0.0.1:8000'}); urllib.request.urlopen(req,timeout=10).read()"
API_REQUEST = "import sys,urllib.request; data=sys.stdin.buffer.read(); req=urllib.request.Request('http://127.0.0.1:8000/api/telegram-api',data=data,headers={'Content-Type':'application/json','Origin':'http://127.0.0.1:8000'}); sys.stdout.buffer.write(urllib.request.urlopen(req,timeout=90).read())"


def config():
    result = subprocess.run(['pct', 'exec', '103', '--', '/opt/cookidoo-manager/.venv/bin/python', '-c', CONFIG_READER],
                            capture_output=True, timeout=15, check=True)
    value = json.loads(result.stdout)
    if (not isinstance(value, dict) or not isinstance(value.get('token'), str)
            or not isinstance(value.get('clients'), dict)):
        return None
    return value


def same_pair(before, after, client_id):
    key = str(client_id)
    return bool(after and before['token'] == after['token'] and key in before['clients']
                and before['clients'][key] == after['clients'].get(key))


def call(token, method, payload):
    body = urllib.parse.urlencode(payload).encode()
    request = urllib.request.Request('https://api.telegram.org/bot' + token + '/' + method, data=body)
    with urllib.request.urlopen(request, timeout=35) as response:
        result = json.load(response)
    if not result.get('ok'):
        raise ValueError('Telegram request failed')
    return result['result']


def send_api_response(token, client_id, nonce, encoded):
    if len(encoded) <= 3000:
        call(token, 'sendMessage', {'chat_id': client_id, 'text': f'rezeptgarten-api-part {nonce} 1/1 {encoded}',
                                   'disable_notification': 'true'})
        return
    boundary = 'rezeptgarten-' + os.urandom(16).hex()
    fields = (
        f'--{boundary}\r\nContent-Disposition: form-data; name="chat_id"\r\n\r\n{client_id}\r\n'
        f'--{boundary}\r\nContent-Disposition: form-data; name="disable_notification"\r\n\r\ntrue\r\n'
        f'--{boundary}\r\nContent-Disposition: form-data; name="caption"\r\n\r\nrezeptgarten-api-document {nonce}\r\n'
        f'--{boundary}\r\nContent-Disposition: form-data; name="document"; filename="rezeptgarten.dat"\r\n'
        f'Content-Type: application/octet-stream\r\n\r\n{encoded}\r\n--{boundary}--\r\n'
    )
    request = urllib.request.Request('https://api.telegram.org/bot' + token + '/sendDocument',
                                     data=fields.encode('ascii'), headers={
                                         'Content-Type': 'multipart/form-data; boundary=' + boundary,
                                     })
    with urllib.request.urlopen(request, timeout=35) as response:
        result = json.load(response)
    if not result.get('ok'):
        raise ValueError('Telegram request failed')


class ApiRequests:
    def __init__(self):
        self.pending = {}

    def accept(self, update, client_id, identity, now):
        message = update.get('message') or {}
        sender = message.get('from') or {}
        chat = message.get('chat') or {}
        match = re.fullmatch(r'rezeptgarten-api ([a-f0-9]{32}) ([0-9]{1,2})/([0-9]{1,2}) ([A-Za-z0-9+/=]{1,3000})',
                             message.get('text') or '')
        if (not match or sender.get('id') != client_id or sender.get('is_bot') is not False
                or chat.get('type') != 'private' or chat.get('id') != client_id
                or type(message.get('date')) is not int or abs(now - message['date']) > 120):
            return None
        nonce, index, total, chunk = match.groups()
        index, total = int(index), int(total)
        if not 1 <= index <= total <= 30:
            return None
        self.pending = {key: value for key, value in self.pending.items() if now - value[0] <= 120}
        key = identity, client_id, nonce
        if key not in self.pending and len(self.pending) >= 32:
            return None
        _, expected, pieces = self.pending.setdefault(key, (now, total, {}))
        if total != expected or (index in pieces and pieces[index] != chunk):
            self.pending.pop(key)
            return None
        pieces[index] = chunk
        if len(pieces) == total:
            self.pending.pop(key)
            return nonce, ''.join(pieces[i] for i in range(1, total + 1))
        return None


def api_response(client_id, nonce, encoded):
    request = json.dumps({'client_id': client_id, 'nonce': nonce, 'data': encoded}).encode()
    result = subprocess.run(['pct', 'exec', '103', '--', '/opt/cookidoo-manager/.venv/bin/python', '-c', API_REQUEST],
                            input=request, capture_output=True, timeout=95, check=True)
    response = json.loads(result.stdout)['data']
    if not re.fullmatch(r'[A-Za-z0-9+/=]{1,1333372}', response):
        raise ValueError('invalid encrypted response')
    return response


def reply_for(update, client_id, now):
    message = update.get('message') or {}
    sender = message.get('from') or {}
    chat = message.get('chat') or {}
    text = message.get('text') or ''
    match = re.fullmatch(r'rezeptgarten-(ping|cart|cartz|week|weekz) ([a-f0-9]{32})(?: (\d{4}-\d{2}-\d{2}))?', text)
    if (not match or sender.get('id') != client_id or sender.get('is_bot') is not False
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


def pairing_request(update, now):
    message = update.get('message') or {}
    sender = message.get('from') or {}
    chat = message.get('chat') or {}
    match = re.fullmatch(r'rezeptgarten-pair ([a-f0-9]{64})', message.get('text') or '')
    client_id = sender.get('id')
    if (not match or type(client_id) is not int or sender.get('is_bot') is not False
            or chat.get('type') != 'private' or chat.get('id') != client_id
            or type(message.get('date')) is not int or abs(now - message['date']) > 120):
        return None
    return client_id, match.group(1)


def confirm_pair(client_id, challenge, token_hash):
    payload = json.dumps({'client_id': client_id, 'challenge': challenge, 'token_hash': token_hash}).encode()
    subprocess.run(['pct', 'exec', '103', '--', '/opt/cookidoo-manager/.venv/bin/python', '-c', PAIR_CONFIRM],
                   input=payload, capture_output=True, timeout=15, check=True)


def cart_messages(nonce, client_id, compress=False):
    result = subprocess.run(['pct', 'exec', '103', '--', '/opt/cookidoo-manager/.venv/bin/python', '-c', CART_READER, nonce, 'compressed' if compress else 'plain', str(client_id)],
                            capture_output=True, timeout=20, check=True)
    encoded = result.stdout.decode('ascii').strip()
    if not re.fullmatch(r'[A-Za-z0-9+/=]{1,54000}', encoded):
        raise ValueError('invalid encrypted response')
    pieces = [encoded[i:i + 3000] for i in range(0, len(encoded), 3000)]
    return [f'rezeptgarten-cart-part {nonce} {i + 1}/{len(pieces)} {piece}' for i, piece in enumerate(pieces)]


def week_messages(nonce, day, client_id, compress=False):
    result = subprocess.run(['pct', 'exec', '103', '--', '/opt/cookidoo-manager/.venv/bin/python', '-c', WEEK_READER, nonce, day, 'true' if compress else 'false', str(client_id)],
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
    api_requests = ApiRequests()
    while True:
        try:
            value = config()
            if not value:
                time.sleep(10)
                continue
            token = value['token']
            identity = hashlib.sha256(token.encode()).hexdigest()
            if identity != last_token:
                offset, last_token = 0, identity
            updates = call(token, 'getUpdates', {'offset': offset, 'timeout': 20, 'allowed_updates': '["message"]'})
            for update in updates:
                update_id = update.get('update_id')
                if not isinstance(update_id, int):
                    continue
                sender = (update.get('message') or {}).get('from') or {}
                client_id = sender.get('id')
                pairing = pairing_request(update, int(time.time()))
                if pairing:
                    try:
                        confirm_pair(*pairing, identity)
                        updated = config()
                        if updated and updated['token'] == token and updated['clients'].get(str(pairing[0]), {}).get('is_bot') is False:
                            call(token, 'sendMessage', {'chat_id': pairing[0], 'text': 'rezeptgarten-paired ' + pairing[1]})
                    except (OSError, ValueError, subprocess.SubprocessError, urllib.error.URLError):
                        pass
                reply = (reply_for(update, client_id, int(time.time()))
                         if type(client_id) is int and str(client_id) in value['clients'] else None)
                if type(client_id) is int and str(client_id) in value['clients']:
                    pair_identity = value['clients'][str(client_id)]['identity']
                    incoming = api_requests.accept(update, client_id, (identity, pair_identity), int(time.time()))
                    if incoming and same_pair(value, config(), client_id):
                        nonce, encoded = incoming
                        try:
                            response = api_response(client_id, nonce, encoded)
                        except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError):
                            response = None
                        time.sleep(max(0, 1.1 - (time.monotonic() - last_reply)))
                        if same_pair(value, config(), client_id):
                            if response:
                                send_api_response(token, client_id, nonce, response)
                            else:
                                call(token, 'sendMessage', {'chat_id': client_id, 'text': 'rezeptgarten-api-error ' + nonce,
                                                           'disable_notification': 'true'})
                            last_reply = time.monotonic()
                if reply:
                    time.sleep(max(0, 1 - (time.monotonic() - last_reply)))
                    # Recheck pairing after the long poll before sending anything.
                    if same_pair(value, config(), client_id):
                        if reply.startswith(('rezeptgarten-cart ', 'rezeptgarten-cartz ')):
                            nonce = reply.split(' ')[1]
                            try:
                                messages = cart_messages(nonce, client_id, compress=reply.startswith('rezeptgarten-cartz '))
                            except (OSError, ValueError, subprocess.SubprocessError):
                                messages = ['rezeptgarten-cart-error ' + nonce]
                        elif reply.startswith(('rezeptgarten-week ', 'rezeptgarten-weekz ')):
                            _, nonce, day = reply.split(' ')
                            try:
                                messages = week_messages(nonce, day, client_id, compress=reply.startswith('rezeptgarten-weekz '))
                            except (OSError, ValueError, subprocess.SubprocessError):
                                messages = ['rezeptgarten-week-error ' + nonce]
                        else:
                            messages = [reply]
                        for index, message in enumerate(messages):
                            if index:
                                time.sleep(1.1)
                            if not same_pair(value, config(), client_id):
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
