import hashlib
import hmac
import json
import os
import secrets
import time
from pathlib import Path

from cryptography.fernet import Fernet


def password_hash(password):
    salt = secrets.token_bytes(16)
    value = hashlib.scrypt(password.encode(), salt=salt, n=16384, r=8, p=1)
    return salt.hex() + ':' + value.hex()


def verify_password(password, encoded):
    try:
        salt, value = encoded.split(':')
        actual = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1)
        return hmac.compare_digest(actual.hex(), value)
    except (ValueError, TypeError):
        return False


def new_session(database):
    token = secrets.token_urlsafe(40)
    with database.connect() as db:
        db.execute('DELETE FROM sessions WHERE expires<?', (time.time(),))
        db.execute('INSERT INTO sessions(token_hash,expires) VALUES(?,?)', (hashlib.sha256(token.encode()).hexdigest(), time.time() + 30 * 86400))
    return token


def valid_session(database, token):
    if not token or len(token) > 256:
        return False
    with database.connect() as db:
        return db.execute('SELECT 1 FROM sessions WHERE token_hash=? AND expires>?', (hashlib.sha256(token.encode()).hexdigest(), time.time())).fetchone() is not None


class Vault:
    def __init__(self, directory, filename='cookidoo.enc'):
        self.directory = Path(directory)
        self.key_path = self.directory / 'vault.key'
        self.path = self.directory / filename
        if not self.key_path.exists():
            with self.key_path.open('xb') as file:
                file.write(Fernet.generate_key())
            os.chmod(self.key_path, 0o600)
        self.cipher = Fernet(self.key_path.read_bytes())

    def read(self):
        return json.loads(self.cipher.decrypt(self.path.read_bytes())) if self.path.exists() else None

    def write(self, payload):
        temporary = self.path.with_suffix('.tmp')
        with temporary.open('wb') as file:
            file.write(self.cipher.encrypt(json.dumps(payload).encode()))
        os.chmod(temporary, 0o600)
        os.replace(temporary, self.path)

    def clear(self):
        self.path.unlink(missing_ok=True)
