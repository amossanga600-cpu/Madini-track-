import json, pathlib, sqlite3, sys, unittest
import re
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from fixture import build_v7, seed, uid, ROOT
from test_v8_migration import migrate

Q = json.loads((ROOT / 'docs/migrations/queries.json').read_text())


def fresh(test_case=None):
    db = build_v7(); ids = seed(db); migrate(db)
    if test_case is not None:
        test_case.addCleanup(db.close)
    return db, ids


class PullApplyTest(unittest.TestCase):
    """Data iliyopakuliwa kutoka seva haipaswi kutengeneza events za kutuma tena."""
    def setUp(self):
        self.db, self.ids = fresh(self)
        self.db.execute("DELETE FROM sync_outbox")

    def flag(self, on):
        self.db.execute("INSERT OR REPLACE INTO sync_state(key,value,updated_at) VALUES('applying_pull',?,'n')",
                        ('1' if on else '0',))

    def test_pulled_insert_and_update_create_no_outbox_events_and_keep_version(self):
        self.db.execute('BEGIN'); self.flag(True)
        u = uid()
        self.db.execute("INSERT INTO workers(uuid,created_at,company_id,mine_id,full_name,role,pay_type,version,sync_status,device_id) VALUES(?,?,?,?,?,?,?,?,?,?)",
                        (u, 'n', 'Kampuni A', 'Mgodi 1', 'Neema', 'Opereta', 'Mwezi', 4, 'Synced', 'dev-other'))
        self.db.execute("UPDATE workers SET full_name='Neema M', version=7, sync_status='Synced' WHERE uuid=?", (u,))
        self.flag(False); self.db.execute('COMMIT')
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM sync_outbox").fetchone()[0], 0)
        self.assertEqual(self.db.execute("SELECT version, sync_status, device_id FROM workers WHERE uuid=?", (u,)).fetchone(),
                         (7, 'Synced', 'dev-other'))

    def test_normal_edits_still_queue_after_pull_flag_cleared(self):
        self.db.execute('BEGIN'); self.flag(True); self.flag(False); self.db.execute('COMMIT')
        self.db.execute("UPDATE workers SET pay_rate=1 WHERE uuid=?", (self.ids['w1'],))
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM sync_outbox WHERE record_uuid=?", (self.ids['w1'],)).fetchone()[0], 1)

    def test_flag_rolled_back_with_failed_pull(self):
        self.db.execute('BEGIN'); self.flag(True); self.db.execute('ROLLBACK')
        self.db.execute("UPDATE workers SET pay_rate=2 WHERE uuid=?", (self.ids['w1'],))
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM sync_outbox").fetchone()[0], 1)

    def test_fk_trigger_still_blocks_child_before_parent_during_pull(self):
        self.db.execute('BEGIN'); self.flag(True)
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO attendance(uuid,created_at,company_id,mine_id,worker_uuid,att_date,status) VALUES(?,?,?,?,?,?,?)",
                            (uid(), 'n', 'Kampuni A', 'Mgodi 1', 'bado-haijaja', '2026-01-01', 'Yupo'))
        self.db.execute('ROLLBACK')


class TraceTest(unittest.TestCase):
    def setUp(self):
        self.db, self.ids = fresh(self)

    def q(self, name, *a):
        return self.db.execute(Q['trace'][name], a).fetchall()

    def test_batch_to_sale_chain(self):
        b = self.ids['b1']
        self.assertEqual(len(self.q('batch', b)), 1)
        self.assertEqual(len(self.q('production', b)), 1)
        self.assertEqual([r[0] for r in self.db.execute("SELECT batch_id FROM ore_batches WHERE parent_batch_uuid=?", (b,))], ['B-01-A'])
        self.assertEqual(len(self.q('children', b)), 1)
        self.assertEqual(len(self.q('movements', b)), 1)
        self.assertEqual(len(self.q('processing', b)), 1)
        self.assertEqual(len(self.q('lots', b)), 1)
        sales = self.q('sales', b)
        self.assertEqual(len(sales), 1); self.assertEqual(sales[0][4], 30.0)

    def test_sale_sources_show_origin_batch(self):
        src = self.q('sale_sources', self.ids['sale1'])
        self.assertEqual([(r[0], r[4]) for r in src], [('B-01', 30.0)])

    def test_voided_sale_not_in_batch_trace(self):
        self.db.execute("UPDATE sales SET voided=1 WHERE uuid=?", (self.ids['sale1'],))
        self.assertEqual(self.q('sales', self.ids['b1']), [])

    def test_trace_works_after_batch_id_reuse(self):
        # B-02 imebatilishwa na kuhifadhiwa; ID mpya B-02 haichanganyi historia
        pu, bu = uid(), uid()
        self.db.execute("INSERT INTO production_records(uuid,created_at,company_id,mine_id,shaft_area,batch_id,shift_date,shift_type,bags_count,weight_kg,recorded_by,voided) VALUES(?,?,?,?,?,?,?,?,?,?,?,0)",
                        (pu, 'n', 'Kampuni A', 'Mgodi 1', 'S2', 'B-02', '2026-02-01', 'Mchana', 1, 10, 'a'))
        self.db.execute("INSERT INTO ore_batches(uuid,created_at,company_id,mine_id,batch_id,source_location,current_location,weight_kg,status,weight_initial_kg,source_production_uuid) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                        (bu, 'n', 'Kampuni A', 'Mgodi 1', 'B-02', 'S2', 'S2', 10, 'Imechimbwa', 10, pu))
        self.assertEqual(self.q('production', bu)[0][self._col('production_records', 'uuid')], pu)
        self.assertEqual(self.q('production', self.ids['b2'])[0][self._col('production_records', 'uuid')], self.ids['p2'])

    def _col(self, t, c):
        return [r[1] for r in self.db.execute(f'PRAGMA table_info({t})')].index(c)

    def test_evidence_by_record(self):
        a = dict(uuid=uid(), created_at='n', company_id='Kampuni A', record_entity='sales', record_uuid=self.ids['sale1'],
                 file_path='/x', mime_type='image/jpeg', file_size=1, checksum_sha256='a' * 64, created_by='amina')
        self.db.execute(f"INSERT INTO attachments({','.join(a)}) VALUES({','.join('?' * len(a))})", list(a.values()))
        self.assertEqual(len(self.q('evidence', self.ids['sale1'])), 1)


class DebtsDueTest(unittest.TestCase):
    def setUp(self):
        self.db, self.ids = fresh(self)

    def due(self, until):
        return [r for r in self.db.execute(Q['debts_due'], ('Kampuni A', until))]

    def test_overdue_and_upcoming_debts_listed_with_balance(self):
        self.db.execute("UPDATE debts SET due_date='2026-01-20' WHERE uuid=?", (self.ids['d1'],))
        self.assertEqual(len(self.due('2026-01-25')), 1)
        self.assertEqual(len(self.due('2026-01-10')), 0)

    def test_fully_paid_debt_not_listed(self):
        self.db.execute("UPDATE debts SET due_date='2026-01-20' WHERE uuid=?", (self.ids['d1'],))
        self.db.execute("INSERT INTO debt_payments(uuid,created_at,company_id,debt_uuid,amount,pay_date) VALUES(?,?,?,?,?,?)",
                        (uid(), 'n', 'Kampuni A', self.ids['d1'], 60000, '2026-01-12'))  # 40,000 + 60,000 = 100,000
        self.assertEqual(self.due('2026-02-01'), [])

    def test_voided_and_undated_not_listed(self):
        self.assertEqual(self.due('2099-01-01'), [])  # d1 haina due_date
        self.db.execute("UPDATE debts SET due_date='2026-01-20', voided=1 WHERE uuid=?", (self.ids['d1'],))
        self.assertEqual(self.due('2099-01-01'), [])


class LocalUsersAndApprovalTest(unittest.TestCase):
    def setUp(self):
        self.db, self.ids = fresh(self)

    def user(self, **kw):
        d = dict(uuid=uid(), company_id='Kampuni A', username='amina', full_name='Amina', role='production_supervisor',
                 pin_salt='s', pin_hash='h', pin_iterations=10000, created_at='n')
        d.update(kw)
        self.db.execute(f"INSERT INTO local_users({','.join(d)}) VALUES({','.join('?' * len(d))})", list(d.values()))

    def test_unique_username_per_company_and_valid_role(self):
        self.user()
        with self.assertRaises(sqlite3.IntegrityError): self.user(uuid=uid())
        with self.assertRaises(sqlite3.IntegrityError): self.user(uuid=uid(), username='x', role='mfalme')
        with self.assertRaises(sqlite3.IntegrityError): self.user(uuid=uid(), username='y', pin_iterations=1)
        self.user(uuid=uid(), company_id='Kampuni B')  # kampuni nyingine inaruhusiwa

    def test_local_users_never_enter_sync_outbox(self):
        self.user()
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM sync_outbox WHERE entity='local_users'").fetchone()[0], 0)

    def test_existing_expenses_stay_approved_and_new_columns_exist(self):
        self.assertEqual(self.db.execute("SELECT approval_status FROM finance_transactions WHERE uuid=?", (self.ids['fin_proc'],)).fetchone()[0], 'Imeidhinishwa')
        cols = {r[1] for r in self.db.execute('PRAGMA table_info(production_records)')}
        self.assertTrue({'witness_user_uuid', 'witness_verified'} <= cols)

    def test_approval_change_is_queued_for_sync(self):
        self.db.execute("DELETE FROM sync_outbox")
        self.db.execute("UPDATE finance_transactions SET approval_status='Imekataliwa', approved_by='boss', approved_at='n', sync_status='Pending' WHERE uuid=?", (self.ids['fin_proc'],))
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM sync_outbox WHERE record_uuid=?", (self.ids['fin_proc'],)).fetchone()[0], 1)


class PinMetadataMigrationTest(unittest.TestCase):
    def test_v9_labels_existing_pin_hashes_without_changing_credentials(self):
        db, _ = fresh(self)
        row_uuid = uid()
        db.execute(
            "INSERT INTO local_users(uuid,company_id,username,full_name,role,pin_salt,pin_hash,pin_iterations,created_at) "
            "VALUES(?,?,?,?,?,?,?,?,?)",
            (row_uuid, 'Kampuni A', 'amina', 'Amina', 'company_owner', '0011', 'legacy-hash', 10000, 'n'),
        )
        before = db.execute(
            "SELECT pin_salt,pin_hash,pin_iterations FROM local_users WHERE uuid=?",
            (row_uuid,),
        ).fetchone()

        migration = (ROOT / 'docs/migrations/v9_up.sql').read_text()
        db.executescript(migration)

        after = db.execute(
            "SELECT pin_salt,pin_hash,pin_iterations,pin_algorithm FROM local_users WHERE uuid=?",
            (row_uuid,),
        ).fetchone()
        self.assertEqual(after[:3], before)
        self.assertEqual(after[3], 'pbkdf2-hmac-sha256')
        audit_columns = {row[1] for row in db.execute('PRAGMA table_info(audit_log)')}
        self.assertTrue({'actor_uuid', 'mine_id'} <= audit_columns)


class MassBalanceMigrationTest(unittest.TestCase):
    def test_v10_dart_and_documented_migrations_stay_in_sync(self):
        dart = (ROOT / 'mobile/lib/migration_v10_sql.dart').read_text()
        match = re.search(r"'''(.*?)'''", dart, re.S)
        self.assertIsNotNone(match)
        create_view = match.group(1).strip()
        sql = re.sub(r'(?m)^--.*\n', '', (ROOT / 'docs/migrations/v10_up.sql').read_text())
        statements = [statement.strip() for statement in sql.split(';') if statement.strip()]
        self.assertEqual(statements, ['DROP VIEW v_mass_balance', create_view])

    def test_v10_uses_source_transfer_ledger_for_merged_batches(self):
        db, _ = fresh(self)
        db.executescript((ROOT / 'docs/migrations/v9_up.sql').read_text())
        db.executescript((ROOT / 'docs/migrations/v10_up.sql').read_text())
        mine = 'Mgodi 1'
        sources = [('B-M1', 40.0), ('B-M2', 60.0)]
        for batch_id, weight in sources:
            db.execute(
                "INSERT INTO ore_batches(uuid,created_at,company_id,mine_id,batch_id,source_location,current_location,"
                "weight_kg,status,initial_weight_kg,weight_initial_kg) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                (uid(), 'n', 'Kampuni A', mine, batch_id, 'Pit', 'Pit', 0, 'Imeunganishwa', weight, weight),
            )
        for batch_id, weight in sources:
            db.execute(
                "INSERT INTO batch_movements(uuid,created_at,company_id,batch_id,child_batch_id,from_location,"
                "to_location,weight_kg,movement_date,moved_by,notes) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                (uid(), 'n', 'Kampuni A', batch_id, 'M-MERGED', 'Pit', 'Crusher', weight, 'n', 'amina',
                 'Imeunganishwa kuwa Batch M-MERGED'),
            )
        db.execute(
            "INSERT INTO ore_batches(uuid,created_at,company_id,mine_id,batch_id,source_location,current_location,"
            "weight_kg,status,initial_weight_kg,weight_initial_kg,parent_batch_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
            (uid(), 'n', 'Kampuni A', mine, 'M-MERGED', 'Pit', 'Crusher', 100, 'Imehamishwa', 100, 100, 'B-M1'),
        )

        variances = db.execute(
            "SELECT batch_id, initial_kg - remaining_kg - processed_kg - split_out_kg "
            "FROM v_mass_balance WHERE batch_id IN ('B-M1','B-M2','M-MERGED') ORDER BY batch_id"
        ).fetchall()
        self.assertEqual(len(variances), 3)
        self.assertTrue(all(abs(variance) < 0.000001 for _, variance in variances))


if __name__ == '__main__':
    unittest.main()
