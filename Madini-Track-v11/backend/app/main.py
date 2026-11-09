"""Madini Track API. Secrets hutolewa kwa environment; hakuna secret ndani ya app."""
import os
import time
import uuid

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field

from .core import RateLimiter, SyncEngine, User, has_permission, validate_jwt_secret
from .db import PostgresRepo

JWT_SECRET = validate_jwt_secret(os.environ.get('JWT_SECRET', ''))
DATABASE_URL = os.environ.get('DATABASE_URL', '')
if not DATABASE_URL:
    raise RuntimeError('DATABASE_URL inahitajika kuanzisha API.')
TOKEN_TTL = int(os.environ.get('TOKEN_TTL_SECONDS', 12 * 3600))
if TOKEN_TTL <= 0:
    raise RuntimeError('TOKEN_TTL_SECONDS lazima iwe zaidi ya sifuri.')
app = FastAPI(title='Madini Track API', version='2.1.0')
repo = PostgresRepo(DATABASE_URL)
engine = SyncEngine(repo)
hasher = PasswordHasher()
limiter = RateLimiter()
bearer = HTTPBearer(auto_error=False)


class LoginIn(BaseModel):
    username: str = Field(min_length=2, max_length=120)
    password: str = Field(min_length=10, max_length=256)
    device_id: str = Field(min_length=8, max_length=128)
    device_name: str = Field(default='', max_length=120)


class PushIn(BaseModel):
    device_id: str
    events: list = Field(max_length=200)


class ConflictDecision(BaseModel):
    decision: str


class UserCreate(BaseModel):
    username: str = Field(min_length=2, max_length=120)
    password: str = Field(min_length=12, max_length=256)
    role: str
    company_uuid: str


def current_user(cred: HTTPAuthorizationCredentials = Depends(bearer)) -> User:
    if cred is None:
        raise HTTPException(401, 'token inahitajika')
    try:
        p = jwt.decode(cred.credentials, JWT_SECRET, algorithms=['HS256'])
        username, device_id, jti = p['sub'], p['device_id'], p['jti']
    except (jwt.PyJWTError, KeyError):
        raise HTTPException(401, 'token batili')
    u = repo.get_user_by_name(username)
    if not u or not u['active'] or not repo.device_belongs_to_user(u['id'], device_id):
        raise HTTPException(401, 'mtumiaji au kifaa hakiruhusiwi')
    if repo.token_revoked(jti):
        raise HTTPException(401, 'token imefutwa')
    return User(u['id'], u['memberships'], device_id)


def company_admin(company_uuid: str, user: User):
    role = user.memberships.get(company_uuid)
    if role not in ('company_owner', 'company_admin'):
        raise HTTPException(403, 'ruhusa ya msimamizi wa kampuni inahitajika')


@app.get('/health')
def health():
    # Health ya app pekee; /health/ready hukagua database.
    return {'status': 'ok', 'service': 'madini-track-api'}


@app.get('/health/ready')
def ready():
    try:
        repo.ping()
        return {'status': 'ready', 'database': 'ok'}
    except Exception:
        raise HTTPException(503, 'database haipatikani')


@app.post('/v1/auth/login')
def login(body: LoginIn, request: Request):
    key = f"{request.client.host}:{body.username}"
    if not limiter.allow(key):
        raise HTTPException(429, 'majaribio mengi; subiri dakika chache')
    u = repo.get_user_by_name(body.username)
    if not u or not u['active']:
        raise HTTPException(401, 'jina au nywila si sahihi')
    try:
        hasher.verify(u['password_hash'], body.password)
    except VerifyMismatchError:
        raise HTTPException(401, 'jina au nywila si sahihi')
    limiter.reset(key)
    repo.register_device(u['id'], body.device_id, body.device_name)
    jti = str(uuid.uuid4())
    exp = int(time.time()) + TOKEN_TTL
    token = jwt.encode({'sub': body.username, 'device_id': body.device_id,
                        'jti': jti, 'iat': int(time.time()), 'exp': exp},
                       JWT_SECRET, algorithm='HS256')
    return {'access_token': token, 'token_type': 'bearer', 'expires_in': TOKEN_TTL}


@app.get('/v1/auth/me')
def me(user: User = Depends(current_user)):
    return {'user_id': user.id, 'device_id': user.device_id, 'memberships': user.memberships}


@app.post('/v1/auth/logout')
def logout(user: User = Depends(current_user),
           cred: HTTPAuthorizationCredentials = Depends(bearer)):
    payload = jwt.decode(cred.credentials, JWT_SECRET, algorithms=['HS256'])
    repo.revoke_token(payload['jti'], user.id, payload['exp'])
    return {'status': 'revoked'}


@app.post('/v1/auth/refresh')
def refresh(user: User = Depends(current_user),
            cred: HTTPAuthorizationCredentials = Depends(bearer)):
    old = jwt.decode(cred.credentials, JWT_SECRET, algorithms=['HS256'])
    repo.revoke_token(old['jti'], user.id, old['exp'])
    jti, exp = str(uuid.uuid4()), int(time.time()) + TOKEN_TTL
    token = jwt.encode({'sub': old['sub'], 'device_id': user.device_id,
                        'jti': jti, 'iat': int(time.time()), 'exp': exp},
                       JWT_SECRET, algorithm='HS256')
    return {'access_token': token, 'token_type': 'bearer', 'expires_in': TOKEN_TTL}


@app.post('/v1/sync/push')
def push(body: PushIn, user: User = Depends(current_user)):
    if body.device_id != user.device_id:
        raise HTTPException(403, 'device_id haiendani na kifaa kilichoingia')
    try:
        return {'results': engine.push(user, body.device_id, body.events)}
    except ValueError as e:
        raise HTTPException(422, str(e))


@app.get('/v1/sync/pull')
def pull(company_uuid: str, cursor: int = 0, limit: int = 200,
         user: User = Depends(current_user)):
    try:
        return engine.pull(user, company_uuid, cursor, limit)
    except PermissionError as e:
        raise HTTPException(403, str(e))


@app.get('/v1/sync/conflicts')
def conflicts(company_uuid: str, limit: int = 100, user: User = Depends(current_user)):
    role = user.memberships.get(company_uuid)
    if role not in ('company_owner', 'company_admin', 'mine_manager', 'auditor'):
        raise HTTPException(403, 'hairuhusiwi kuona conflicts')
    return {'conflicts': repo.list_conflicts(company_uuid, min(max(limit, 1), 500))}


@app.post('/v1/sync/conflicts/{conflict_id}/resolve')
def resolve_conflict(conflict_id: int, company_uuid: str, body: ConflictDecision,
                     user: User = Depends(current_user)):
    company_admin(company_uuid, user)
    if body.decision not in ('accept_conflict', 'keep_server'):
        raise HTTPException(422, 'decision lazima iwe accept_conflict au keep_server')
    if not repo.resolve_conflict(company_uuid, conflict_id, body.decision, user.id):
        raise HTTPException(404, 'conflict haipo au tayari imetatuliwa')
    return {'status': 'resolved', 'decision': body.decision}


@app.post('/v1/admin/users')
def create_user(body: UserCreate, user: User = Depends(current_user)):
    company_admin(body.company_uuid, user)
    allowed = {'company_admin', 'mine_manager', 'production_supervisor', 'processing_operator',
               'storekeeper', 'accountant', 'auditor', 'read_only'}
    if body.role not in allowed:
        raise HTTPException(422, 'role hairuhusiwi')
    try:
        uid = repo.create_company_user(body.username, hasher.hash(body.password),
                                       body.company_uuid, body.role)
    except Exception:
        raise HTTPException(409, 'username tayari ipo au taarifa si sahihi')
    return {'user_id': uid, 'username': body.username, 'role': body.role}
