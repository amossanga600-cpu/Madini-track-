import os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from app.core import MemoryRepo, RateLimiter, SyncEngine, User, has_permission, can_write_entity, validate_jwt_secret

CA, CB = 'company-a', 'company-b'

def ev(uuid='r1', version=1, company=CA, entity='workers', key=None, data=None):
    return {'idempotency_key': key or f'{entity}:{uuid}:{version}', 'entity': entity, 'record_uuid': uuid,
            'company_uuid': company, 'version': version, 'data': data if data is not None else {'uuid': uuid, 'v': version}}

class T(unittest.TestCase):
    def setUp(self):
        self.repo = MemoryRepo(); self.e = SyncEngine(self.repo)
        self.owner_a = User('u1', {CA: 'company_owner'})
        self.owner_b = User('u2', {CB: 'company_owner'})

    def test_applied_then_duplicate_no_double_write(self):
        r = self.e.push(self.owner_a, 'd1', [ev()])[0]
        self.assertEqual(r['status'], 'applied')
        r2 = self.e.push(self.owner_a, 'd1', [ev()])[0]
        self.assertEqual(r2['status'], 'duplicate')
        self.assertEqual(len(self.repo.records), 1)

    def test_tenant_isolation(self):
        r = self.e.push(self.owner_b, 'd2', [ev(company=CA)])[0]
        self.assertEqual(r['status'], 'rejected'); self.assertEqual(self.repo.records, {})

    def test_readonly_and_auditor_cannot_write(self):
        for role in ('read_only', 'auditor'):
            r = self.e.push(User('x', {CA: role}), 'd', [ev()])[0]
            self.assertEqual(r['status'], 'rejected')
        self.assertFalse(has_permission('read_only', 'sync:write'))

    def test_same_device_newer_version_updates(self):
        self.e.push(self.owner_a, 'd1', [ev(version=1)])
        r = self.e.push(self.owner_a, 'd1', [ev(version=3)])[0]
        self.assertEqual(r['status'], 'applied')
        self.assertEqual(self.repo.records[(CA, 'workers', 'r1')]['version'], 3)

    def test_other_device_overwrite_is_conflict_not_silent(self):
        self.e.push(self.owner_a, 'd1', [ev(version=2, data={'uuid': 'r1', 'pay': 1})])
        r = self.e.push(self.owner_a, 'd2', [ev(version=5, data={'uuid': 'r1', 'pay': 99})])[0]
        self.assertEqual(r['status'], 'conflict')
        self.assertEqual(self.repo.records[(CA, 'workers', 'r1')]['data']['pay'], 1)
        self.assertEqual(len(self.repo.conflicts), 1)

    def test_validation(self):
        bad = [ev(entity='users'), ev(version=0), ev(data={'uuid': 'other'}), {'entity': 'workers'}]
        for b in bad:
            self.assertEqual(self.e.push(self.owner_a, 'd', [b])[0]['status'], 'rejected')
        with self.assertRaises(ValueError):
            self.e.push(self.owner_a, '', [ev()])

    def test_entity_level_permissions(self):
        self.assertTrue(can_write_entity('storekeeper', 'inventory_movements'))
        self.assertFalse(can_write_entity('storekeeper', 'payroll_payments'))
        self.assertFalse(can_write_entity('production_supervisor', 'sales'))
        self.assertTrue(can_write_entity('accountant', 'sales'))

    def test_rejects_cross_tenant_payload_and_oversized_data(self):
        cross = ev(data={'uuid': 'r1', 'company_id': CB})
        self.assertEqual(self.e.push(self.owner_a, 'd1', [cross])[0]['status'], 'rejected')
        huge = ev(data={'uuid': 'r1', 'blob': 'x' * 270000})
        self.assertEqual(self.e.push(self.owner_a, 'd1', [huge])[0]['status'], 'rejected')

    def test_pull_requires_membership_and_read_permission(self):
        with self.assertRaises(PermissionError):
            self.e.pull(User('x', {CB: 'company_owner'}), CA)
        self.assertEqual(self.e.pull(User('x', {CA: 'read_only'}), CA)['records'], [])

    def test_rate_limiter(self):
        t = [0.0]; rl = RateLimiter(3, 60, clock=lambda: t[0])
        self.assertTrue(all(rl.allow('k') for _ in range(3))); self.assertFalse(rl.allow('k'))
        t[0] = 61; self.assertTrue(rl.allow('k'))

    def test_jwt_secret_must_contain_at_least_32_utf8_bytes(self):
        with self.assertRaises(RuntimeError):
            validate_jwt_secret('too-short')
        self.assertEqual(validate_jwt_secret('a' * 32), 'a' * 32)

class V10Tests(unittest.TestCase):
    def setUp(self):
        self.repo = MemoryRepo({CA: 'Kampuni A'}); self.e = SyncEngine(self.repo)
        self.u = User('u1', {CA: 'company_owner'}, 'd1')

    def app_event(self, uuid='w1', version=1, entity='workers', **data):
        d = {'uuid': uuid, 'company_id': 'Kampuni A', 'full_name': 'Juma'}; d.update(data)
        return ev(uuid=uuid, version=version, entity=entity, data=d)

    def test_app_style_event_with_company_name_is_accepted(self):
        self.assertEqual(self.e.push(self.u, 'd1', [self.app_event()])[0]['status'], 'applied')

    def test_other_company_name_in_payload_rejected(self):
        r = self.e.push(self.u, 'd1', [self.app_event(company_id='Kampuni B')])[0]
        self.assertEqual(r['status'], 'rejected'); self.assertEqual(self.repo.records, {})

    def test_company_record_must_match_its_own_tenant(self):
        bad = ev(uuid='other-company', entity='companies', data={'uuid': 'other-company', 'name': 'X'})
        self.assertEqual(self.e.push(self.u, 'd1', [bad])[0]['status'], 'rejected')
        good = ev(uuid=CA, entity='companies', data={'uuid': CA, 'name': 'Kampuni A'})
        self.assertEqual(self.e.push(self.u, 'd1', [good])[0]['status'], 'applied')

    def test_pull_returns_updated_records_again(self):
        self.e.push(self.u, 'd1', [self.app_event(version=1)])
        first = self.e.pull(self.u, CA, 0)
        cur = first['next_cursor']
        self.assertEqual(len(first['records']), 1)
        self.assertEqual(self.e.pull(self.u, CA, cur)['records'], [])
        self.e.push(self.u, 'd1', [self.app_event(version=2, full_name='Juma M')])  # hariri
        again = self.e.pull(self.u, CA, cur)
        self.assertEqual([r['version'] for r in again['records']], [2])
        self.assertGreater(again['next_cursor'], cur)

    def test_pull_is_tenant_scoped_and_paginated(self):
        for i in range(5):
            self.e.push(self.u, 'd1', [self.app_event(uuid=f'w{i}')])
        other = User('u2', {CB: 'company_owner'}, 'd2')
        with self.assertRaises(PermissionError):
            self.e.pull(other, CA, 0)
        page = self.e.pull(self.u, CA, 0, limit=2)
        self.assertEqual((len(page['records']), page['has_more']), (2, True))
        rest = self.e.pull(self.u, CA, page['next_cursor'], limit=10)
        self.assertEqual((len(rest['records']), rest['has_more']), (3, False))


if __name__ == '__main__':
    unittest.main()
