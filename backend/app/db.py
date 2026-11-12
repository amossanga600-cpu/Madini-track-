"""PostgreSQL repository. Every write that changes sync state is transactional."""
import hashlib
import json
import uuid
from datetime import datetime, timezone

import psycopg
from psycopg_pool import ConnectionPool


def _append_audit(
    connection, company_uuid, user_id, action, entity, record_uuid, detail
):
    previous = connection.execute(
        """
        SELECT entry_hash FROM audit_log
        WHERE company_id=%s AND entry_hash IS NOT NULL
        ORDER BY id DESC LIMIT 1
        """,
        (company_uuid,),
    ).fetchone()
    previous_hash = previous[0] if previous else "0" * 64
    created_at = datetime.now(timezone.utc)
    canonical = {
        "company_id": str(company_uuid),
        "user_id": str(user_id),
        "action": action,
        "entity": entity,
        "record_uuid": record_uuid,
        "detail": detail,
        "created_at": created_at.isoformat(),
    }
    encoded = json.dumps(
        canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":"), default=str
    ).encode("utf-8")
    entry_hash = hashlib.sha256(
        bytes.fromhex(previous_hash) + encoded
    ).hexdigest()
    connection.execute(
        """
        INSERT INTO audit_log
          (company_id,user_id,action,entity,record_uuid,detail,created_at,
           previous_hash,entry_hash)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        (
            company_uuid,
            user_id,
            action,
            entity,
            record_uuid,
            json.dumps(detail, ensure_ascii=False, default=str),
            created_at,
            previous_hash,
            entry_hash,
        ),
    )


class PostgresRepo:
    def __init__(self, dsn: str, *, connect_kwargs=None, min_size=1, max_size=10):
        self.dsn = dsn
        self.pool = ConnectionPool(
            conninfo=dsn,
            kwargs=connect_kwargs or {},
            min_size=min_size,
            max_size=max_size,
            timeout=10,
            open=False,
        )

    def open(self):
        self.pool.open(wait=True, timeout=10)

    def _conn(self):
        return self.pool.connection()

    def close(self):
        self.pool.close()

    def migrate(self):
        from .migrations import migrate

        with self._conn() as c:
            return migrate(c)

    def consume_login_attempt(self, bucket, max_attempts, window_seconds):
        with self._conn() as c:
            c.execute(
                "DELETE FROM login_rate_limits WHERE updated_at < now() - interval '1 day'"
            )
            row = c.execute(
                """
                INSERT INTO login_rate_limits(bucket, window_started_at, attempts)
                VALUES (%s, now(), 1)
                ON CONFLICT (bucket) DO UPDATE SET
                  attempts = CASE
                    WHEN login_rate_limits.window_started_at <=
                      now() - (%s * interval '1 second') THEN 1
                    ELSE login_rate_limits.attempts + 1
                  END,
                  window_started_at = CASE
                    WHEN login_rate_limits.window_started_at <=
                      now() - (%s * interval '1 second') THEN now()
                    ELSE login_rate_limits.window_started_at
                  END,
                  updated_at = now()
                RETURNING attempts
                """,
                (bucket, window_seconds, window_seconds),
            ).fetchone()
        return row[0] <= max_attempts

    def clear_login_attempts(self, bucket):
        with self._conn() as c:
            c.execute("DELETE FROM login_rate_limits WHERE bucket=%s", (bucket,))

    def resolve_mine(self, company_uuid, mine_id):
        with self._conn() as c:
            row = c.execute(
                """
                SELECT record_uuid
                FROM sync_records
                WHERE company_id=%s AND entity='mines'
                  AND (record_uuid=%s OR data->>'name'=%s)
                ORDER BY CASE WHEN record_uuid=%s THEN 0 ELSE 1 END
                LIMIT 1
                """,
                (company_uuid, mine_id, mine_id, mine_id),
            ).fetchone()
        return row[0] if row else None

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
            c.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))",
                      ('madini-company-stream:' + company_uuid,))
            previous = c.execute(
                'SELECT data FROM sync_records WHERE company_id=%s AND entity=%s '
                'AND record_uuid=%s FOR UPDATE',
                (company_uuid, ev['entity'], ev['record_uuid']),
            ).fetchone()
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
            _append_audit(
                c, company_uuid, user_id, 'sync_' + outcome, ev['entity'],
                ev['record_uuid'], {
                    'version': ev['version'],
                    'device_id': device_id,
                    'idempotency_key': ev['idempotency_key'],
                    'mine_id': ev['data'].get('mine_id'),
                    'previous_data': previous[0] if previous else None,
                    'updated_data': ev['data'] if outcome == 'applied' else None,
                },
            )


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
                if seen[0] in ('applied', 'stale'):
                    return {'idempotency_key': key, 'status': 'duplicate'}
                if seen[0] == 'conflict':
                    current = c.execute(
                        'SELECT version FROM sync_records WHERE company_id=%s AND entity=%s '
                        'AND record_uuid=%s',
                        (company_uuid, ev['entity'], ev['record_uuid']),
                    ).fetchone()
                    return {
                        'idempotency_key': key,
                        'status': 'conflict',
                        'server_version': current[0] if current else None,
                        'message': 'Rekodi inahitaji uamuzi wa mgongano.',
                    }
                return {
                    'idempotency_key': key,
                    'status': 'rejected',
                    'message': 'Tukio hili lilikataliwa awali.',
                }

            if ev['entity'] == 'mines':
                duplicate_mine = c.execute(
                    """
                    SELECT 1 FROM sync_records
                    WHERE company_id=%s AND entity='mines'
                      AND lower(data->>'name')=lower(%s) AND record_uuid<>%s
                    LIMIT 1
                    """,
                    (company_uuid, ev['data']['name'].strip(), ev['record_uuid']),
                ).fetchone()
                if duplicate_mine:
                    c.execute(
                        'INSERT INTO sync_events(device_id,idempotency_key,company_id,outcome,user_id) '
                        'VALUES (%s,%s,%s,%s,%s)',
                        (device_id, key, company_uuid, 'rejected', user_id),
                    )
                    _append_audit(
                        c, company_uuid, user_id, 'sync_rejected', 'mines',
                        ev['record_uuid'], {
                            'device_id': device_id,
                            'idempotency_key': key,
                            'reason': 'mine_name_already_exists',
                            'proposed_data': ev['data'],
                        },
                    )
                    return {
                        'idempotency_key': key,
                        'status': 'rejected',
                        'message': 'Jina la mgodi limetumika tayari ndani ya kampuni.',
                    }

            existing = c.execute(
                'SELECT version,device_id,data FROM sync_records '
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
                outcome_data = ev['data']
            elif existing[1] == device_id:
                outcome = 'stale'
                outcome_data = existing[2]
            else:
                outcome = 'conflict'
                outcome_data = existing[2]
                c.execute(
                    'INSERT INTO sync_conflicts(company_id,entity,record_uuid,device_id,version,data) '
                    'VALUES (%s,%s,%s,%s,%s,%s)',
                    (company_uuid, ev['entity'], ev['record_uuid'], device_id, ev['version'],
                     json.dumps(ev['data'])))

            c.execute(
                'INSERT INTO sync_events(device_id,idempotency_key,company_id,outcome,user_id) '
                'VALUES (%s,%s,%s,%s,%s)', (device_id, key, company_uuid, outcome, user_id))
            _append_audit(
                c,
                company_uuid,
                user_id,
                'sync_' + outcome,
                ev['entity'],
                ev['record_uuid'],
                {
                    'version': ev['version'],
                    'device_id': device_id,
                    'idempotency_key': key,
                    'mine_id': ev['data'].get('mine_id'),
                    'previous_data': existing[2] if existing else None,
                    'updated_data': ev['data'] if outcome == 'applied' else outcome_data,
                    'proposed_data': ev['data'] if outcome != 'applied' else None,
                },
            )

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

    def mine_names(self, company_uuid, mine_uuids):
        if not mine_uuids:
            return set()
        with self._conn() as c:
            rows = c.execute(
                """
                SELECT record_uuid,data->>'name' FROM sync_records
                WHERE company_id=%s AND entity='mines' AND record_uuid=ANY(%s)
                """,
                (company_uuid, list(mine_uuids)),
            ).fetchall()
        return {value for row in rows for value in row if value}

    def pull_records(self, company_uuid, cursor, limit, mine_uuids=None):
        with self._conn() as c:
            if mine_uuids is None:
                rows = c.execute(
                    'SELECT seq,entity,record_uuid,version,data,updated_at,device_id FROM sync_records '
                    'WHERE company_id=%s AND seq>%s ORDER BY seq LIMIT %s',
                    (company_uuid, cursor, limit + 1)).fetchall()
            elif not mine_uuids:
                rows = []
            else:
                rows = c.execute(
                    """
                    SELECT seq,entity,record_uuid,version,data,updated_at,device_id
                    FROM sync_records
                    WHERE company_id=%s AND seq>%s
                      AND (
                        entity='companies'
                        OR (entity='mines' AND record_uuid=ANY(%s))
                        OR data->>'mine_id'=ANY(%s)
                      )
                    ORDER BY seq LIMIT %s
                    """,
                    (company_uuid, cursor, list(mine_uuids), list(mine_uuids), limit + 1),
                ).fetchall()
        more = len(rows) > limit
        rows = rows[:limit]
        result = [{'cursor': r[0], 'entity': r[1], 'record_uuid': r[2],
                   'version': r[3], 'data': r[4], 'updated_at': r[5].isoformat(), 'device_id': r[6]}
                  for r in rows]
        return result, (rows[-1][0] if rows else cursor), more

    def list_conflicts(self, company_uuid, limit=100, mine_uuids=None):
        mine_names = None
        if mine_uuids is not None:
            mine_names = self.mine_names(company_uuid, mine_uuids)
            mine_names.update(mine_uuids)
        with self._conn() as c:
            if mine_uuids is None:
                rows = c.execute(
                    "SELECT id,entity,record_uuid,device_id,version,data,created_at "
                    "FROM sync_conflicts WHERE company_id=%s AND status='open' "
                    "ORDER BY id LIMIT %s", (company_uuid, limit)).fetchall()
            elif mine_uuids:
                rows = c.execute(
                    """
                    SELECT id,entity,record_uuid,device_id,version,data,created_at
                    FROM sync_conflicts
                    WHERE company_id=%s AND status='open'
                      AND data->>'mine_id'=ANY(%s)
                    ORDER BY id LIMIT %s
                    """,
                    (company_uuid, list(mine_names), limit),
                ).fetchall()
            else:
                rows = []
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
            current = c.execute(
                "SELECT version,data,device_id FROM sync_records "
                "WHERE company_id=%s AND entity=%s AND record_uuid=%s FOR UPDATE",
                (company_uuid, row[0], row[1]),
            ).fetchone()
            next_version = max(row[2], current[0] if current else 0) + 1
            resolved_version = next_version if decision == 'accept_conflict' else (
                current[0] if current else 0
            )
            if decision == 'accept_conflict':
                c.execute(
                    'INSERT INTO sync_records(company_id,entity,record_uuid,version,data,device_id,updated_by) '
                    'VALUES (%s,%s,%s,%s,%s,%s,%s) ON CONFLICT (company_id,entity,record_uuid) DO UPDATE '
                    'SET version=EXCLUDED.version,data=EXCLUDED.data,device_id=EXCLUDED.device_id,'
                    "updated_by=EXCLUDED.updated_by,updated_at=now(),seq=nextval('sync_records_seq')",
                    (company_uuid, row[0], row[1], next_version,
                     json.dumps(row[3]), row[4], user_id))
            c.execute("UPDATE sync_conflicts SET status=%s,resolved_by=%s,resolved_at=now() WHERE id=%s",
                      (decision, user_id, conflict_id))
            _append_audit(
                c,
                company_uuid,
                user_id,
                'conflict_' + decision,
                row[0],
                row[1],
                {
                    'conflict_id': conflict_id,
                    'version': resolved_version,
                    'mine_id': row[3].get('mine_id'),
                    'previous_data': current[1] if current else None,
                    'updated_data': row[3] if decision == 'accept_conflict'
                    else current[1] if current else None,
                },
            )
        return True

    def audit_entries(self, company_uuid, after_id=0, limit=200,
                      mine_id=None, mine_uuids=None):
        mine_filter = None
        if mine_id is not None:
            mine_uuid = self.resolve_mine(company_uuid, mine_id)
            mine_filter = {mine_id, mine_uuid} if mine_uuid else {mine_id}
        elif mine_uuids is not None:
            mine_filter = self.mine_names(company_uuid, mine_uuids)
            mine_filter.update(mine_uuids)
        with self._conn() as c:
            if mine_filter is not None and not mine_filter:
                rows = []
            elif mine_filter is None:
                rows = c.execute(
                    """
                    SELECT company_id::text,id,user_id::text,action,entity,record_uuid,detail,created_at,
                           previous_hash,entry_hash
                    FROM audit_log WHERE company_id=%s AND id>%s
                    ORDER BY id LIMIT %s
                    """,
                    (company_uuid, after_id, limit + 1),
                ).fetchall()
            else:
                rows = c.execute(
                    """
                    SELECT company_id::text,id,user_id::text,action,entity,record_uuid,detail,created_at,
                           previous_hash,entry_hash
                    FROM audit_log
                    WHERE company_id=%s AND id>%s AND detail->>'mine_id'=ANY(%s)
                    ORDER BY id LIMIT %s
                    """,
                    (company_uuid, after_id, list(mine_filter), limit + 1),
                ).fetchall()
            chain = c.execute(
                """
                SELECT company_id::text,id,user_id::text,action,entity,record_uuid,detail,created_at,
                       previous_hash,entry_hash
                FROM audit_log WHERE company_id=%s AND entry_hash IS NOT NULL
                ORDER BY id
                """,
                (company_uuid,),
            ).fetchall()
        valid = self._verify_audit_rows(chain)
        more = len(rows) > limit
        rows = rows[:limit]
        entries = [
            {
                'id': r[1],
                'user_id': r[2],
                'action': r[3],
                'entity': r[4],
                'record_uuid': r[5],
                'detail': r[6],
                'created_at': r[7].isoformat(),
                'previous_hash': r[8],
                'entry_hash': r[9],
            }
            for r in rows
        ]
        return {
            'entries': entries,
            'next_cursor': rows[-1][1] if rows else after_id,
            'has_more': more,
            'chain_valid': valid,
        }

    @staticmethod
    def _verify_audit_rows(rows):
        previous_hash = "0" * 64
        for row in rows:
            canonical = {
                'company_id': row[0],
                'user_id': row[2],
                'action': row[3],
                'entity': row[4],
                'record_uuid': row[5],
                'detail': row[6],
                'created_at': row[7].isoformat(),
            }
            encoded = json.dumps(
                canonical,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
                default=str,
            ).encode("utf-8")
            expected = hashlib.sha256(
                bytes.fromhex(previous_hash) + encoded
            ).hexdigest()
            if row[8] != previous_hash or row[9] != expected:
                return False
            previous_hash = row[9]
        return True

    def batch_genealogy(self, company_uuid, identifier, limit=500,
                        mine_uuids=None):
        batches = {}
        movements = {}
        identifiers = {identifier}
        for _ in range(50):
            with self._conn() as c:
                batch_rows = c.execute(
                    """
                    SELECT record_uuid,data FROM sync_records
                    WHERE company_id=%s AND entity='ore_batches'
                      AND (record_uuid=ANY(%s) OR data->>'batch_id'=ANY(%s)
                           OR data->>'parent_batch_id'=ANY(%s))
                    ORDER BY seq DESC LIMIT %s
                    """,
                    (company_uuid, list(identifiers), list(identifiers),
                     list(identifiers), limit),
                ).fetchall()
                movement_rows = c.execute(
                    """
                    SELECT record_uuid,data FROM sync_records
                    WHERE company_id=%s AND entity='batch_movements'
                      AND (record_uuid=ANY(%s) OR data->>'batch_id'=ANY(%s)
                           OR data->>'parent_batch_id'=ANY(%s)
                           OR data->>'child_batch_id'=ANY(%s))
                    ORDER BY seq DESC LIMIT %s
                    """,
                    (company_uuid, list(identifiers), list(identifiers),
                     list(identifiers), list(identifiers), limit),
                ).fetchall()
            discovered = set()
            for record_uuid, data in batch_rows:
                batches[record_uuid] = data
                for key in ('batch_id', 'parent_batch_id'):
                    value = data.get(key)
                    if isinstance(value, str) and value:
                        discovered.add(value)
            for record_uuid, data in movement_rows:
                movements[record_uuid] = data
                for key in ('batch_id', 'parent_batch_id', 'child_batch_id'):
                    value = data.get(key)
                    if isinstance(value, str) and value:
                        discovered.add(value)
            new_identifiers = discovered - identifiers
            if not new_identifiers or len(identifiers) >= limit:
                break
            identifiers.update(new_identifiers)

        with self._conn() as c:
            related = {}
            for entity in (
                'production_records',
                'processing_records',
                'gold_inventory',
                'gold_sale_allocations',
                'sales',
            ):
                rows = c.execute(
                    """
                    SELECT record_uuid,data FROM sync_records
                    WHERE company_id=%s AND entity=%s
                      AND (data->>'batch_id'=ANY(%s)
                           OR data->>'source_batch_id'=ANY(%s))
                    ORDER BY seq LIMIT %s
                    """,
                    (company_uuid, entity, list(identifiers), list(identifiers), limit),
                ).fetchall()
                related[entity] = [
                    {'record_uuid': row[0], 'data': row[1]} for row in rows
                ]

        if mine_uuids is not None:
            mine_names = self.mine_names(company_uuid, mine_uuids)
            mine_names.update(mine_uuids)
            batches = {
                record_uuid: data for record_uuid, data in batches.items()
                if data.get('mine_id') in mine_names
            }
            movements = {
                record_uuid: data for record_uuid, data in movements.items()
                if data.get('mine_id') in mine_names
            }
            related = {
                entity: [
                    record for record in records
                    if record['data'].get('mine_id') in mine_names
                ]
                for entity, records in related.items()
            }
        return {
            'batches': [
                {'record_uuid': record_uuid, 'data': data}
                for record_uuid, data in batches.items()
            ],
            'movements': [
                {'record_uuid': record_uuid, 'data': data}
                for record_uuid, data in movements.items()
            ],
            'related': related,
        }

    def ping(self):
        with self._conn() as c:
            c.execute('SELECT 1').fetchone()

    def token_revoked(self, jti):
        with self._conn() as c:
            r = c.execute('SELECT 1 FROM revoked_tokens WHERE jti=%s', (jti,)).fetchone()
        return bool(r)

    def revoke_token(self, jti, user_id, exp):
        expires = datetime.fromtimestamp(int(exp), timezone.utc)
        with self._conn() as c:
            c.execute("DELETE FROM revoked_tokens WHERE expires_at < now()")
            c.execute('INSERT INTO revoked_tokens(jti,user_id,expires_at) VALUES (%s,%s,%s) '
                      'ON CONFLICT (jti) DO NOTHING', (jti, user_id, expires))

    def rotate_token(self, old_jti, user_id, old_exp):
        with self._conn() as c:
            c.execute("SELECT id FROM users WHERE id=%s FOR UPDATE", (user_id,))
            if c.execute(
                "SELECT 1 FROM revoked_tokens WHERE jti=%s", (old_jti,)
            ).fetchone():
                return False
            c.execute("DELETE FROM revoked_tokens WHERE expires_at < now()")
            c.execute(
                "INSERT INTO revoked_tokens(jti,user_id,expires_at) VALUES (%s,%s,%s)",
                (old_jti, user_id, datetime.fromtimestamp(int(old_exp), timezone.utc)),
            )
        return True

    def _user(self, c, query, value):
        row = c.execute(query, (value,)).fetchone()
        if not row:
            return None
        memberships = c.execute(
            "SELECT company_id::text,role,mine_scope_restricted "
            "FROM memberships WHERE user_id=%s", (row[0],)
        ).fetchall()
        mine_rows = c.execute(
            "SELECT company_id::text,mine_uuid FROM mine_memberships WHERE user_id=%s",
            (row[0],),
        ).fetchall()
        mine_memberships = {
            company_id: set() if restricted else None
            for company_id, _, restricted in memberships
        }
        for company_id, mine_uuid in mine_rows:
            if mine_memberships.get(company_id) is not None:
                mine_memberships.setdefault(company_id, set()).add(mine_uuid)
        return {
            'id': str(row[0]),
            'password_hash': row[1],
            'active': row[2],
            'memberships': {company: role for company, role, _ in memberships},
            'mine_memberships': mine_memberships,
        }

    def get_user_by_name(self, username):
        with self._conn() as c:
            return self._user(
                c,
                "SELECT id,password_hash,active FROM users WHERE username=%s",
                username,
            )

    def get_user_by_id(self, user_id):
        with self._conn() as c:
            return self._user(
                c,
                "SELECT id,password_hash,active FROM users WHERE id=%s",
                user_id,
            )

    def update_password_hash(self, user_id, password_hash):
        with self._conn() as c:
            c.execute(
                "UPDATE users SET password_hash=%s WHERE id=%s",
                (password_hash, user_id),
            )

    def create_company_user(
        self, username, password_hash, company_uuid, role,
        actor_user_id, mine_uuids=None,
    ):
        uid = str(uuid.uuid4())
        with self._conn() as c:
            c.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))",
                      ('madini-company-stream:' + company_uuid,))
            if mine_uuids:
                known = c.execute(
                    """
                    SELECT record_uuid FROM sync_records
                    WHERE company_id=%s AND entity='mines' AND record_uuid=ANY(%s)
                    """,
                    (company_uuid, mine_uuids),
                ).fetchall()
                if {row[0] for row in known} != set(mine_uuids):
                    raise ValueError('mgodi haupo ndani ya kampuni hii')
            c.execute('INSERT INTO users(id,username,password_hash) VALUES (%s,%s,%s)',
                      (uid, username, password_hash))
            c.execute('INSERT INTO memberships(user_id,company_id,role) VALUES (%s,%s,%s)',
                      (uid, company_uuid, role))
            c.execute(
                "UPDATE memberships SET mine_scope_restricted=%s "
                "WHERE user_id=%s AND company_id=%s",
                (mine_uuids is not None, uid, company_uuid),
            )
            for mine_uuid in mine_uuids or []:
                c.execute(
                    "INSERT INTO mine_memberships(user_id,company_id,mine_uuid) "
                    "VALUES (%s,%s,%s)",
                    (uid, company_uuid, mine_uuid),
                )
            _append_audit(
                c, company_uuid, actor_user_id, 'user_created', 'users', uid,
                {'role': role, 'mine_uuids': mine_uuids},
            )
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
            _append_audit(
                c, company_id, user_id, 'company_owner_bootstrapped',
                'companies', company_id, {'company_name': company_name},
            )
        return {'company_uuid': company_id, 'user_id': user_id}
