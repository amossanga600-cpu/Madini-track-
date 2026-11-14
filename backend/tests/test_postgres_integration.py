"""Real FastAPI + PostgreSQL integration tests (no mocked repository)."""

import os
import json
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlparse

import psycopg
from fastapi.testclient import TestClient

from app.core import SyncEngine, User
from app.db import PostgresRepo


TEST_DSN = os.environ.get('TEST_DATABASE_URL')
os.environ.setdefault(
    'DATABASE_URL',
    TEST_DSN or 'postgresql://unused:unused@127.0.0.1:1/madini_test',
)
os.environ.setdefault('JWT_SECRET', 'integration-tests-only-secret-value-32-bytes-minimum')
os.environ.setdefault('APP_ENV', 'development')

from app import main  # noqa: E402


def _uuid():
    return str(uuid.uuid4())


def _event(company_uuid, entity, record_uuid, data, version=1, key=None):
    return {
        'company_uuid': company_uuid,
        'entity': entity,
        'record_uuid': record_uuid,
        'version': version,
        'idempotency_key': key or f'{entity}:{record_uuid}:{version}',
        'data': data,
    }


@unittest.skipUnless(
    TEST_DSN, 'TEST_DATABASE_URL is not configured'
)
class PostgreSQLApiIntegrationTests(unittest.TestCase):
    def setUp(self):
        if not TEST_DSN:
            self.skipTest('Set TEST_DATABASE_URL to a disposable local PostgreSQL test database.')
        parsed = urlparse(TEST_DSN)
        if parsed.hostname not in ('localhost', '127.0.0.1', '::1') or 'test' not in parsed.path.lower():
            raise RuntimeError(
                'Refusing PostgreSQL integration tests unless TEST_DATABASE_URL points '
                'to a loopback database whose name contains "test".'
            )
        self.schema = f"madini_test_{uuid.uuid4().hex}"
        with psycopg.connect(TEST_DSN) as connection:
            connection.execute(f'CREATE SCHEMA "{self.schema}"')
        self.repo = PostgresRepo(
            TEST_DSN,
            connect_kwargs={'options': f'-c search_path={self.schema}'},
            min_size=1,
            max_size=6,
        )
        main.repo = self.repo
        main.engine = SyncEngine(self.repo)
        self.client = TestClient(main.app)
        self.client.__enter__()
        self.company_a = _uuid()
        self.company_b = _uuid()
        self.owner_a = self.repo.bootstrap_company_owner(
            'Kampuni A', 'owner-a', main.hasher.hash('correct-horse-battery-a'),
            self.company_a,
        )
        self.owner_b = self.repo.bootstrap_company_owner(
            'Kampuni B', 'owner-b', main.hasher.hash('correct-horse-battery-b'),
            self.company_b,
        )
        self.device_a = _uuid()
        self.device_b = _uuid()
        self.token_a = self.login('owner-a', 'correct-horse-battery-a', self.device_a)
        self.token_b = self.login('owner-b', 'correct-horse-battery-b', self.device_b)

    def tearDown(self):
        client = getattr(self, 'client', None)
        if client:
            client.__exit__(None, None, None)
        repo = getattr(self, 'repo', None)
        if repo:
            repo.close()
        schema = getattr(self, 'schema', None)
        if schema:
            with psycopg.connect(TEST_DSN) as connection:
                connection.execute(f'DROP SCHEMA "{schema}" CASCADE')

    def login(self, username, password, device_id=None):
        response = self.client.post('/v1/auth/login', json={
            'username': username,
            'password': password,
            'device_id': device_id or _uuid(),
            'device_name': 'PostgreSQL integration test',
        })
        assert response.status_code == 200, response.text
        return response.json()['access_token']

    @staticmethod
    def auth(token):
        return {'Authorization': f'Bearer {token}'}

    def push(self, token, device_id, *events):
        return self.client.post(
            '/v1/sync/push',
            headers=self.auth(token),
            json={'device_id': device_id, 'events': list(events)},
        )

    def add_mine(self, company_uuid, token, device_id, name):
        mine_uuid = _uuid()
        event = _event(company_uuid, 'mines', mine_uuid, {
            'uuid': mine_uuid,
            'company_id': 'Kampuni A' if company_uuid == self.company_a else 'Kampuni B',
            'name': name,
        })
        result = self.push(token, device_id, event)
        assert result.status_code == 200, result.text
        assert result.json()['results'][0]['status'] == 'applied'
        return mine_uuid

    def test_api_startup_migrations_and_health(self):
        self.assertEqual(self.client.get('/health').json()['status'], 'ok')
        self.assertEqual(self.client.get('/health/ready').status_code, 200)
        with self.repo._conn() as connection:
            versions = connection.execute(
                'SELECT version FROM schema_migrations ORDER BY version'
            ).fetchall()
        self.assertEqual([row[0] for row in versions], ['0001_baseline', '0002'])
        self.assertEqual(self.repo.migrate(), [])

    def test_jwt_rotation_logout_and_database_rate_limit(self):
        for _ in range(main.LOGIN_MAX_ATTEMPTS):
            response = self.client.post('/v1/auth/login', json={
                'username': 'nobody',
                'password': 'incorrect-password',
                'device_id': _uuid(),
            })
            self.assertEqual(response.status_code, 401)
        limited = self.client.post('/v1/auth/login', json={
            'username': 'nobody',
            'password': 'incorrect-password',
            'device_id': _uuid(),
        })
        self.assertEqual(limited.status_code, 429)

        response = self.client.post(
            '/v1/auth/refresh', headers=self.auth(self.token_a)
        )
        self.assertEqual(response.status_code, 200, response.text)
        rotated = response.json()['access_token']
        self.assertEqual(
            self.client.get('/v1/auth/me', headers=self.auth(self.token_a)).status_code,
            401,
        )
        self.assertEqual(
            self.client.get('/v1/auth/me', headers=self.auth(rotated)).status_code,
            200,
        )
        self.assertEqual(
            self.client.post('/v1/auth/logout', headers=self.auth(rotated)).status_code,
            200,
        )
        self.assertEqual(
            self.client.get('/v1/auth/me', headers=self.auth(rotated)).status_code,
            401,
        )

    def test_tenant_mine_scope_conflict_audit_and_batch_trace(self):
        mine_a = self.add_mine(
            self.company_a, self.token_a, self.device_a, 'Mgodi Alpha'
        )
        mine_b = self.add_mine(
            self.company_a, self.token_a, self.device_a, 'Mgodi Beta'
        )
        batch_uuid = _uuid()
        production_uuid = _uuid()
        batch_id = 'B-DEVICE-0001'
        batch_data = {
            'uuid': batch_uuid,
            'company_id': 'Kampuni A',
            'mine_id': 'Mgodi Alpha',
            'batch_id': batch_id,
            'parent_batch_id': None,
            'weight_kg': 12.5,
        }
        production_data = {
            'uuid': production_uuid,
            'batch_uuid': batch_uuid,
            'company_id': 'Kampuni A',
            'mine_id': 'Mgodi Alpha',
            'batch_id': batch_id,
            'quantity_kg': 12.5,
        }
        batch_event = _event(
            self.company_a, 'ore_batches', batch_uuid, batch_data
        )
        production_event = _event(
            self.company_a, 'production_records', production_uuid, production_data
        )
        self.assertEqual(
            self.push(self.token_a, self.device_a, batch_event).json()['results'][0]['status'],
            'applied',
        )
        first = self.push(self.token_a, self.device_a, production_event)
        self.assertEqual(first.json()['results'][0]['status'], 'applied')
        repeated = self.push(self.token_a, self.device_a, production_event)
        self.assertEqual(repeated.json()['results'][0]['status'], 'duplicate')

        second_token = self.login(
            'owner-a', 'correct-horse-battery-a', self.device_b
        )
        updated = dict(production_data, quantity_kg=10.0)
        conflict_event = _event(
            self.company_a, 'production_records', production_uuid, updated,
            version=2,
        )
        conflict = self.push(second_token, self.device_b, conflict_event)
        self.assertEqual(conflict.json()['results'][0]['status'], 'conflict')
        self.assertEqual(
            self.push(second_token, self.device_b, conflict_event)
            .json()['results'][0]['status'],
            'conflict',
        )

        other_tenant = self.client.get(
            f'/v1/sync/pull?company_uuid={self.company_a}&cursor=0',
            headers=self.auth(self.token_b),
        )
        self.assertEqual(other_tenant.status_code, 403)
        cross_tenant = dict(production_event, company_uuid=self.company_a)
        rejected = self.push(self.token_b, self.device_b, cross_tenant)
        self.assertEqual(rejected.status_code, 200)
        self.assertEqual(rejected.json()['results'][0]['status'], 'rejected')

        listed = self.client.get(
            f'/v1/sync/conflicts?company_uuid={self.company_a}',
            headers=self.auth(self.token_a),
        )
        self.assertEqual(listed.status_code, 200)
        conflict_id = listed.json()['conflicts'][0]['id']
        resolved = self.client.post(
            f'/v1/sync/conflicts/{conflict_id}/resolve?company_uuid={self.company_a}',
            headers=self.auth(self.token_a),
            json={'decision': 'accept_conflict'},
        )
        self.assertEqual(resolved.status_code, 200, resolved.text)

        pulled = self.client.get(
            f'/v1/sync/pull?company_uuid={self.company_a}&cursor=0&limit=2',
            headers=self.auth(self.token_a),
        )
        self.assertEqual(pulled.status_code, 200)
        self.assertTrue(pulled.json()['has_more'])
        cursor = pulled.json()['next_cursor']
        pulled_remaining = self.client.get(
            f'/v1/sync/pull?company_uuid={self.company_a}&cursor={cursor}&limit=20',
            headers=self.auth(self.token_a),
        ).json()['records']
        records = pulled.json()['records'] + pulled_remaining
        production = next(
            record for record in records
            if record['record_uuid'] == production_uuid
        )
        self.assertEqual(production['version'], 3)
        self.assertEqual(production['data']['quantity_kg'], 10.0)

        audit = self.client.get(
            f'/v1/audit?company_uuid={self.company_a}&limit=100',
            headers=self.auth(self.token_a),
        )
        self.assertEqual(audit.status_code, 200, audit.text)
        self.assertTrue(audit.json()['chain_valid'])
        self.assertTrue(audit.json()['entries'])
        with self.assertRaises(psycopg.errors.RaiseException):
            with self.repo._conn() as connection:
                connection.execute(
                    'UPDATE audit_log SET action=%s WHERE company_id=%s',
                    ('tampered', self.company_a),
                )

        trace = self.client.get(
            f'/v1/batches/{batch_uuid}/trace?company_uuid={self.company_a}',
            headers=self.auth(self.token_a),
        )
        self.assertEqual(trace.status_code, 200, trace.text)
        self.assertEqual(trace.json()['batches'][0]['record_uuid'], batch_uuid)
        self.assertEqual(
            trace.json()['related']['production_records'][0]['record_uuid'],
            production_uuid,
        )
        duplicate_uuid = _uuid()
        duplicate_event = _event(
            self.company_a,
            'ore_batches',
            duplicate_uuid,
            dict(batch_data, uuid=duplicate_uuid),
        )
        rejected_batch = self.push(self.token_a, self.device_a, duplicate_event)
        self.assertEqual(rejected_batch.json()['results'][0]['status'], 'rejected')

        other_mine_batch_uuid = _uuid()
        other_mine_batch = _event(
            self.company_a,
            'ore_batches',
            other_mine_batch_uuid,
            dict(batch_data, uuid=other_mine_batch_uuid, mine_id='Mgodi Beta'),
        )
        rejected_other_mine = self.push(
            self.token_a, self.device_a, other_mine_batch
        )
        self.assertEqual(
            rejected_other_mine.json()['results'][0]['status'], 'rejected'
        )
        with self.repo._conn() as connection:
            connection.execute(
                """
                INSERT INTO sync_records
                  (company_id,entity,record_uuid,version,data,device_id,updated_by)
                VALUES (%s,'ore_batches',%s,1,%s,%s,%s)
                """,
                (
                    self.company_a,
                    other_mine_batch_uuid,
                    json.dumps(
                        dict(
                            batch_data,
                            uuid=other_mine_batch_uuid,
                            mine_id='Mgodi Beta',
                        )
                    ),
                    self.device_a,
                    self.owner_a['user_id'],
                ),
            )
        ambiguous_label = self.client.get(
            f'/v1/batches/{batch_id}/trace?company_uuid={self.company_a}',
            headers=self.auth(self.token_a),
        )
        self.assertEqual(ambiguous_label.status_code, 409, ambiguous_label.text)

        scoped_user = self.client.post(
            '/v1/admin/users',
            headers=self.auth(self.token_a),
            json={
                'username': 'mine-operator',
                'password': 'operator-password-long',
                'role': 'production_supervisor',
                'company_uuid': self.company_a,
                'mine_uuids': [mine_a],
            },
        )
        self.assertEqual(scoped_user.status_code, 200, scoped_user.text)
        operator_token = self.login(
            'mine-operator', 'operator-password-long', _uuid()
        )
        scoped_pull = self.client.get(
            f'/v1/sync/pull?company_uuid={self.company_a}&cursor=0&limit=100',
            headers=self.auth(operator_token),
        )
        self.assertEqual(scoped_pull.status_code, 200)
        scoped_ids = {row['record_uuid'] for row in scoped_pull.json()['records']}
        self.assertIn(mine_a, scoped_ids)
        self.assertNotIn(mine_b, scoped_ids)
        forbidden_audit = self.client.get(
            f'/v1/audit?company_uuid={self.company_a}',
            headers=self.auth(operator_token),
        )
        self.assertEqual(forbidden_audit.status_code, 403)
        hidden_trace = self.client.get(
            f'/v1/batches/{other_mine_batch_uuid}/trace?company_uuid={self.company_a}',
            headers=self.auth(operator_token),
        )
        self.assertEqual(hidden_trace.status_code, 404)

    def test_concurrent_duplicate_delivery_is_applied_once(self):
        mine_uuid = self.add_mine(
            self.company_a, self.token_a, self.device_a, 'Mgodi Concurrent'
        )
        record_uuid = _uuid()
        event = _event(
            self.company_a,
            'workers',
            record_uuid,
            {
                'uuid': record_uuid,
                'company_id': 'Kampuni A',
                'mine_id': 'Mgodi Concurrent',
                'full_name': 'Mfanyakazi',
            },
            key=f'workers:{record_uuid}:1',
        )
        user = User(
            self.owner_a['user_id'],
            {self.company_a: 'company_owner'},
            self.device_a,
        )
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(
                lambda _: self.repo.process_event(
                    self.company_a, event, self.device_a, user.id
                ),
                range(2),
            ))
        self.assertEqual(
            sorted(result['status'] for result in results),
            ['applied', 'duplicate'],
        )
        self.assertEqual(
            self.repo.get_record(self.company_a, 'workers', record_uuid)['data']['mine_id'],
            'Mgodi Concurrent',
        )
