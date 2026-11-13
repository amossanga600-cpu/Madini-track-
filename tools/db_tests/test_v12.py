import pathlib
import re
import sqlite3
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from fixture import ROOT, build_v7, seed, uid
from test_v8_migration import migrate


def versioned_db(test_case):
    db = build_v7()
    ids = seed(db)
    test_case.addCleanup(db.close)
    migrate(db)
    for version in ('v9', 'v10', 'v11'):
        db.executescript((ROOT / f'docs/migrations/{version}_up.sql').read_text())
    return db, ids


class V12TraceabilityTest(unittest.TestCase):
    def setUp(self):
        self.db, self.ids = versioned_db(self)

    def apply_v12(self):
        self.db.executescript((ROOT / 'docs/migrations/v12_up.sql').read_text())

    def test_generated_dart_matches_documented_migration(self):
        dart = (ROOT / 'mobile/lib/migration_v12_sql.dart').read_text()
        from_dart = [
            statement.strip()
            for statement in re.findall(r'r"""(.*?)"""', dart, re.S)
        ]
        from_sql = []
        current = ''
        for line in (ROOT / 'docs/migrations/v12_up.sql').read_text().splitlines():
            if line.lstrip().startswith('--'):
                continue
            current += line + '\n'
            if sqlite3.complete_statement(current):
                statement = current.strip().removesuffix(';').strip()
                if statement:
                    from_sql.append(statement)
                current = ''
        self.assertEqual(from_dart, from_sql)

    def test_backfills_all_existing_lifecycle_links_without_issues(self):
        self.apply_v12()
        expected = {
            'production_records': ('uuid', self.ids['p1']),
            'batch_movements': ('uuid', self.ids['mv']),
            'processing_records': ('uuid', self.ids['pr1']),
            'gold_inventory': ('uuid', self.ids['lot1']),
            'gold_sale_allocations': ('uuid', self.ids['alloc1']),
        }
        for table, (key, record_uuid) in expected.items():
            self.assertIsNotNone(
                self.db.execute(
                    f'SELECT batch_uuid FROM {table} WHERE {key}=?',
                    (record_uuid,),
                ).fetchone()[0],
                table,
            )
        self.assertEqual(
            self.db.execute('SELECT COUNT(*) FROM batch_traceability_issues').fetchone()[0],
            0,
        )

    def test_unmatched_legacy_rows_are_preserved_and_reported(self):
        production_uuid = uid()
        self.db.execute(
            'INSERT INTO production_records(uuid,created_at,company_id,mine_id,shaft_area,batch_id,'
            'shift_date,shift_type,bags_count,weight_kg,recorded_by,voided) '
            'VALUES(?,?,?,?,?,?,?,?,?,?,?,0)',
            (production_uuid, 'n', 'Kampuni A', 'Mgodi 1', 'S9', 'B-LOST',
             '2026-03-01', 'Mchana', 1, 5, 'amina'),
        )
        processing_uuid = uid()
        self.db.execute(
            'INSERT INTO processing_records(uuid,created_at,company_id,mine_id,batch_id,ore_processed_kg,'
            'gold_recovered_g,tailings_kg,processing_date,processed_by,voided) '
            'VALUES(?,?,?,?,?,?,?,?,?,?,0)',
            (processing_uuid, 'n', 'Kampuni A', 'Mgodi 1', 'B-LOST', 5, 1, 4,
             '2026-03-02', 'amina'),
        )
        self.apply_v12()
        issues = self.db.execute(
            'SELECT entity,record_uuid,relation FROM batch_traceability_issues'
        ).fetchall()
        self.assertIn(('production_records', production_uuid, 'batch'), issues)
        self.assertIn(('processing_records', processing_uuid, 'batch'), issues)
        self.assertEqual(
            self.db.execute(
                'SELECT batch_id FROM production_records WHERE uuid=?',
                (production_uuid,),
            ).fetchone()[0],
            'B-LOST',
        )
        self.assertEqual(
            self.db.execute(
                'SELECT batch_id FROM processing_records WHERE uuid=?',
                (processing_uuid,),
            ).fetchone()[0],
            'B-LOST',
        )

    def test_uuid_constraints_reject_invalid_links_and_immutable_identity(self):
        self.apply_v12()
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(
                "UPDATE ore_batches SET uuid=? WHERE uuid=?",
                (uid(), self.ids['b1']),
            )
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(
                "INSERT INTO processing_records(uuid,created_at,company_id,mine_id,batch_id,batch_uuid,"
                "ore_processed_kg,gold_recovered_g,tailings_kg,processing_date,processed_by,voided) "
                "VALUES(?,?,?,?,?,?,?,?,?,?,?,0)",
                (uid(), 'n', 'Kampuni A', 'Mgodi 1', 'B-01', self.ids['b2'],
                 1, 1, 0, '2026-03-03', 'amina'),
            )

    def test_failed_migration_transaction_leaves_schema_unchanged(self):
        statements = [
            'ALTER TABLE production_records ADD COLUMN batch_uuid TEXT',
            'ALTER TABLE batch_movements ADD COLUMN mine_id TEXT',
        ]
        self.db.execute('BEGIN')
        try:
            for statement in statements:
                self.db.execute(statement)
            raise sqlite3.OperationalError('simulated migration interruption')
        except sqlite3.OperationalError:
            self.db.execute('ROLLBACK')
        columns = {
            row[1] for row in self.db.execute('PRAGMA table_info(production_records)')
        }
        self.assertNotIn('batch_uuid', columns)


if __name__ == '__main__':
    unittest.main()
