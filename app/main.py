import asyncio
import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .security import Vault, new_session, password_hash, valid_session, verify_password
from .storage import Database
from .sync import REGIONS, SyncService, friendly_error

STATIC = Path(__file__).parent / 'static'
COOKIE = 'rezeptgarten_session'


class Login(BaseModel):
    password: str = Field(min_length=1, max_length=256)


class Setup(Login):
    code: str = Field(min_length=10, max_length=128)


class Connection(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=512)
    region: str = 'de'


class Settings(BaseModel):
    sync_hours: int


def create_app(directory=None, secure_cookies=None):
    os.umask(0o077)
    database = Database(directory or os.environ.get('REZEPTGARTEN_DATA', './data'))
    vault = Vault(database.directory)
    service = SyncService(database, vault)
    secure = secure_cookies if secure_cookies is not None else os.environ.get('REZEPTGARTEN_SECURE_COOKIE', '1') != '0'
    setup_path = database.directory / 'setup-code'
    if not database.get('admin_password') and not setup_path.exists():
        setup_path.write_text(secrets.token_urlsafe(24))
        setup_path.chmod(0o600)
    attempts = defaultdict(deque)

    @asynccontextmanager
    async def lifespan(app):
        await service.start()
        yield
        await service.close()

    app = FastAPI(title='Rezeptgarten', docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)
    app.state.database = database
    app.state.sync = service

    @app.middleware('http')
    async def security_headers(request, call_next):
        if request.url.path.startswith('/api/') and request.method not in ('GET', 'HEAD', 'OPTIONS'):
            origin = request.headers.get('origin')
            expected = f'{request.url.scheme}://{request.headers.get("host", "")}'
            if origin != expected:
                return JSONResponse({'detail': 'Die Anfrage muss aus dieser App stammen.'}, status_code=403)
            content_length = request.headers.get('content-length', '0')
            try:
                if int(content_length) > 16384:
                    return JSONResponse({'detail': 'Die Anfrage ist zu groß.'}, status_code=413)
            except ValueError:
                return JSONResponse({'detail': 'Ungültige Anfrage.'}, status_code=400)
        response = await call_next(request)
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Referrer-Policy'] = 'no-referrer'
        response.headers['X-Frame-Options'] = 'DENY'
        response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'; worker-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
        if request.url.path.startswith('/api/'):
            response.headers['Cache-Control'] = 'no-store'
        return response

    def authenticated(request: Request):
        if not valid_session(database, request.cookies.get(COOKIE)):
            raise HTTPException(401, 'Bitte melde dich in Rezeptgarten an.')

    def throttle(request):
        key = request.client.host if request.client else 'unknown'
        queue = attempts[key]
        while queue and queue[0] < time.monotonic() - 60:
            queue.popleft()
        if len(queue) >= 8:
            raise HTTPException(429, 'Zu viele Versuche. Bitte warte eine Minute.')
        queue.append(time.monotonic())

    def session_response():
        response = JSONResponse({'ok': True})
        response.set_cookie(COOKIE, new_session(database), secure=secure, httponly=True, samesite='strict', max_age=30 * 86400, path='/')
        return response

    @app.get('/api/health')
    def health():
        return {'ok': True, 'version': '0.1.0'}

    @app.get('/api/auth/status')
    def auth_status(request: Request):
        return {'configured': bool(database.get('admin_password')), 'authenticated': valid_session(database, request.cookies.get(COOKIE))}

    @app.post('/api/auth/setup')
    def setup(payload: Setup, request: Request):
        throttle(request)
        if len(payload.password) < 8:
            raise HTTPException(400, 'Bitte verwende mindestens 8 Zeichen für dein App-Passwort.')
        if not setup_path.exists() or not hmac.compare_digest(payload.code, setup_path.read_text().strip()):
            raise HTTPException(403, 'Der Einrichtungscode ist ungültig oder bereits verwendet.')
        # The setup can only be claimed once, including concurrent requests.
        with database.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            if db.execute("SELECT 1 FROM settings WHERE key='admin_password'").fetchone():
                raise HTTPException(409, 'Die App ist bereits eingerichtet.')
            database.write_setting(db, 'admin_password', password_hash(payload.password))
        setup_path.unlink(missing_ok=True)
        return session_response()

    @app.post('/api/auth/login')
    def login(payload: Login, request: Request):
        throttle(request)
        if not verify_password(payload.password, database.get('admin_password')):
            raise HTTPException(401, 'Das App-Passwort stimmt nicht.')
        return session_response()

    @app.post('/api/auth/logout', dependencies=[Depends(authenticated)])
    def logout(request: Request):
        token = request.cookies.get(COOKIE, '')
        with database.connect() as db:
            db.execute('DELETE FROM sessions WHERE token_hash=?', (hashlib.sha256(token.encode()).hexdigest(),))
        response = JSONResponse({'ok': True})
        response.delete_cookie(COOKIE, path='/', secure=secure, httponly=True, samesite='strict')
        return response

    @app.get('/api/status', dependencies=[Depends(authenticated)])
    def status():
        return {'stats': database.stats(), 'connected': service.client is not None, 'account': database.get('account'), 'sync': service.state, 'last_result': database.get('last_result'), 'sync_hours': database.get('sync_hours', 6)}

    @app.get('/api/collections', dependencies=[Depends(authenticated)])
    def collections():
        return {'items': database.collections()}

    @app.get('/api/recipes', dependencies=[Depends(authenticated)])
    def recipes(collection: str | None = None, q: str = Query('', max_length=200), sort: str = 'name', offset: int = Query(0, ge=0), limit: int = Query(48, ge=1, le=100)):
        if sort not in ('name', 'time'):
            raise HTTPException(400, 'Ungültige Sortierung.')
        return database.recipes(collection, q.strip(), sort, offset, limit)

    @app.get('/api/recipes/{recipe_id}', dependencies=[Depends(authenticated)])
    def recipe(recipe_id: str):
        result = database.recipe(recipe_id)
        if result is None:
            raise HTTPException(404, 'Dieses Rezept wurde nicht gefunden.')
        return result

    @app.get('/api/images/{filename}', dependencies=[Depends(authenticated)])
    def image(filename: str):
        if not re.fullmatch(r'[a-f0-9]{40}\.webp', filename):
            raise HTTPException(404)
        path = service.images / filename
        if not path.is_file():
            raise HTTPException(404)
        return FileResponse(path, media_type='image/webp', headers={'Cache-Control': 'private, max-age=86400'})

    @app.post('/api/connect', dependencies=[Depends(authenticated)])
    async def connect(payload: Connection):
        if payload.region not in REGIONS or '@' not in payload.email:
            raise HTTPException(400, 'Bitte prüfe E-Mail-Adresse und Land deines Cookidoo-Kontos.')
        try:
            await service.connect(payload.email.strip(), payload.password, payload.region)
            service.begin()
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        except Exception as error:
            logging.getLogger(__name__).warning('Cookidoo login failed: %s', type(error).__name__)
            raise HTTPException(502, friendly_error(error)) from None
        return {'ok': True}

    @app.post('/api/disconnect', dependencies=[Depends(authenticated)])
    async def disconnect():
        try:
            await service.disconnect()
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        return {'ok': True}

    @app.post('/api/sync', dependencies=[Depends(authenticated)])
    async def sync():
        try:
            started = service.begin()
        except ValueError as error:
            raise HTTPException(409, str(error)) from None
        return {'started': started}

    @app.post('/api/settings', dependencies=[Depends(authenticated)])
    def settings(payload: Settings):
        if payload.sync_hours not in (0, 1, 6, 24):
            raise HTTPException(400, 'Ungültiges Synchronisierungsintervall.')
        database.set('sync_hours', payload.sync_hours)
        return {'ok': True}

    @app.get('/api/export', dependencies=[Depends(authenticated)])
    def export():
        return Response(json.dumps(database.export(), ensure_ascii=False, indent=2), media_type='application/json', headers={'Content-Disposition': 'attachment; filename="rezeptgarten-sammlung.json"', 'Cache-Control': 'no-store'})

    @app.get('/sw.js')
    def worker():
        return FileResponse(STATIC / 'sw.js', media_type='application/javascript', headers={'Cache-Control': 'no-cache', 'Service-Worker-Allowed': '/'})

    app.mount('/static', StaticFiles(directory=STATIC), name='static')

    @app.get('/')
    def index():
        return FileResponse(STATIC / 'index.html', headers={'Cache-Control': 'no-cache'})

    return app
