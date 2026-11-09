"""Fixture ya SYNTHETIC ya schema v7, iliyojengwa kwa kusoma SQL ya
mobile/lib/database_helper.dart. Si database halisi ya mteja; mipaka imeandikwa
kwenye docs/TESTING.md."""
import pathlib, re, sqlite3

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = (ROOT / 'mobile/lib/database_helper.dart').read_text()

COMMON = """uuid TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        device_id TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'Pending'"""

V4 = [
    """CREATE TABLE production_records (id INTEGER PRIMARY KEY AUTOINCREMENT, company_id TEXT NOT NULL,
      mine_id TEXT NOT NULL, shaft_area TEXT NOT NULL, batch_id TEXT NOT NULL, shift_date TEXT NOT NULL,
      shift_type TEXT NOT NULL, bags_count INTEGER NOT NULL, weight_kg REAL NOT NULL, estimated_grade REAL,
      recorded_by TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'Pending', created_at TEXT NOT NULL,
      UNIQUE(company_id, batch_id))""",
    """CREATE TABLE ore_batches (id INTEGER PRIMARY KEY AUTOINCREMENT, company_id TEXT NOT NULL,
      mine_id TEXT NOT NULL, batch_id TEXT NOT NULL, source_location TEXT NOT NULL, current_location TEXT NOT NULL,
      weight_kg REAL NOT NULL, status TEXT NOT NULL DEFAULT 'Imechimbwa', created_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'Pending', UNIQUE(company_id, batch_id))""",
    """CREATE TABLE batch_movements (id INTEGER PRIMARY KEY AUTOINCREMENT, company_id TEXT NOT NULL,
      batch_id TEXT NOT NULL, from_location TEXT NOT NULL, to_location TEXT NOT NULL, weight_kg REAL NOT NULL,
      movement_date TEXT NOT NULL, moved_by TEXT NOT NULL, notes TEXT, sync_status TEXT NOT NULL DEFAULT 'Pending')""",
    """CREATE TABLE processing_records (id INTEGER PRIMARY KEY AUTOINCREMENT, company_id TEXT NOT NULL,
      mine_id TEXT NOT NULL, batch_id TEXT NOT NULL, ore_processed_kg REAL NOT NULL, gold_recovered_g REAL NOT NULL,
      tailings_kg REAL NOT NULL, processing_cost REAL NOT NULL DEFAULT 0, processing_date TEXT NOT NULL,
      processed_by TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'Pending')""",
]

def _v5_creates():
    # Soma `creates` list kutoka Dart (v5) na badilisha $common.
    m = re.search(r"final creates = <String>\[(.*?)\n    \];", SRC, re.S)
    blocks = re.findall(r"'''(CREATE TABLE .*?)'''", m.group(1), re.S)
    return [b.replace('$common', COMMON) for b in blocks]

def _v5_alters():
    m = re.search(r"const alters = \[(.*?)\];", SRC, re.S)
    return re.findall(r"'(ALTER TABLE [^']+)'", m.group(1))

def build_v7(path=':memory:'):
    db = sqlite3.connect(path)
    db.isolation_level = None
    for s in V4:
        db.execute(s)
    for t in ['production_records', 'ore_batches', 'batch_movements', 'processing_records']:
        db.execute(f'ALTER TABLE {t} ADD COLUMN uuid TEXT')
        db.execute(f'CREATE UNIQUE INDEX idx_{t}_uuid ON {t}(uuid)')
    for s in _v5_alters():
        db.execute(s)
    for s in _v5_creates():
        db.execute(s)
    db.execute("CREATE TABLE app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    db.execute("INSERT INTO app_metadata VALUES ('device_id','dev-0001')")
    for ddl in re.findall(r"CREATE TABLE IF NOT EXISTS (gold_inventory|gold_sale_allocations) \(.*?\)'''", SRC, re.S):
        pass
    gold = re.findall(r"'''(CREATE TABLE IF NOT EXISTS gold_(?:inventory|sale_allocations) \(.*?\))'''", SRC, re.S)
    assert len(gold) == 2, gold
    for g in gold:
        db.execute(g)
    sync_tables = ['companies','mines','production_records','ore_batches','batch_movements',
        'processing_records','workers','attendance','payroll_payments','finance_transactions',
        'debts','debt_payments','inventory_items','inventory_movements','sales','audit_log',
        'gold_inventory','gold_sale_allocations']
    adds = {'updated_at': 'TEXT', 'device_id': 'TEXT', 'version': 'INTEGER NOT NULL DEFAULT 1', 'deleted_at': 'TEXT'}
    for t in sync_tables:
        cols = {r[1] for r in db.execute(f'PRAGMA table_info({t})')}
        for k, v in adds.items():
            if k not in cols:
                db.execute(f'ALTER TABLE {t} ADD COLUMN {k} {v}')
    for k, v in {'weight_initial_kg': 'REAL NOT NULL DEFAULT 0', 'parent_batch_uuid': 'TEXT',
                 'source_production_uuid': 'TEXT'}.items():
        db.execute(f'ALTER TABLE ore_batches ADD COLUMN {k} {v}')
    db.execute('ALTER TABLE batch_movements ADD COLUMN child_batch_id TEXT')
    # v7 meta triggers (nakala ya mantiki ya Dart)
    for t in sync_tables:
        has_v = any(r[1] == 'voided' for r in db.execute(f'PRAGMA table_info({t})'))
        d = ("CASE WHEN NEW.voided = 1 THEN COALESCE(NEW.deleted_at, strftime('%Y-%m-%dT%H:%M:%fZ','now')) "
             "ELSE NEW.deleted_at END") if has_v else 'NEW.deleted_at'
        db.execute(f"""CREATE TRIGGER trg_{t}_v7_meta AFTER UPDATE ON {t} FOR EACH ROW BEGIN
          UPDATE {t} SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
            device_id = COALESCE(NULLIF(NEW.device_id,''),'dev-0001'),
            version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1)+1), deleted_at = {d}
          WHERE id = NEW.id; END""")
    db.execute('PRAGMA user_version = 7')
    return db

_n = 0
def uid():
    global _n
    _n += 1
    return f'00000000-0000-4000-8000-{_n:012d}'

def seed(db):
    """Data ya majaribio: kampuni, uzalishaji, batch (hai + iliyobatilishwa), processing,
    gold lot, mauzo, FIFO allocation, wafanyakazi, deni, stoo."""
    now = '2026-01-10T08:00:00'
    ids = {}
    def ins(table, **kw):
        kw.setdefault('uuid', uid())
        if table != 'batch_movements': kw.setdefault('created_at', now)  # v7 haina created_at hapa (bug)
        cols = ','.join(kw); q = ','.join('?' * len(kw))
        db.execute(f'INSERT INTO {table}({cols}) VALUES({q})', list(kw.values()))
        return kw['uuid']
    ids['company'] = ins('companies', name='Kampuni A')
    ids['mine'] = ins('mines', company_id='Kampuni A', name='Mgodi 1')
    C, M = 'Kampuni A', 'Mgodi 1'
    # Batch B-01 hai
    ids['p1'] = ins('production_records', company_id=C, mine_id=M, shaft_area='S1', batch_id='B-01',
        shift_date='2026-01-10', shift_type='Mchana', bags_count=10, weight_kg=100, recorded_by='amina', voided=0)
    ids['b1'] = ins('ore_batches', company_id=C, mine_id=M, batch_id='B-01', source_location='S1',
        current_location='Kiwanda', weight_kg=50, status='Inaendelea kuchakatwa',
        initial_weight_kg=100, weight_initial_kg=100, source_production_uuid=ids['p1'], sync_status='Synced')
    # Batch mtoto (split 30kg)
    ids['b1c'] = ins('ore_batches', company_id=C, mine_id=M, batch_id='B-01-A', source_location='S1',
        current_location='Stoo', weight_kg=30, status='Imehamishwa', initial_weight_kg=30,
        weight_initial_kg=30, parent_batch_id='B-01', parent_batch_uuid=ids['b1'])
    ids['mv'] = ins('batch_movements', company_id=C, batch_id='B-01', from_location='S1', to_location='Stoo',
        weight_kg=30, movement_date=now, moved_by='amina', child_batch_id='B-01-A')
    ids['pr1'] = ins('processing_records', company_id=C, mine_id=M, batch_id='B-01', ore_processed_kg=20,
        gold_recovered_g=40, tailings_kg=19.9, processing_cost=50000, processing_date='2026-01-11',
        processed_by='juma', voided=0, purity_percent=90)
    ids['lot1'] = ins('gold_inventory', company_id=C, mine_id=M, processing_uuid=ids['pr1'], batch_id='B-01',
        grams_initial=40, grams_available=10, purity_percent=90)
    ids['sale1'] = ins('sales', company_id=C, mine_id=M, sale_date='2026-01-12', buyer='Dealer X',
        gold_weight_g=30, purity_percent=90, price_per_g=200000, gross_amount=6000000, net_amount=5500000, voided=0)
    ids['alloc1'] = ins('gold_sale_allocations', sale_uuid=ids['sale1'], lot_uuid=ids['lot1'], grams=30)
    ids['fin_proc'] = ins('finance_transactions', company_id=C, mine_id=M, type='Matumizi', category='Uchakataji',
        amount=50000, trans_date='2026-01-11', source='Uchakataji', source_uuid=ids['pr1'], voided=0)
    # Batch B-02 iliyobatilishwa (void) -> ID itakayotumika tena
    ids['p2'] = ins('production_records', company_id=C, mine_id=M, shaft_area='S2', batch_id='B-02',
        shift_date='2026-01-09', shift_type='Usiku', bags_count=5, weight_kg=60, recorded_by='amina',
        voided=1, void_reason='Kosa la kuingiza')
    ids['b2'] = ins('ore_batches', company_id=C, mine_id=M, batch_id='B-02', source_location='S2',
        current_location='S2', weight_kg=0, status='Imefutwa', initial_weight_kg=60, weight_initial_kg=60,
        source_production_uuid=ids['p2'])
    ids['w1'] = ins('workers', company_id=C, mine_id=M, full_name='Juma', role='Mchimbaji', pay_type='Siku', pay_rate=20000)
    ids['att1'] = ins('attendance', company_id=C, mine_id=M, worker_uuid=ids['w1'], att_date='2026-01-10', status='Yupo')
    ids['d1'] = ins('debts', company_id=C, mine_id=M, direction='Tunadaiwa', party='Supplier', amount=100000, voided=0)
    ids['dp1'] = ins('debt_payments', company_id=C, debt_uuid=ids['d1'], amount=40000, pay_date='2026-01-11')
    ids['item1'] = ins('inventory_items', company_id=C, mine_id=M, name='Dizeli', category='Mafuta', unit='lita')
    ids['im1'] = ins('inventory_movements', company_id=C, mine_id=M, item_uuid=ids['item1'], move_type='Ingia',
        quantity=100, move_date='2026-01-10', voided=0)
    ids['audit1'] = ins('audit_log', company_id=C, entity='production', action='Imerekodiwa')
    return ids
