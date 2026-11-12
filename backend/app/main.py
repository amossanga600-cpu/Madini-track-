"""Madini Track API. Secrets hutolewa kwa environment; hakuna secret ndani ya app."""
import hashlib
import hmac
import json
import logging
import os
import time
import uuid
from contextlib import asynccontextmanager
from urllib.parse import parse_qs, urlparse

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field, field_validator

from .core import SyncEngine, User, has_permission, validate_jwt_secret
from .db import PostgresRepo

JWT_SECRET = validate_jwt_secret(os.environ.get('JWT_SECRET', ''))
DATABASE_URL = os.environ.get('DATABASE_URL', '')
if not DATABASE_URL:
    raise RuntimeError('DATABASE_URL inahitajika kuanzisha API.')
APP_ENV = os.environ.get('APP_ENV', 'development').strip().lower()
API_PUBLIC_URL = os.environ.get('API_PUBLIC_URL', '').strip()
if APP_ENV in ('production', 'staging'):
    if not API_PUBLIC_URL.startswith('https://'):
        raise RuntimeError('API_PUBLIC_URL ya uzalishaji lazima itumie HTTPS.')
    query = parse_qs(urlparse(DATABASE_URL).query)
    if query.get('sslmode', [''])[0] not in ('require', 'verify-ca', 'verify-full'):
        raise RuntimeError('DATABASE_URL ya uzalishaji lazima iwe na sslmode=require au salama zaidi.')
TOKEN_TTL = int(os.environ.get('TOKEN_TTL_SECONDS', 12 * 3600))
if TOKEN_TTL <= 0:
    raise RuntimeError('TOKEN_TTL_SECONDS lazima iwe zaidi ya sifuri.')
LOGIN_MAX_ATTEMPTS = int(os.environ.get('LOGIN_MAX_ATTEMPTS', '5'))
LOGIN_WINDOW_SECONDS = int(os.environ.get('LOGIN_WINDOW_SECONDS', '300'))
AUTO_MIGRATE = os.environ.get(
    'AUTO_MIGRATE', 'false' if APP_ENV == 'production' else 'true'
).lower() in ('1', 'true', 'yes')
if LOGIN_MAX_ATTEMPTS < 1 or LOGIN_WINDOW_SECONDS < 1:
    raise RuntimeError('Mipangilio ya login rate limit si sahihi.')

POOL_MIN_SIZE = int(os.environ.get('DB_POOL_MIN_SIZE', '1'))
POOL_MAX_SIZE = int(os.environ.get('DB_POOL_MAX_SIZE', '10'))
if POOL_MIN_SIZE < 1 or POOL_MAX_SIZE < POOL_MIN_SIZE:
    raise RuntimeError('Mipangilio ya pool ya PostgreSQL si sahihi.')

logger = logging.getLogger('madini.api')


class JsonLogFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(record.created)),
            'level': record.levelname.lower(),
            'logger': record.name,
            'message': record.getMessage(),
        }
        if hasattr(record, 'fields'):
            payload.update(record.fields)
        if record.exc_info:
            payload['exception'] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False, default=str)


handler = logging.StreamHandler()
handler.setFormatter(JsonLogFormatter())
logging.basicConfig(level=os.environ.get('LOG_LEVEL', 'INFO').upper(), handlers=[handler])
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO').upper())
logger.handlers.clear()
logger.addHandler(handler)
logger.propagate = False
repo = PostgresRepo(
    DATABASE_URL, min_size=POOL_MIN_SIZE, max_size=POOL_MAX_SIZE
)
engine = SyncEngine(repo)
hasher = PasswordHasher()
bearer = HTTPBearer(auto_error=False)


@asynccontextmanager
async def lifespan(_app):
    try:
        repo.open()
        if AUTO_MIGRATE:
            versions = repo.migrate()
            logger.info('Database migrations ready', extra={'fields': {'applied': versions}})
        else:
            repo.ping()
            logger.info('Database connection ready; startup migrations disabled')
        yield
    finally:
        repo.close()


app = FastAPI(title='Madini Track API', version='2.2.0', lifespan=lifespan)


class LoginIn(BaseModel):
    username: str = Field(min_length=2, max_length=120)
    password: str = Field(min_length=10, max_length=256)
    device_id: str = Field(min_length=8, max_length=128)
    device_name: str = Field(default='', max_length=120)

    @field_validator('device_id')
    @classmethod
    def device_id_must_be_uuid(cls, value):
        return str(uuid.UUID(value))


class SyncEvent(BaseModel):
    idempotency_key: str = Field(min_length=1, max_length=256)
    entity: str = Field(min_length=1, max_length=80)
    record_uuid: uuid.UUID
    company_uuid: uuid.UUID
    version: int = Field(strict=True, ge=1)
    data: dict

    @field_validator('data')
    @classmethod
    def record_data_must_match_uuid(cls, value, info):
        record_uuid = info.data.get('record_uuid')
        if record_uuid is not None and value.get('uuid') != str(record_uuid):
            raise ValueError('data.uuid lazima ilingane na record_uuid')
        return value


class PushIn(BaseModel):
    device_id: str = Field(min_length=8, max_length=128)
    events: list[SyncEvent] = Field(max_length=200)

    @field_validator('device_id')
    @classmethod
    def device_id_must_be_uuid(cls, value):
        return str(uuid.UUID(value))


class ConflictDecision(BaseModel):
    decision: str = Field(pattern='^(accept_conflict|keep_server)$')


class UserCreate(BaseModel):
    username: str = Field(min_length=2, max_length=120)
    password: str = Field(min_length=12, max_length=256)
    role: str
    company_uuid: str
    mine_uuids: list[str] | None = Field(default=None, max_length=500)

    @field_validator('company_uuid')
    @classmethod
    def company_id_must_be_uuid(cls, value):
        return str(uuid.UUID(value))

    @field_validator('mine_uuids')
    @classmethod
    def mine_ids_must_be_uuids(cls, value):
        if value is not None:
            for mine_uuid in value:
                uuid.UUID(mine_uuid)
            if len(set(value)) != len(value):
                raise ValueError('mine_uuids ina UUID inayojirudia')
        return value


def _issue_token(user_id, device_id, jti=None, exp=None):
    now = int(time.time())
    expires = exp or now + TOKEN_TTL
    payload = {
        'sub': user_id,
        'device_id': device_id,
        'jti': jti or str(uuid.uuid4()),
        'iat': now,
        'nbf': now,
        'exp': expires,
        'iss': 'madini-track-api',
        'aud': 'madini-track-mobile',
        'token_use': 'access',
    }
    return jwt.encode(payload, JWT_SECRET, algorithm='HS256'), payload


def current_user(cred: HTTPAuthorizationCredentials = Depends(bearer)) -> User:
    if cred is None:
        raise HTTPException(401, 'token inahitajika')
    try:
        p = jwt.decode(
            cred.credentials,
            JWT_SECRET,
            algorithms=['HS256'],
            issuer='madini-track-api',
            audience='madini-track-mobile',
            options={'require': ['sub', 'device_id', 'jti', 'iat', 'nbf', 'exp', 'iss', 'aud']},
            leeway=30,
        )
        if p.get('token_use') != 'access':
            raise jwt.InvalidTokenError('wrong token use')
        user_id = str(uuid.UUID(p['sub']))
        device_id = str(uuid.UUID(p['device_id']))
        jti = str(uuid.UUID(p['jti']))
    except (jwt.PyJWTError, KeyError, TypeError):
        raise HTTPException(401, 'token batili')
    u = repo.get_user_by_id(user_id)
    if not u or not u['active'] or not repo.device_belongs_to_user(u['id'], device_id):
        raise HTTPException(401, 'mtumiaji au kifaa hakiruhusiwi')
    if repo.token_revoked(jti):
        raise HTTPException(401, 'token imefutwa')
    return User(u['id'], u['memberships'], device_id, u['mine_memberships'])


def company_admin(company_uuid: str, user: User):
    role = user.memberships.get(company_uuid)
    if role not in ('company_owner', 'company_admin'):
        raise HTTPException(403, 'ruhusa ya msimamizi wa kampuni inahitajika')


@app.get('/health')
def health():
    # Health ya app pekee; /health/ready hukagua database.
    return {'status': 'ok', 'service': 'madini-track-api'}


@app.middleware("http")
async def request_logging(request: Request, call_next):
    request_id = request.headers.get('x-request-id', '')
    if not request_id or len(request_id) > 80 or not request_id.isascii():
        request_id = str(uuid.uuid4())
    started = time.monotonic()
    try:
        response = await call_next(request)
    except Exception:
        logger.exception(
            'Unhandled request failure',
            extra={'fields': {
                'request_id': request_id,
                'method': request.method,
                'path': request.url.path,
            }},
        )
        raise
    response.headers['X-Request-ID'] = request_id
    logger.info(
        'Request completed',
        extra={'fields': {
            'request_id': request_id,
            'method': request.method,
            'path': request.url.path,
            'status_code': response.status_code,
            'duration_ms': round((time.monotonic() - started) * 1000, 2),
        }},
    )
    return response


@app.get('/health/ready')
def ready():
    try:
        repo.ping()
        return {'status': 'ready', 'database': 'ok'}
    except Exception as error:
        logger.error('Database readiness check failed', extra={'fields': {
            'error_type': type(error).__name__,
        }})
        raise HTTPException(503, 'database haipatikani')


@app.post('/v1/auth/login')
def login(body: LoginIn, request: Request):
    remote = request.client.host if request.client else 'unknown'
    bucket = hmac.new(
        JWT_SECRET.encode('utf-8'),
        f'{remote}\0{body.username.casefold()}'.encode('utf-8'),
        hashlib.sha256,
    ).hexdigest()
    if not repo.consume_login_attempt(
        bucket, LOGIN_MAX_ATTEMPTS, LOGIN_WINDOW_SECONDS
    ):
        raise HTTPException(429, 'majaribio mengi; subiri dakika chache')
    username = body.username.strip()
    u = repo.get_user_by_name(username)
    if not u or not u['active']:
        raise HTTPException(401, 'jina au nywila si sahihi')
    try:
        hasher.verify(u['password_hash'], body.password)
    except (VerifyMismatchError, InvalidHashError, VerificationError):
        raise HTTPException(401, 'jina au nywila si sahihi')
    if hasher.check_needs_rehash(u['password_hash']):
        repo.update_password_hash(u['id'], hasher.hash(body.password))
    repo.register_device(u['id'], body.device_id, body.device_name)
    repo.clear_login_attempts(bucket)
    token, _ = _issue_token(u['id'], body.device_id)
    return {'access_token': token, 'token_type': 'bearer', 'expires_in': TOKEN_TTL}


@app.get('/v1/auth/me')
def me(user: User = Depends(current_user)):
    return {'user_id': user.id, 'device_id': user.device_id, 'memberships': user.memberships}


@app.post('/v1/auth/logout')
def logout(user: User = Depends(current_user),
           cred: HTTPAuthorizationCredentials = Depends(bearer)):
    payload = jwt.decode(
        cred.credentials,
        JWT_SECRET,
        algorithms=['HS256'],
        issuer='madini-track-api',
        audience='madini-track-mobile',
    )
    repo.revoke_token(payload['jti'], user.id, payload['exp'])
    return {'status': 'revoked'}


@app.post('/v1/auth/refresh')
def refresh(user: User = Depends(current_user),
            cred: HTTPAuthorizationCredentials = Depends(bearer)):
    old = jwt.decode(
        cred.credentials,
        JWT_SECRET,
        algorithms=['HS256'],
        issuer='madini-track-api',
        audience='madini-track-mobile',
    )
    token, _ = _issue_token(user.id, user.device_id)
    if not repo.rotate_token(old['jti'], user.id, old['exp']):
        raise HTTPException(401, 'token imekwisha kutumika; ingia tena')
    return {'access_token': token, 'token_type': 'bearer', 'expires_in': TOKEN_TTL}


@app.post('/v1/sync/push')
def push(body: PushIn, user: User = Depends(current_user)):
    if body.device_id != user.device_id:
        raise HTTPException(403, 'device_id haiendani na kifaa kilichoingia')
    try:
        events = [event.model_dump(mode='json') for event in body.events]
        return {'results': engine.push(user, body.device_id, events)}
    except ValueError as e:
        raise HTTPException(422, str(e))


@app.get('/v1/sync/pull')
def pull(company_uuid: uuid.UUID, cursor: int = Query(default=0, ge=0),
         limit: int = Query(default=200, ge=1, le=500),
         user: User = Depends(current_user)):
    company_id = str(company_uuid)
    try:
        return engine.pull(user, company_id, cursor, limit)
    except PermissionError as e:
        raise HTTPException(403, str(e))


@app.get('/v1/sync/conflicts')
def conflicts(company_uuid: uuid.UUID, limit: int = Query(default=100, ge=1, le=500),
              user: User = Depends(current_user)):
    company_id = str(company_uuid)
    role = user.memberships.get(company_id)
    if role not in ('company_owner', 'company_admin', 'mine_manager', 'auditor'):
        raise HTTPException(403, 'hairuhusiwi kuona conflicts')
    mine_scope = user.mine_memberships.get(company_id)
    return {'conflicts': repo.list_conflicts(company_id, limit, mine_scope)}


@app.post('/v1/sync/conflicts/{conflict_id}/resolve')
def resolve_conflict(conflict_id: int, company_uuid: uuid.UUID, body: ConflictDecision,
                     user: User = Depends(current_user)):
    company_id = str(company_uuid)
    company_admin(company_id, user)
    if body.decision not in ('accept_conflict', 'keep_server'):
        raise HTTPException(422, 'decision lazima iwe accept_conflict au keep_server')
    if not repo.resolve_conflict(company_id, conflict_id, body.decision, user.id):
        raise HTTPException(404, 'conflict haipo au tayari imetatuliwa')
    return {'status': 'resolved', 'decision': body.decision}


@app.get('/v1/audit')
def audit(company_uuid: uuid.UUID, cursor: int = Query(default=0, ge=0),
          limit: int = Query(default=200, ge=1, le=500),
          mine_id: str | None = None, user: User = Depends(current_user)):
    company_id = str(company_uuid)
    role = user.memberships.get(company_id)
    if role is None or not has_permission(role, 'audit:read'):
        raise HTTPException(403, 'hairuhusiwi kuona audit ya kampuni hii')
    if mine_id:
        mine_uuid = repo.resolve_mine(company_id, mine_id)
        if mine_uuid is None:
            raise HTTPException(404, 'mgodi haupo ndani ya kampuni hii')
        assigned = user.mine_memberships.get(company_id)
        if assigned is not None and mine_uuid not in assigned:
            raise HTTPException(403, 'hairuhusiwi kuona audit ya mgodi huu')
    return repo.audit_entries(
        company_id, cursor, limit, mine_id,
        user.mine_memberships.get(company_id) if mine_id is None else None,
    )


@app.get('/v1/batches/{identifier}/trace')
def batch_trace(identifier: str, company_uuid: uuid.UUID,
                user: User = Depends(current_user)):
    company_id = str(company_uuid)
    role = user.memberships.get(company_id)
    if role is None or not has_permission(role, 'sync:read'):
        raise HTTPException(403, 'hairuhusiwi kuona kampuni hii')
    assigned = user.mine_memberships.get(company_id)
    if assigned is not None:
        trace = repo.batch_genealogy(
            company_id, identifier, mine_uuids=assigned
        )
        visible_mines = {
            record['data'].get('mine_id')
            for record in trace['batches']
            if record['data'].get('mine_id') is not None
        }
        trace_mines = {
            name for name in (
                repo.resolve_mine(company_id, value) for value in visible_mines
            ) if name in assigned
        }
        if not trace_mines:
            raise HTTPException(404, 'Batch haipo kwenye migodi uliyopewa')
        return trace
    return repo.batch_genealogy(company_id, identifier)


@app.post('/v1/admin/users')
def create_user(body: UserCreate, user: User = Depends(current_user)):
    company_admin(body.company_uuid, user)
    allowed = {'company_admin', 'mine_manager', 'production_supervisor',
               'processing_operator', 'storekeeper', 'accountant', 'auditor', 'read_only'}
    if body.role not in allowed:
        raise HTTPException(422, 'role hairuhusiwi')
    if body.mine_uuids is not None and body.role in ('company_admin',):
        raise HTTPException(422, 'company_admin hawezi kufungiwa kwenye mgodi mmoja')
    try:
        uid = repo.create_company_user(
            body.username.strip(),
            hasher.hash(body.password),
            body.company_uuid,
            body.role,
            user.id,
            body.mine_uuids,
        )
    except ValueError as error:
        raise HTTPException(422, str(error))
    except Exception as error:
        from psycopg.errors import ForeignKeyViolation, UniqueViolation
        if not isinstance(error, (ForeignKeyViolation, UniqueViolation)):
            raise
        raise HTTPException(409, 'username tayari ipo au taarifa si sahihi')
    return {
        'user_id': uid,
        'username': body.username.strip(),
        'role': body.role,
        'mine_scope': 'company' if body.mine_uuids is None else body.mine_uuids,
    }
