import pathlib, re, sqlite3, sys, unittest, json
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import fixture
from fixture import build_v7, seed, uid

ROOT = fixture.ROOT
SQL = (ROOT / 'docs/migrations/v8_up.sql').read_text()
MAIN, ARCH = SQL.split('-- @@ ARCHIVE')
STATEMENTS = [s.strip() for s in MAIN.split('-- @@') if s.strip() and not s.strip().startswith('--')]
ARCHIVE = [s.strip() for s in ARCH.split('-- @@') if s.strip()]
ORPHANS = json.loads((ROOT / 'docs/migrations/orphan_checks.json').read_text())
SYNC_TABLES = ['companies','mines','production_records','ore_batches','batch_movements','processing_records',
  'workers','attendance','payroll_payments','finance_transactions','debts','debt_payments','inventory_items',
  'inventory_movements','sales','audit_log','gold_inventory','gold_sale_allocations']

def migrate(db):
    db.execute('BEGIN')
    try:
        for s in STATEMENTS:
            db.execute(s)
        db.execute('COMMIT')
    except Exception:
        db.execute('ROLLBACK'); raise
    db.execute('PRAGMA user_version = 8')

def snapshot(db):
    return {t: {r[0] for r in db.execute(f'SELECT uuid FROM {t}')} for t in SYNC_TABLES}

def fresh(test_case=None):
    db = build_v7(); ids = seed(db)
    if test_case is not None:
        test_case.addCleanup(db.close)
    return db, ids

class DartSyncTest(unittest.TestCase):
    def test_dart_file_matches_sql_file(self):
        dart = (ROOT / 'mobile/lib/migration_v8_sql.dart').read_text()
        blocks = [b.strip() for b in re.findall(r"r'''(.*?)'''", dart, re.S)]
        self.assertEqual(blocks[:len(STATEMENTS)], STATEMENTS)
        self.assertEqual(blocks[len(STATEMENTS):len(STATEMENTS) + len(ARCHIVE)], ARCHIVE)

class MigrationTest(unittest.TestCase):
    def test_fixture_is_v7_and_migrates_without_losing_rows_or_uuids(self):
        db, ids = fresh(self)
        before = snapshot(db)
        counts = {t: db.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0] for t in SYNC_TABLES}
        migrate(db)
        after = snapshot(db)
        self.assertEqual(before, after)
        for t in SYNC_TABLES:
            self.assertEqual(counts[t], db.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0], t)
        self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0], 8)

    def test_numeric_data_unchanged(self):
        db, ids = fresh(self)
        sums = lambda: (db.execute('SELECT SUM(weight_kg) FROM ore_batches').fetchone(),
                        db.execute('SELECT SUM(gold_weight_g), SUM(net_amount) FROM sales').fetchone(),
                        db.execute('SELECT SUM(grams_available) FROM gold_inventory').fetchone())
        b = sums(); migrate(db); self.assertEqual(b, sums())

    def test_migration_is_atomic_on_failure(self):
        db, ids = fresh(self)
        db.execute('BEGIN')
        try:
            for s in STATEMENTS[:40]:
                db.execute(s)
            db.execute('SELECT * FROM tabu_isiyokuwepo')
        except sqlite3.OperationalError:
            db.execute('ROLLBACK')
        cols = [r[1] for r in db.execute('PRAGMA table_info(production_records)')]
        self.assertNotIn('original_batch_id', cols)
        self.assertEqual(db.execute("SELECT COUNT(*) FROM sqlite_master WHERE name='sync_outbox'").fetchone()[0], 0)

    def test_voided_batch_id_archived_with_history(self):
        db, ids = fresh(self)
        migrate(db)
        row = db.execute('SELECT batch_id, original_batch_id, uuid, voided FROM production_records WHERE uuid=?', (ids['p2'],)).fetchone()
        self.assertEqual(row[1], 'B-02'); self.assertTrue(row[0].startswith('B-02~V')); self.assertEqual(row[3], 1)
        brow = db.execute('SELECT batch_id, original_batch_id FROM ore_batches WHERE uuid=?', (ids['b2'],)).fetchone()
        self.assertEqual(brow[0], row[0]); self.assertEqual(brow[1], 'B-02')
        # Batch hai haijaguswa
        self.assertEqual(db.execute('SELECT batch_id, original_batch_id FROM production_records WHERE uuid=?', (ids['p1'],)).fetchone(), ('B-01', None))

    def test_batch_id_can_be_reused_after_archive_and_duplicates_still_blocked(self):
        db, ids = fresh(self); migrate(db)
        db.execute("INSERT INTO production_records(uuid,created_at,company_id,mine_id,shaft_area,batch_id,shift_date,shift_type,bags_count,weight_kg,recorded_by,voided) VALUES(?,?,?,?,?,?,?,?,?,?,?,0)",
                   (uid(), 'now', 'Kampuni A', 'Mgodi 1', 'S2', 'B-02', '2026-01-20', 'Mchana', 3, 30, 'amina'))
        with self.assertRaises(sqlite3.IntegrityError):
            db.execute("INSERT INTO production_records(uuid,created_at,company_id,mine_id,shaft_area,batch_id,shift_date,shift_type,bags_count,weight_kg,recorded_by,voided) VALUES(?,?,?,?,?,?,?,?,?,?,?,0)",
                       (uid(), 'now', 'Kampuni A', 'Mgodi 1', 'S2', 'B-02', '2026-01-21', 'Mchana', 3, 30, 'amina'))
        # rekodi ya zamani bado ipo kwa UUID yake
        self.assertEqual(db.execute('SELECT COUNT(*) FROM production_records WHERE uuid=?', (ids['p2'],)).fetchone()[0], 1)

    def test_runtime_archive_statements_for_new_void(self):
        db, ids = fresh(self); migrate(db)
        # production mpya, kisha void kwa mtiririko wa Dart: voided=1 kisha archive
        pu, bu = uid(), uid()
        db.execute("INSERT INTO production_records(uuid,created_at,company_id,mine_id,shaft_area,batch_id,shift_date,shift_type,bags_count,weight_kg,recorded_by,voided) VALUES(?,?,?,?,?,?,?,?,?,?,?,0)",
                   (pu, 'now', 'Kampuni A', 'Mgodi 1', 'S3', 'B-09', '2026-02-01', 'Mchana', 2, 20, 'amina'))
        db.execute("INSERT INTO ore_batches(uuid,created_at,company_id,mine_id,batch_id,source_location,current_location,weight_kg,status,weight_initial_kg,source_production_uuid) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                   (bu, 'now', 'Kampuni A', 'Mgodi 1', 'B-09', 'S3', 'S3', 20, 'Imechimbwa', 20, pu))
        db.execute('BEGIN')
        db.execute("UPDATE production_records SET voided=1, void_reason='x' WHERE uuid=?", (pu,))
        db.execute("UPDATE ore_batches SET status='Imefutwa', weight_kg=0 WHERE uuid=?", (bu,))
        archived = 'B-09~V' + pu[:8]
        for s in ARCHIVE:
            db.execute(s, [archived, 'Kampuni A', 'B-09'])
        db.execute('COMMIT')
        self.assertEqual(db.execute('SELECT original_batch_id FROM ore_batches WHERE uuid=?', (bu,)).fetchone()[0], 'B-09')
        self.assertEqual(db.execute("SELECT COUNT(*) FROM ore_batches WHERE batch_id='B-09'").fetchone()[0], 0)

class OutboxTest(unittest.TestCase):
    def setUp(self):
        self.db, self.ids = fresh(self); migrate(self.db)
        self.db.execute('PRAGMA foreign_keys = ON')

    def q(self, sql, *a): return self.db.execute(sql, a).fetchall()

    def test_backfill_creates_events_only_for_pending_rows(self):
        pending = sum(self.db.execute(f"SELECT COUNT(*) FROM {t} WHERE sync_status <> 'Synced'").fetchone()[0] for t in SYNC_TABLES)
        events = self.db.execute("SELECT COUNT(*) FROM sync_outbox WHERE sync_status='pending'").fetchone()[0]
        self.assertEqual(pending, events)
        # B-01 ilikuwa 'Synced' kwenye fixture -> haina event
        self.assertEqual(self.q("SELECT COUNT(*) FROM sync_outbox WHERE record_uuid=?", self.ids['b1'])[0][0], 0)

    def test_business_record_and_outbox_event_commit_together(self):
        self.db.execute('BEGIN')
        u = uid()
        self.db.execute("INSERT INTO workers(uuid,created_at,company_id,mine_id,full_name,role,pay_type,pay_rate) VALUES(?,?,?,?,?,?,?,?)",
                        (u, 'now', 'Kampuni A', 'Mgodi 1', 'Neema', 'Opereta', 'Mwezi', 600000))
        self.db.execute('COMMIT')
        ev = self.q("SELECT entity, company_name, op, sync_status, idempotency_key FROM sync_outbox WHERE record_uuid=?", u)
        self.assertEqual(ev, [('workers', 'Kampuni A', 'upsert', 'pending', f'workers:{u}:1')])

    def test_rollback_removes_both_record_and_event(self):
        u = uid()
        self.db.execute('BEGIN')
        self.db.execute("INSERT INTO workers(uuid,created_at,company_id,mine_id,full_name,role,pay_type,pay_rate) VALUES(?,?,?,?,?,?,?,?)",
                        (u, 'now', 'Kampuni A', 'Mgodi 1', 'Neema', 'Opereta', 'Mwezi', 600000))
        self.db.execute('ROLLBACK')
        self.assertEqual(self.q("SELECT COUNT(*) FROM workers WHERE uuid=?", u)[0][0], 0)
        self.assertEqual(self.q("SELECT COUNT(*) FROM sync_outbox WHERE record_uuid=?", u)[0][0], 0)

    def test_failed_business_transaction_leaves_no_orphan_event(self):
        before = self.db.execute('SELECT COUNT(*) FROM sync_outbox').fetchone()[0]
        self.db.execute('BEGIN')
        try:
            self.db.execute("INSERT INTO workers(uuid,created_at,company_id,mine_id,full_name,role,pay_type) VALUES(?,?,?,?,?,?,?)",
                            (uid(), 'now', 'Kampuni A', 'Mgodi 1', 'X', 'Y', 'Siku'))  # pay_type ipo, role ipo -> ok
            self.db.execute("INSERT INTO attendance(uuid,created_at,company_id,mine_id,worker_uuid,att_date,status) VALUES(?,?,?,?,?,?,?)",
                            (uid(), 'now', 'Kampuni A', 'Mgodi 1', 'haipo', '2026-01-01', 'Yupo'))
        except sqlite3.IntegrityError:
            self.db.execute('ROLLBACK')
        self.assertEqual(before, self.db.execute('SELECT COUNT(*) FROM sync_outbox').fetchone()[0])

    def test_updates_coalesce_and_bump_version(self):
        u = self.ids['w1']
        self.db.execute("UPDATE workers SET pay_rate=25000, sync_status='Pending' WHERE uuid=?", (u,))
        self.db.execute("UPDATE workers SET pay_rate=26000, sync_status='Pending' WHERE uuid=?", (u,))
        ev = self.q("SELECT COUNT(*), MAX(record_version) FROM sync_outbox WHERE record_uuid=? AND sync_status='pending'", u)[0]
        self.assertEqual(ev[0], 1)
        ver = self.q("SELECT version FROM workers WHERE uuid=?", u)[0][0]
        self.assertEqual(ev[1], ver)
        self.assertGreaterEqual(ver, 3)

    def test_marking_synced_does_not_bump_version_or_requeue(self):
        u = self.ids['w1']
        ver0 = self.q("SELECT version FROM workers WHERE uuid=?", u)[0][0]
        self.db.execute("UPDATE sync_outbox SET sync_status='synced' WHERE record_uuid=?", (u,))
        n_events = self.db.execute('SELECT COUNT(*) FROM sync_outbox').fetchone()[0]
        self.db.execute("UPDATE workers SET sync_status='Synced' WHERE uuid=? AND version=?", (u, ver0))
        self.assertEqual(self.q("SELECT version, sync_status FROM workers WHERE uuid=?", u)[0], (ver0, 'Synced'))
        self.assertEqual(n_events, self.db.execute('SELECT COUNT(*) FROM sync_outbox').fetchone()[0])

    def test_edit_after_synced_becomes_pending_and_queues_new_event(self):
        u = self.ids['b1']  # Synced kwenye fixture
        self.db.execute("UPDATE ore_batches SET weight_kg = 45 WHERE uuid=?", (u,))  # bila kugusa sync_status
        self.assertEqual(self.q("SELECT sync_status FROM ore_batches WHERE uuid=?", u)[0][0], 'Pending')
        self.assertEqual(self.q("SELECT COUNT(*) FROM sync_outbox WHERE record_uuid=? AND sync_status='pending'", u)[0][0], 1)

    def test_sync_attempts_cascade_and_foreign_keys_enforced(self):
        self.assertEqual(self.db.execute('PRAGMA foreign_keys').fetchone()[0], 1)
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO sync_attempts(outbox_uuid,attempted_at,result) VALUES('haipo','now','x')")
        o = self.q("SELECT uuid FROM sync_outbox LIMIT 1")[0][0]
        self.db.execute("INSERT INTO sync_attempts(outbox_uuid,attempted_at,result) VALUES(?,?,?)", (o, 'now', 'network_error'))
        self.db.execute("DELETE FROM sync_outbox WHERE uuid=?", (o,))
        self.assertEqual(self.q("SELECT COUNT(*) FROM sync_attempts WHERE outbox_uuid=?", o)[0][0], 0)

    def test_only_one_open_event_per_record(self):
        o = self.q("SELECT entity, record_uuid FROM sync_outbox WHERE sync_status='pending' LIMIT 1")[0]
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO sync_outbox(uuid,entity,record_uuid,idempotency_key,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                            (uid(), o[0], o[1], 'k', 'n', 'n'))

class IntegrityTest(unittest.TestCase):
    def setUp(self):
        self.db, self.ids = fresh(self); migrate(self.db)

    def test_orphan_inserts_blocked(self):
        cases = [
            ("attendance(uuid,created_at,company_id,mine_id,worker_uuid,att_date,status)", ('nope',)),
        ]
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO attendance(uuid,created_at,company_id,mine_id,worker_uuid,att_date,status) VALUES(?,?,?,?,?,?,?)", (uid(),'n','C','M','nope','2026-01-01','Yupo'))
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO debt_payments(uuid,created_at,company_id,debt_uuid,amount,pay_date) VALUES(?,?,?,?,?,?)", (uid(),'n','C','nope',1,'2026-01-01'))
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO gold_sale_allocations(uuid,created_at,sale_uuid,lot_uuid,grams) VALUES(?,?,?,?,?)", (uid(),'n',self.ids['sale1'],'nope',1))
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO inventory_movements(uuid,created_at,company_id,mine_id,item_uuid,move_type,quantity,move_date) VALUES(?,?,?,?,?,?,?,?)", (uid(),'n','C','M','nope','Toka',1,'2026-01-01'))

    def test_valid_children_allowed(self):
        self.db.execute("INSERT INTO debt_payments(uuid,created_at,company_id,debt_uuid,amount,pay_date) VALUES(?,?,?,?,?,?)", (uid(),'n','C',self.ids['d1'],5,'2026-01-01'))

    def test_orphan_report_clean_on_valid_data_and_detects_injected_orphan(self):
        for name, sql in ORPHANS.items():
            self.assertEqual(self.db.execute(sql).fetchone()[0], 0, name)
        # orphan ya kihistoria (iliyoingizwa kabla ya triggers) lazima igunduliwe
        self.db.execute("DROP TRIGGER trg_fk_attendance_worker_uuid")
        self.db.execute("INSERT INTO attendance(uuid,created_at,company_id,mine_id,worker_uuid,att_date,status) VALUES(?,?,?,?,?,?,?)", (uid(),'n','C','M','nope','2026-01-02','Yupo'))
        self.assertEqual(self.db.execute(ORPHANS['attendance_worker']).fetchone()[0], 1)

class ConstraintTest(unittest.TestCase):
    def setUp(self):
        self.db, self.ids = fresh(self); migrate(self.db)
    def rate(self, **kw):
        d = dict(uuid=uid(), created_at='n', company_id='Kampuni A', rate_type='mrabaha', percent=1.0,
                 effective_from='2026-01-01', source_reference='REF-TEST')
        d.update(kw)
        self.db.execute(f"INSERT INTO tax_rates({','.join(d)}) VALUES({','.join('?'*len(d))})", list(d.values()))
    def test_no_seeded_rates(self):
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM tax_rates').fetchone()[0], 0)
    def test_rate_requires_source_and_valid_range(self):
        self.rate()
        for bad in [dict(source_reference='  '), dict(percent=101), dict(percent=-1),
                    dict(effective_to='2025-12-31')]:
            with self.assertRaises(sqlite3.IntegrityError, msg=str(bad)):
                self.rate(**bad)
    def test_new_rate_enqueued_for_sync(self):
        self.rate(uuid='r1')
        self.assertEqual(self.db.execute("SELECT entity FROM sync_outbox WHERE record_uuid='r1'").fetchone()[0], 'tax_rates')
    def test_attachment_metadata_constraints(self):
        a = dict(uuid=uid(), created_at='n', company_id='Kampuni A', record_entity='sales', record_uuid=self.ids['sale1'],
                 file_path='/x/a.jpg', mime_type='image/jpeg', file_size=10, checksum_sha256='a'*64, created_by='amina')
        self.db.execute(f"INSERT INTO attachments({','.join(a)}) VALUES({','.join('?'*len(a))})", list(a.values()))
        a.update(uuid=uid(), checksum_sha256='short')
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(f"INSERT INTO attachments({','.join(a)}) VALUES({','.join('?'*len(a))})", list(a.values()))
    def test_safety_incident_validation(self):
        base = dict(uuid=uid(), created_at='n', company_id='Kampuni A', mine_id='Mgodi 1', incident_type='Near miss',
                    occurred_at='2026-01-01T10:00', description='Mwamba ulidondoka', reported_by='amina')
        self.db.execute(f"INSERT INTO safety_incidents({','.join(base)}) VALUES({','.join('?'*len(base))})", list(base.values()))
        base.update(uuid=uid(), incident_type='Nyingine')
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(f"INSERT INTO safety_incidents({','.join(base)}) VALUES({','.join('?'*len(base))})", list(base.values()))

class ReportViewsTest(unittest.TestCase):
    def setUp(self):
        self.db, self.ids = fresh(self); migrate(self.db)
    def test_mass_balance_closes_for_consistent_batch(self):
        r = self.db.execute("SELECT initial_kg, remaining_kg, processed_kg, split_out_kg FROM v_mass_balance WHERE batch_id='B-01'").fetchone()
        # 100 awali = 50 iliyobaki + 20 iliyochakatwa + 30 iliyohamishwa
        self.assertEqual(r, (100, 50, 20, 30))
        self.assertEqual(r[0] - r[1] - r[2] - r[3], 0)
    def test_mass_balance_excludes_voided_batch(self):
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM v_mass_balance WHERE original_batch_id IS NOT NULL").fetchone()[0] if False else
                         self.db.execute("SELECT COUNT(*) FROM v_mass_balance WHERE batch_uuid=?", (self.ids['b2'],)).fetchone()[0], 0)
    def test_batch_cost_includes_processing_expense_without_double_count(self):
        self.db.execute("INSERT INTO finance_transactions(uuid,created_at,company_id,mine_id,type,category,amount,trans_date,batch_uuid,voided) VALUES(?,?,?,?,?,?,?,?,?,0)",
                        (uid(),'n','Kampuni A','Mgodi 1','Matumizi','Mafuta',30000,'2026-01-10',self.ids['b1']))
        r = self.db.execute("SELECT total_cost, txn_count FROM v_batch_costs WHERE batch_uuid=?", (self.ids['b1'],)).fetchone()
        self.assertEqual(r, (80000.0, 2))
    def test_voided_expense_excluded_from_batch_cost(self):
        self.db.execute("UPDATE finance_transactions SET voided=1 WHERE uuid=?", (self.ids['fin_proc'],))
        self.assertIsNone(self.db.execute("SELECT total_cost FROM v_batch_costs WHERE batch_uuid=?", (self.ids['b1'],)).fetchone())

if __name__ == '__main__':
    unittest.main(verbosity=2)
