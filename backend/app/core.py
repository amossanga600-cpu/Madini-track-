"""Mantiki ya seva (bila utegemezi wa FastAPI/Postgres) ili ijaribiwe kwa unit tests."""
import time
import json
from dataclasses import dataclass, field

ENTITIES = {
    'companies', 'mines', 'production_records', 'ore_batches', 'batch_movements',
    'processing_records', 'workers', 'attendance', 'payroll_payments', 'finance_transactions',
    'debts', 'debt_payments', 'inventory_items', 'inventory_movements', 'sales', 'audit_log',
    'gold_inventory', 'gold_sale_allocations', 'attachments', 'tax_rates', 'safety_incidents',
}

ROLE_PERMISSIONS = {
    'company_owner': {'sync:write', 'sync:read', 'users:manage', 'audit:read'},
    'company_admin': {'sync:write', 'sync:read', 'users:manage', 'audit:read'},
    'mine_manager': {'sync:write', 'sync:read', 'audit:read'},
    'production_supervisor': {'sync:write', 'sync:read'},
    'processing_operator': {'sync:write', 'sync:read'},
    'storekeeper': {'sync:write', 'sync:read'},
    'accountant': {'sync:write', 'sync:read', 'audit:read'},
    'auditor': {'sync:read', 'audit:read'},
    'read_only': {'sync:read'},
}

# Ruhusa za biashara: ruhusa ya jumla ya sync pekee haitoshi kuandika kila aina ya rekodi.
ROLE_ENTITIES = {
    'company_owner': set(ENTITIES),
    'company_admin': set(ENTITIES),
    'mine_manager': set(ENTITIES),
    'production_supervisor': {'mines', 'production_records', 'ore_batches', 'batch_movements'},
    'processing_operator': {'ore_batches', 'batch_movements', 'processing_records', 'gold_inventory'},
    'storekeeper': {'inventory_items', 'inventory_movements', 'attachments'},
    'accountant': {'finance_transactions', 'debts', 'debt_payments', 'sales',
                   'gold_inventory', 'gold_sale_allocations', 'payroll_payments', 'tax_rates'},
    'auditor': set(),
    'read_only': set(),
}

def validate_jwt_secret(secret: str) -> str:
    if len(secret.encode('utf-8')) < 32:
        raise RuntimeError('JWT_SECRET lazima iwe na angalau bytes 32.')
    return secret


def can_write_entity(role: str, entity: str) -> bool:
    return has_permission(role, 'sync:write') and entity in ROLE_ENTITIES.get(role, set())



def has_permission(role: str, perm: str) -> bool:
    return perm in ROLE_PERMISSIONS.get(role, set())


@dataclass
class User:
    id: str
    memberships: dict  # company_uuid -> role
    device_id: str = ''
    mine_memberships: dict = field(default_factory=dict)  # company_uuid -> mine UUIDs


class RateLimiter:
    """Rate limiter ya kumbukumbu kwa unit tests pekee."""

    def __init__(self, max_attempts=5, window_seconds=300, clock=time.monotonic):
        self.max, self.window, self.clock = max_attempts, window_seconds, clock
        self.hits = {}

    def allow(self, key: str) -> bool:
        now = self.clock()
        q = [t for t in self.hits.get(key, []) if now - t < self.window]
        if len(q) >= self.max:
            self.hits[key] = q
            return False
        q.append(now)
        self.hits[key] = q
        return True

    def reset(self, key: str):
        self.hits.pop(key, None)


class MemoryRepo:
    """Repo ya majaribio. PostgresRepo (app/db.py) ina mkataba huo huo."""

    def __init__(self, company_names=None):
        self.events, self.records, self.conflicts = {}, {}, []
        self.company_names = company_names or {}
        self._seq = 0

    def company_name(self, company_uuid):
        return self.company_names.get(company_uuid)

    def pull_records(self, company_uuid, cursor, limit, mine_uuids=None):
        rows = sorted(
            ((v['seq'], k, v) for k, v in self.records.items() if k[0] == company_uuid and v['seq'] > cursor),
            key=lambda x: x[0])
        if mine_uuids is not None:
            rows = [
                row for row in rows
                if (
                    row[1][1] == 'companies'
                    or (
                        row[1][1] == 'mines'
                        and row[1][2] in mine_uuids
                    )
                    or row[2]['data'].get('mine_id') in mine_uuids
                )
            ]
        more = len(rows) > limit
        rows = rows[:limit]
        out = [{'cursor': s, 'entity': k[1], 'record_uuid': k[2], 'version': v['version'],
                'data': v['data'], 'device_id': v['device_id']} for s, k, v in rows]
        return out, (rows[-1][0] if rows else cursor), more

    def get_event(self, device_id, key):
        return self.events.get((device_id, key))

    def get_record(self, company_uuid, entity, record_uuid):
        return self.records.get((company_uuid, entity, record_uuid))

    def apply(self, company_uuid, ev, device_id, outcome, user_id):
        """Atomic: rekodi + event ya idempotency kwa pamoja."""
        if outcome == 'applied':
            self._seq += 1  # seq inabadilika kwa kila uandishi, ili pull ipate masahihisho pia
            self.records[(company_uuid, ev['entity'], ev['record_uuid'])] = {
                'version': ev['version'], 'data': ev['data'], 'device_id': device_id, 'seq': self._seq}
        elif outcome == 'conflict':
            self.conflicts.append({'company': company_uuid, 'event': ev, 'device_id': device_id})
        self.events[(device_id, ev['idempotency_key'])] = outcome


def _reject(key, msg):
    return {'idempotency_key': key, 'status': 'rejected', 'message': msg}


class SyncEngine:
    MAX_EVENTS = 200

    def __init__(self, repo):
        self.repo = repo

    def push(self, user: User, device_id: str, events: list):
        if not device_id or not isinstance(events, list) or len(events) > self.MAX_EVENTS:
            raise ValueError('payload batili')
        return [self._one(user, device_id, ev) for ev in events]

    def pull(self, user: User, company_uuid: str, cursor: int = 0, limit: int = 200):
        role = user.memberships.get(company_uuid)
        if role is None or not has_permission(role, 'sync:read'):
            raise PermissionError('hairuhusiwi kusoma kampuni hii')
        if not hasattr(self.repo, 'pull_records'):
            return {'records': [], 'next_cursor': cursor, 'has_more': False}
        mine_scope = user.mine_memberships.get(company_uuid)
        if hasattr(self.repo, 'mine_names') and mine_scope is not None:
            mine_scope = self.repo.mine_names(company_uuid, mine_scope)
        rows, next_cursor, more = self.repo.pull_records(
            company_uuid,
            cursor,
            min(max(limit, 1), 500),
            mine_uuids=mine_scope,
        )
        return {'records': rows, 'next_cursor': next_cursor, 'has_more': more}

    def _one(self, user, device_id, ev):
        key = ev.get('idempotency_key') if isinstance(ev, dict) else None
        if not isinstance(key, str) or not key:
            return _reject(str(key), 'idempotency_key inahitajika')
        entity, ruuid, company = ev.get('entity'), ev.get('record_uuid'), ev.get('company_uuid')
        version, data = ev.get('version'), ev.get('data')
        if entity not in ENTITIES:
            return _reject(key, 'entity haikubaliki')
        if not (isinstance(ruuid, str) and ruuid and isinstance(company, str) and company):
            return _reject(key, 'record_uuid/company_uuid vinahitajika')
        if not isinstance(version, int) or isinstance(version, bool) or version < 1:
            return _reject(key, 'version batili')
        if not isinstance(data, dict) or data.get('uuid') != ruuid:
            return _reject(key, 'data.uuid haiendani na record_uuid')
        if entity == 'companies' and ruuid != company:
            return _reject(key, 'rekodi ya kampuni lazima iwe ya kampuni husika')
        if entity == 'mines' and (
            not isinstance(data.get('name'), str) or not data['name'].strip()
        ):
            return _reject(key, 'jina la mgodi linahitajika')
        # App inatuma `company_id` kama JINA la kampuni (si uuid): kubali jina lililosajiliwa
        # kwa company_uuid hii au uuid yenyewe; kitu kingine ni jaribio la kuvuka tenant.
        cid = data.get('company_id')
        if entity != 'companies' and cid is not None:
            allowed = {company}
            name = self.repo.company_name(company) if hasattr(self.repo, 'company_name') else None
            if name:
                allowed.add(name)
            if str(cid) not in allowed:
                return _reject(key, 'company_id ya data haiendani na tenant')
        mine_id = data.get('mine_id')
        if entity not in ('companies', 'mines') and isinstance(mine_id, str) and mine_id.strip():
            if hasattr(self.repo, 'resolve_mine'):
                mine_uuid = self.repo.resolve_mine(company, mine_id.strip())
                if mine_uuid is None:
                    return _reject(key, 'mine_id haipo ndani ya kampuni hii')
                assigned_mines = user.mine_memberships.get(company)
                if assigned_mines is not None and mine_uuid not in assigned_mines:
                    return _reject(key, 'jukumu lako haliruhusu kutumia mgodi huu')
        if len(json.dumps(data, ensure_ascii=False, default=str).encode('utf-8')) > 262144:
            return _reject(key, 'rekodi imezidi ukubwa wa 256KB')
        role = user.memberships.get(company)
        if role is None or not can_write_entity(role, entity):
            return _reject(key, 'jukumu lako haliruhusu kuandika aina hii ya rekodi')
        # PostgreSQL implementation performs idempotency check, version decision,
        # record/conflict write, sync event and audit entry in ONE transaction.
        # MemoryRepo keeps the simpler path for deterministic unit tests.
        if hasattr(self.repo, 'process_event'):
            return self.repo.process_event(company, ev, device_id, user.id)
        if self.repo.get_event(device_id, key) is not None:
            return {'idempotency_key': key, 'status': 'duplicate'}
        existing = self.repo.get_record(company, entity, ruuid)
        if existing is None or (existing['device_id'] == device_id and version > existing['version']):
            self.repo.apply(company, ev, device_id, 'applied', user.id)
            return {'idempotency_key': key, 'status': 'applied', 'server_version': version}
        if existing['device_id'] == device_id:  # toleo la zamani/sawa kutoka kifaa kile kile
            self.repo.apply(company, ev, device_id, 'stale', user.id)
            return {'idempotency_key': key, 'status': 'duplicate', 'server_version': existing['version']}
        # Kifaa tofauti kinaandika rekodi iliyopo: HAKUNA silent overwrite.
        self.repo.apply(company, ev, device_id, 'conflict', user.id)
        return {'idempotency_key': key, 'status': 'conflict', 'server_version': existing['version'],
                'message': 'Rekodi imebadilishwa na kifaa kingine; inahitaji uamuzi.'}
