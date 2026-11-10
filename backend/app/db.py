"""PostgresRepo kwa Supabase PostgreSQL (psycopg 3). HAIJAJARIBIWA hapa: hakuna Postgres kwenye mazingira ya ujenzi."""
import json
import psycopg


class PostgresRepo:
    def __init__(self, dsn: str):
        self.dsn = dsn

    def _conn(self):
        return psycopg.connect(self.dsn)

    def company_name(self, company_uuid):
        with self._conn() as c:
            r = c.execute('SELECT name FROM companies WHERE id=%s', (company_uuid,)).fetchone()
        return r[0] if r else None

    def get_event(self, device_id, key):
        with self._conn() as c:
            r = c.execute('SELECT outcome FROM sync_events WHERE device_id=%s AND idempotency_key=%s',
                          (device_id, key)).fetchone()
        return r[0] if r else None

    def get_record(self, company_uuid, entity, record_uuid):
        with self._conn() as c:
            r = c.execute('SELECT version, data, device_id FROM sync_records '
                          'WHERE company_id=%s AND entity=%s AND record_uuid=%s',
                          (company_uuid, entity, record_uuid)).fetchone()
        return {'version': r[0], 'data': r[1], 'device_id': r[2]} if r else None

    def apply(self, company_uuid, ev, device_id, outcome, user_id):
        # `with conn` = transaction moja; commit hutokea TU kama kila kitu kimefaulu.
        with self._conn() as c:
            if outcome == 'applied':
                c.execute(
                    'INSERT INTO sync_records(company_id,entity,record_uuid,version,data,device_id,updated_by) '
                    'VALUES (%s,%s,%s,%s,%s,%s,%s) ON CONFLICT (company_id,entity,record_uuid) DO UPDATE '
                    'SET version=EXCLUDED.version, data=EXCLUDED.data, device_id=EXCLUDED.device_id, '
                    "updated_by=EXCLUDED.updated_by, updated_at=now(), seq=nextval('sync_records_seq')",
                    (company_uuid, ev['entity'], ev['record_uuid'], ev['version'],
                     json.dumps(ev['data']), device_id, user_id))
            elif outcome == 'conflict':
                c.execute('INSERT INTO sync_conflicts(company_id,entity,record_uuid,device_id,version,data) '
                          'VALUES (%s,%s,%s,%s,%s,%s)',
                          (company_uuid, ev['entity'], ev['record_uuid'], device_id, ev['version'],
                           json.dumps(ev['data'])))
            c.execute('INSERT INTO sync_events(device_id,idempotency_key,company_id,outcome,user_id) '
                      'VALUES (%s,%s,%s,%s,%s)',
                      (device_id, ev['idempotency_key'], company_uuid, outcome, user_id))
            c.execute('INSERT INTO audit_log(company_id,user_id,action,entity,record_uuid,detail) '
                      'VALUES (%s,%s,%s,%s,%s,%s)',
                      (company_uuid, user_id, 'sync_' + outcome, ev['entity'], ev['record_uuid'],
                       json.dumps({'version': ev['version'], 'device_id': device_id})))


    def process_event(self, company_uuid, ev, device_id, user_id):
        """Atomic PostgreSQL event processing.

        Locks the idempotency key and then the company stream. The first lock prevents
        duplicate concurrent deliveries from writing twice; the company lock keeps
        committed sequence allocation ordered for cursor-based pull sync.
        """
        key = ev['idempotency_key']
        with self._conn() as c:
            c.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s, 1))",
                      (device_id + ':' + key,))
            c.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))",
                      ('madini-company-stream:' + company_uuid,))

            seen = c.execute(
                'SELECT outcome FROM sync_events WHERE device_id=%s AND idempotency_key=%s',
                (device_id, key)).fetchone()
            if seen:
                return {'idempotency_key': key, 'status': 'duplicate'}

            existing = c.execute(
                'SELECT version,device_id FROM sync_records '
                'WHERE company_id=%s AND entity=%s AND record_uuid=%s FOR UPDATE',
                (company_uuid, ev['entity'], ev['record_uuid'])).fetchone()

            if existing is None or (existing[1] == device_id and ev['version'] > existing[0]):
                outcome = 'applied'
                c.execute(
                    'INSERT INTO sync_records(company_id,entity,record_uuid,version,data,device_id,updated_by) '
                    'VALUES (%s,%s,%s,%s,%s,%s,%s) ON CONFLICT (company_id,entity,record_uuid) DO UPDATE '
                    'SET version=EXCLUDED.version,data=EXCLUDED.data,device_id=EXCLUDED.device_id, '
                    "updated_by=EXCLUDED.updated_by,updated_at=now(),seq=nextval('sync_records_seq')",
                    (company_uuid, ev['entity'], ev['record_uuid'], ev['version'],
                     json.dumps(ev['data']), device_id, user_id))
            elif existing[1] == device_id:
                outcome = 'stale'
            else:
                outcome = 'conflict'
                c.execute(
                    'INSERT INTO sync_conflicts(company_id,entity,record_uuid,device_id,version,data) '
                    'VALUES (%s,%s,%s,%s,%s,%s)',
                    (company_uuid, ev['entity'], ev['record_uuid'], device_id, ev['version'],
                     json.dumps(ev['data'])))

            c.execute(
                'INSERT INTO sync_events(device_id,idempotency_key,company_id,outcome,user_id) '
                'VALUES (%s,%s,%s,%s,%s)', (device_id, key, company_uuid, outcome, user_id))
            c.execute(
                'INSERT INTO audit_log(company_id,user_id,action,entity,record_uuid,detail) '
                'VALUES (%s,%s,%s,%s,%s,%s)',
                (company_uuid, user_id, 'sync_' + outcome, ev['entity'], ev['record_uuid'],
                 json.dumps({'version': ev['version'], 'device_id': device_id,
                             'idempotency_key': key})))

        if outcome == 'applied':
            return {'idempotency_key': key, 'status': 'applied', 'server_version': ev['version']}
        if outcome == 'stale':
            return {'idempotency_key': key, 'status': 'duplicate', 'server_version': existing[0]}
        return {'idempotency_key': key, 'status': 'conflict', 'server_version': existing[0],
                'message': 'Rekodi imebadilishwa na kifaa kingine; inahitaji uamuzi.'}

    def get_user_by_name(self, username):
        with self._conn() as c:
            u = c.execute('SELECT id::text, password_hash, active FROM users WHERE username=%s',
                          (username,)).fetchone()
            if not u:
                return None
            m = c.execute('SELECT company_id::text, role FROM memberships WHERE user_id=%s', (u[0],)).fetchall()
        return {'id': u[0], 'password_hash': u[1], 'active': u[2], 'memberships': {a: b for a, b in m}}

    def register_device(self, user_id, device_id, name):
        with self._conn() as c:
            c.execute('INSERT INTO devices(user_id,device_id,name) VALUES (%s,%s,%s) '
                      'ON CONFLICT (user_id,device_id) DO UPDATE SET last_seen=now(), revoked_at=NULL',
                      (user_id, device_id, name))


    def device_belongs_to_user(self, user_id, device_id):
        with self._conn() as c:
            r = c.execute('SELECT 1 FROM devices WHERE user_id=%s AND device_id=%s AND revoked_at IS NULL',
                          (user_id, device_id)).fetchone()
        return bool(r)

    def pull_records(self, company_uuid, cursor, limit):
        with self._conn() as c:
            rows = c.execute(
                'SELECT seq,entity,record_uuid,version,data,updated_at,device_id FROM sync_records '
                'WHERE company_id=%s AND seq>%s ORDER BY seq LIMIT %s',
                (company_uuid, cursor, limit + 1)).fetchall()
        more = len(rows) > limit
        rows = rows[:limit]
        result = [{'cursor': r[0], 'entity': r[1], 'record_uuid': r[2],
                   'version': r[3], 'data': r[4], 'updated_at': r[5].isoformat(), 'device_id': r[6]}
                  for r in rows]
        return result, (rows[-1][0] if rows else cursor), more

    def list_conflicts(self, company_uuid, limit=100):
        with self._conn() as c:
            rows = c.execute(
                "SELECT id,entity,record_uuid,device_id,version,data,created_at "
                "FROM sync_conflicts WHERE company_id=%s AND status='open' "
                "ORDER BY id LIMIT %s", (company_uuid, limit)).fetchall()
        return [{'id': r[0], 'entity': r[1], 'record_uuid': r[2], 'device_id': r[3],
                 'version': r[4], 'data': r[5], 'created_at': r[6].isoformat()} for r in rows]

    def resolve_conflict(self, company_uuid, conflict_id, decision, user_id):
        with self._conn() as c:
            # Same per-company lock used by push: pull cursors cannot skip a late commit.
            c.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))",
                      ('madini-company-stream:' + company_uuid,))
            row = c.execute(
                "SELECT entity,record_uuid,version,data,device_id FROM sync_conflicts "
                "WHERE id=%s AND company_id=%s AND status='open' FOR UPDATE",
                (conflict_id, company_uuid)).fetchone()
            if not row:
                return False
            if decision == 'accept_conflict':
                c.execute(
                    'INSERT INTO sync_records(company_id,entity,record_uuid,version,data,device_id,updated_by) '
                    'VALUES (%s,%s,%s,%s,%s,%s,%s) ON CONFLICT (company_id,entity,record_uuid) DO UPDATE '
                    'SET version=EXCLUDED.version,data=EXCLUDED.data,device_id=EXCLUDED.device_id,'
                    "updated_by=EXCLUDED.updated_by,updated_at=now(),seq=nextval('sync_records_seq')",
                    (company_uuid, row[0], row[1], row[2], json.dumps(row[3]), row[4], user_id))
            c.execute("UPDATE sync_conflicts SET status=%s,resolved_by=%s,resolved_at=now() WHERE id=%s",
                      (decision, user_id, conflict_id))
            c.execute('INSERT INTO audit_log(company_id,user_id,action,entity,record_uuid,detail) '
                      'VALUES (%s,%s,%s,%s,%s,%s)',
                      (company_uuid,user_id,'conflict_'+decision,row[0],row[1],
                       json.dumps({'conflict_id': conflict_id})))
        return True


    def ping(self):
        with self._conn() as c:
            c.execute('SELECT 1').fetchone()

    def token_revoked(self, jti):
        with self._conn() as c:
            r = c.execute('SELECT 1 FROM revoked_tokens WHERE jti=%s', (jti,)).fetchone()
        return bool(r)

    def revoke_token(self, jti, user_id, exp):
        import datetime
        expires = datetime.datetime.fromtimestamp(int(exp), datetime.timezone.utc)
        with self._conn() as c:
            c.execute('INSERT INTO revoked_tokens(jti,user_id,expires_at) VALUES (%s,%s,%s) '
                      'ON CONFLICT (jti) DO NOTHING', (jti, user_id, expires))

    def create_company_user(self, username, password_hash, company_uuid, role):
        import uuid
        uid = str(uuid.uuid4())
        with self._conn() as c:
            c.execute('INSERT INTO users(id,username,password_hash) VALUES (%s,%s,%s)',
                      (uid, username, password_hash))
            c.execute('INSERT INTO memberships(user_id,company_id,role) VALUES (%s,%s,%s)',
                      (uid, company_uuid, role))
        return uid

    def bootstrap_company_owner(self, company_name, username, password_hash, company_uuid=None):
        import uuid
        # company_uuid LAZIMA iwe ile ya app (Usawazishaji > Kitambulisho cha kampuni).
        company_id, user_id = company_uuid or str(uuid.uuid4()), str(uuid.uuid4())
        with self._conn() as c:
            c.execute('INSERT INTO companies(id,name) VALUES (%s,%s)', (company_id, company_name))
            c.execute('INSERT INTO users(id,username,password_hash) VALUES (%s,%s,%s)',
                      (user_id, username, password_hash))
            c.execute('INSERT INTO memberships(user_id,company_id,role) VALUES (%s,%s,%s)',
                      (user_id, company_id, 'company_owner'))
        return {'company_uuid': company_id, 'user_id': user_id}
