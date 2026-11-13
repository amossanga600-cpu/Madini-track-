import pathlib, re, sqlite3, sys, unittest
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from fixture import build_v7, seed, uid, ROOT
from test_v8_migration import migrate

V11_COLS = ['incident_category', 'root_cause', 'injury_class', 'injured_name', 'body_part',
            'lost_work_days', 'witnesses', 'equipment_involved', 'ppe_worn', 'work_stopped',
            'reported_to_authority', 'authority_reference', 'corrective_action',
            'corrective_due', 'closed_by', 'closed_at']


def base_incident(**kw):
    d = dict(uuid=uid(), created_at='n', company_id='Kampuni A', mine_id='Mgodi 1',
             incident_type='Ajali', occurred_at='2026-01-01T10:00',
             description='Mwamba ulidondoka', reported_by='amina')
    d.update(kw)
    return d


def insert(db, d):
    db.execute(f"INSERT INTO safety_incidents({','.join(d)}) VALUES({','.join('?' * len(d))})", list(d.values()))


class V11Test(unittest.TestCase):
    def setUp(self):
        self.db = build_v7(); seed(self.db); migrate(self.db)
        self.addCleanup(self.db.close)
        for v in ('v9', 'v10'):
            self.db.executescript((ROOT / f'docs/migrations/{v}_up.sql').read_text())
        self.old = base_incident()
        insert(self.db, self.old)  # rekodi ya zamani (kabla ya v11)
        self.db.executescript((ROOT / 'docs/migrations/v11_up.sql').read_text())

    def test_dart_and_documented_migrations_stay_in_sync(self):
        dart = (ROOT / 'mobile/lib/migration_v11_sql.dart').read_text()
        from_dart = [s.strip() for s in re.findall(r"\'\'\'(.*?)\'\'\'", dart, re.S)]
        sql = re.sub(r'(?m)^--.*\n', '', (ROOT / 'docs/migrations/v11_up.sql').read_text())
        from_sql = [s.strip() for s in sql.split(';') if s.strip()]
        self.assertEqual(from_dart, from_sql)
        self.assertEqual(len(from_sql), len(V11_COLS))

    def test_columns_added_and_old_row_preserved(self):
        cols = {r[1] for r in self.db.execute('PRAGMA table_info(safety_incidents)')}
        self.assertTrue(set(V11_COLS) <= cols)
        row = self.db.execute("SELECT description, lost_work_days, work_stopped, reported_to_authority, injury_class "
                              "FROM safety_incidents WHERE uuid=?", (self.old['uuid'],)).fetchone()
        self.assertEqual(row, ('Mwamba ulidondoka', 0, 0, 0, None))

    def test_constraints_reject_bad_values(self):
        for bad in (dict(incident_category='Haipo'), dict(root_cause='Haipo'), dict(injury_class='Haipo'),
                    dict(lost_work_days=-1), dict(ppe_worn=2), dict(work_stopped=2),
                    dict(reported_to_authority=3)):
            with self.assertRaises(sqlite3.IntegrityError, msg=str(bad)):
                insert(self.db, base_incident(**bad))

    def test_valid_technical_incident_and_update_still_versions_and_queues(self):
        d = base_incident(incident_category='Kuanguka kwa miamba/udongo', root_cause='Hali isiyo salama',
                          injury_class='Siku za kupoteza kazi', lost_work_days=4, ppe_worn=0,
                          reported_to_authority=1, authority_reference='REF-1')
        insert(self.db, d)
        v0 = self.db.execute('SELECT version FROM safety_incidents WHERE uuid=?', (d['uuid'],)).fetchone()[0]
        self.db.execute("UPDATE safety_incidents SET follow_up_status='Inaendelea', corrective_action='Funga eneo' "
                        "WHERE uuid=?", (d['uuid'],))
        v1, st = self.db.execute('SELECT version, sync_status FROM safety_incidents WHERE uuid=?',
                                 (d['uuid'],)).fetchone()
        self.assertEqual((v1, st), (v0 + 1, 'Pending'))
        n = self.db.execute("SELECT COUNT(*) FROM sync_outbox WHERE entity='safety_incidents' AND record_uuid=?",
                            (d['uuid'],)).fetchone()[0]
        self.assertGreaterEqual(n, 1)

    def test_dart_wiring(self):
        dh = (ROOT / 'mobile/lib/database_helper.dart').read_text()
        self.assertIn('const int kDbVersion = 12;', dh)
        self.assertEqual(dh.count('await _migrateToV11(db);'), 2)  # onCreate + onUpgrade
        self.assertIn("import 'migration_v11_sql.dart';", dh)


if __name__ == '__main__':
    unittest.main()
