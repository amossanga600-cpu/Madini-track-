#!/usr/bin/env python3
"""Huzalisha migration v8 kutoka chanzo kimoja.

Matokeo:
  docs/migrations/v8_up.sql            (statements zimetenganishwa na '-- @@')
  mobile/lib/migration_v8_sql.dart     (const kV8Statements ... kArchiveBatchStatements)
Majaribio ya Python (backend/../tests_db) huendesha SQL hii hii.
"""
import pathlib, sys, json

ROOT = pathlib.Path(__file__).resolve().parents[1]
NOW = "strftime('%Y-%m-%dT%H:%M:%fZ','now')"

SYNC_TABLES = [
    'companies', 'mines', 'production_records', 'ore_batches', 'batch_movements',
    'processing_records', 'workers', 'attendance', 'payroll_payments',
    'finance_transactions', 'debts', 'debt_payments', 'inventory_items',
    'inventory_movements', 'sales', 'audit_log', 'gold_inventory',
    'gold_sale_allocations',
    # mpya v8
    'attachments', 'tax_rates', 'safety_incidents',
]
HAS_VOIDED = {'production_records', 'processing_records', 'payroll_payments',
              'finance_transactions', 'debts', 'inventory_movements', 'sales',
              'safety_incidents'}

COMMON = """uuid TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  device_id TEXT,
  version INTEGER NOT NULL DEFAULT 1,
  deleted_at TEXT,
  sync_status TEXT NOT NULL DEFAULT 'Pending'"""


def company_expr(t, prefix):
    if t == 'companies':
        return f"{prefix}.name"
    if t == 'gold_sale_allocations':  # haina company_id; chukua kutoka kwenye mauzo
        return f"(SELECT s.company_id FROM sales s WHERE s.uuid = {prefix}.sale_uuid)"
    return f"{prefix}.company_id"


S = []  # statements

# ---- 1. Safu mpya kwenye majedwali yaliyopo (additive) -----------------------
for t in ['production_records', 'ore_batches', 'processing_records', 'gold_inventory']:
    S.append(f"ALTER TABLE {t} ADD COLUMN original_batch_id TEXT")
S.append("ALTER TABLE finance_transactions ADD COLUMN batch_uuid TEXT")
# BUG ya v7: batch_movements haikuwa na created_at ingawa meta() inaiingiza kwenye kila uhamisho.
S.append("ALTER TABLE finance_transactions ADD COLUMN approval_status TEXT NOT NULL DEFAULT 'Imeidhinishwa'")
S.append("ALTER TABLE finance_transactions ADD COLUMN approved_by TEXT")
S.append("ALTER TABLE finance_transactions ADD COLUMN approved_at TEXT")
S.append("ALTER TABLE production_records ADD COLUMN witness_user_uuid TEXT")
S.append("ALTER TABLE production_records ADD COLUMN witness_verified INTEGER NOT NULL DEFAULT 0")
S.append("ALTER TABLE batch_movements ADD COLUMN created_at TEXT")
S.append("UPDATE batch_movements SET created_at = movement_date WHERE created_at IS NULL")

# ---- 2. Hifadhi Batch ID za zamani zilizobatilishwa (hazipotei; zinahamishiwa
#         kwenye original_batch_id ili ID iweze kutumika tena). UUID hazibadiliki.
VOIDED_SUFFIX = ("'~V' || (SELECT substr(p.uuid,1,8) FROM production_records p "
                 "WHERE p.company_id = {t}.company_id AND p.batch_id = {t}.batch_id AND p.voided = 1)")
COND = ("EXISTS (SELECT 1 FROM production_records p WHERE p.company_id = {t}.company_id "
        "AND p.batch_id = {t}.batch_id AND p.voided = 1)")
for t in ['ore_batches', 'processing_records', 'gold_inventory']:
    S.append(
        f"UPDATE {t} SET original_batch_id = batch_id, batch_id = batch_id || "
        + VOIDED_SUFFIX.format(t=t) + f" WHERE original_batch_id IS NULL AND "
        + COND.format(t=t)
    )
S.append("UPDATE production_records SET original_batch_id = batch_id, "
         "batch_id = batch_id || '~V' || substr(uuid,1,8) WHERE voided = 1 AND original_batch_id IS NULL")

# ---- 3. Majedwali mapya --------------------------------------------------------
S.append(f"""CREATE TABLE sync_outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  entity TEXT NOT NULL,
  record_uuid TEXT NOT NULL,
  company_name TEXT,
  op TEXT NOT NULL DEFAULT 'upsert' CHECK (op IN ('upsert')),
  record_version INTEGER NOT NULL DEFAULT 1,
  idempotency_key TEXT NOT NULL,
  sync_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (sync_status IN ('pending','sending','failed','synced','conflict','rejected')),
  retry_count INTEGER NOT NULL DEFAULT 0,
  next_retry_at TEXT,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)""")
S.append("CREATE UNIQUE INDEX uq_outbox_open ON sync_outbox(entity, record_uuid) "
         "WHERE sync_status IN ('pending','failed')")
S.append("CREATE INDEX idx_outbox_due ON sync_outbox(sync_status, next_retry_at)")
S.append("""CREATE TABLE sync_attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  outbox_uuid TEXT NOT NULL REFERENCES sync_outbox(uuid) ON DELETE CASCADE,
  attempted_at TEXT NOT NULL,
  http_status INTEGER,
  result TEXT NOT NULL,
  error TEXT
)""")
S.append("CREATE INDEX idx_attempts_outbox ON sync_attempts(outbox_uuid)")
S.append("""CREATE TABLE local_users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  company_id TEXT NOT NULL,
  username TEXT NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('company_owner','company_admin','mine_manager','production_supervisor',
    'processing_operator','storekeeper','accountant','auditor','read_only')),
  pin_salt TEXT NOT NULL,
  pin_hash TEXT NOT NULL,
  pin_iterations INTEGER NOT NULL CHECK (pin_iterations >= 1000),
  active INTEGER NOT NULL DEFAULT 1,
  failed_attempts INTEGER NOT NULL DEFAULT 0,
  locked_until TEXT,
  created_at TEXT NOT NULL,
  UNIQUE (company_id, username)
)""")
S.append("""CREATE TABLE sync_state (
  key TEXT PRIMARY KEY,
  value TEXT,
  updated_at TEXT NOT NULL
)""")

S.append(f"""CREATE TABLE attachments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  company_id TEXT NOT NULL,
  mine_id TEXT,
  record_entity TEXT NOT NULL,
  record_uuid TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'Picha',
  file_path TEXT NOT NULL,
  storage_key TEXT,
  mime_type TEXT NOT NULL,
  file_size INTEGER NOT NULL CHECK (file_size >= 0),
  checksum_sha256 TEXT NOT NULL CHECK (length(checksum_sha256) = 64),
  upload_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (upload_status IN ('pending','uploaded','failed')),
  created_by TEXT NOT NULL,
  {COMMON}
)""")
S.append("CREATE INDEX idx_attachments_record ON attachments(record_entity, record_uuid)")
S.append("CREATE INDEX idx_attachments_upload ON attachments(upload_status)")

S.append(f"""CREATE TABLE tax_rates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  company_id TEXT NOT NULL,
  rate_type TEXT NOT NULL,
  mineral TEXT NOT NULL DEFAULT 'Dhahabu',
  percent REAL NOT NULL CHECK (percent >= 0 AND percent <= 100),
  effective_from TEXT NOT NULL,
  effective_to TEXT,
  source_reference TEXT NOT NULL CHECK (length(trim(source_reference)) > 0),
  source_url TEXT,
  verified_by TEXT,
  verified_at TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','verified','retired')),
  {COMMON},
  CHECK (effective_to IS NULL OR effective_to >= effective_from)
)""")
S.append("CREATE INDEX idx_tax_rates_lookup ON tax_rates(company_id, rate_type, status, effective_from)")

S.append(f"""CREATE TABLE safety_incidents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  company_id TEXT NOT NULL,
  mine_id TEXT NOT NULL,
  incident_type TEXT NOT NULL
    CHECK (incident_type IN ('Ajali','Tukio hatarishi','Near miss','Ukaguzi wa usalama','PPE')),
  severity TEXT NOT NULL DEFAULT 'Ndogo' CHECK (severity IN ('Ndogo','Wastani','Kubwa','Kifo')),
  occurred_at TEXT NOT NULL,
  location TEXT,
  description TEXT NOT NULL,
  injured_count INTEGER NOT NULL DEFAULT 0 CHECK (injured_count >= 0),
  action_taken TEXT,
  responsible_officer TEXT,
  follow_up_status TEXT NOT NULL DEFAULT 'Wazi' CHECK (follow_up_status IN ('Wazi','Inaendelea','Imefungwa')),
  follow_up_date TEXT,
  reported_by TEXT NOT NULL,
  voided INTEGER NOT NULL DEFAULT 0,
  void_reason TEXT,
  {COMMON}
)""")
S.append("CREATE INDEX idx_safety_scope ON safety_incidents(company_id, mine_id, occurred_at)")
S.append("CREATE INDEX idx_fin_batch ON finance_transactions(batch_uuid)")

# ---- 4. Triggers za uadilifu (FK zinazolindwa bila kujenga upya majedwali) -----
FKS = [
    ('attendance', 'worker_uuid', 'workers'),
    ('payroll_payments', 'worker_uuid', 'workers'),
    ('debt_payments', 'debt_uuid', 'debts'),
    ('inventory_movements', 'item_uuid', 'inventory_items'),
    ('gold_sale_allocations', 'sale_uuid', 'sales'),
    ('gold_sale_allocations', 'lot_uuid', 'gold_inventory'),
    ('gold_inventory', 'processing_uuid', 'processing_records'),
]
for child, col, parent in FKS:
    S.append(f"""CREATE TRIGGER trg_fk_{child}_{col} BEFORE INSERT ON {child}
FOR EACH ROW WHEN NOT EXISTS (SELECT 1 FROM {parent} WHERE uuid = NEW.{col})
BEGIN
  SELECT RAISE(ABORT, 'FK: {child}.{col} -> {parent}.uuid haipo');
END""")

# ---- 5. Meta triggers (v8) zinazobadilisha za v7 ------------------------------
DEV = "(SELECT value FROM app_metadata WHERE key = 'device_id')"
PULL_FLAG = "COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'"
SKIP_SYNCED = ("NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND " + PULL_FLAG)
for t in SYNC_TABLES:
    S.append(f"DROP TRIGGER IF EXISTS trg_{t}_v7_meta")
    if t in HAS_VOIDED:
        deleted = f"CASE WHEN NEW.voided = 1 THEN COALESCE(NEW.deleted_at, {NOW}) ELSE NEW.deleted_at END"
    else:
        deleted = "NEW.deleted_at"
    S.append(f"""CREATE TRIGGER trg_{t}_v8_meta AFTER UPDATE ON {t}
FOR EACH ROW WHEN {SKIP_SYNCED}
BEGIN
  UPDATE {t} SET updated_at = {NOW},
    device_id = COALESCE(NULLIF(NEW.device_id,''), {DEV}),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = {deleted},
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END""")

# ---- 6. Transactional Outbox triggers -----------------------------------------
def ob_body(t):
    c = company_expr(t, 'NEW')
    return f"""  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = '{t}:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = {NOW}
  WHERE entity = '{t}' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), '{t}', NEW.uuid, {c}, 'upsert', NEW.version,
      '{t}:' || NEW.uuid || ':' || NEW.version, 'pending', {NOW}, {NOW}
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = '{t}' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));"""

for t in SYNC_TABLES:
    S.append(f"""CREATE TRIGGER trg_{t}_v8_ob_ins AFTER INSERT ON {t}
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND {PULL_FLAG}
BEGIN
{ob_body(t)}
END""")
    S.append(f"""CREATE TRIGGER trg_{t}_v8_ob_upd AFTER UPDATE ON {t}
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND {SKIP_SYNCED}
BEGIN
{ob_body(t)}
END""")

# ---- 7. Backfill: rekodi za v7 ambazo bado 'Pending' zinaingia kwenye outbox ----
for t in SYNC_TABLES:
    if t in ('attachments', 'tax_rates', 'safety_incidents'):
        continue
    c = company_expr(t, 'r')
    S.append(f"""INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), '{t}', r.uuid, {c}, 'upsert', COALESCE(r.version,1),
    '{t}:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', {NOW}, {NOW}
FROM {t} r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = '{t}'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))""")

# ---- 8. Views za ripoti --------------------------------------------------------
S.append("""CREATE VIEW v_mass_balance AS
SELECT b.uuid AS batch_uuid, b.company_id, b.mine_id, b.batch_id,
  COALESCE(NULLIF(b.weight_initial_kg,0), b.initial_weight_kg, b.weight_kg) AS initial_kg,
  b.weight_kg AS remaining_kg,
  IFNULL((SELECT SUM(p.ore_processed_kg) FROM processing_records p
          WHERE p.company_id = b.company_id AND p.batch_id = b.batch_id AND p.voided = 0), 0) AS processed_kg,
  IFNULL((SELECT SUM(p.tailings_kg) FROM processing_records p
          WHERE p.company_id = b.company_id AND p.batch_id = b.batch_id AND p.voided = 0), 0) AS tailings_kg,
  IFNULL((SELECT SUM(p.gold_recovered_g) FROM processing_records p
          WHERE p.company_id = b.company_id AND p.batch_id = b.batch_id AND p.voided = 0), 0) AS gold_g,
  IFNULL((SELECT SUM(c.weight_initial_kg) FROM ore_batches c
          WHERE c.company_id = b.company_id AND c.parent_batch_id = b.batch_id
            AND c.status <> 'Imefutwa'), 0) AS split_out_kg
FROM ore_batches b WHERE b.status <> 'Imefutwa'""")
S.append("""CREATE VIEW v_batch_costs AS
SELECT b.uuid AS batch_uuid, b.company_id, b.mine_id, b.batch_id,
  SUM(c.amount) AS total_cost, COUNT(*) AS txn_count
FROM ore_batches b JOIN (
  SELECT f.uuid AS fuuid, f.amount AS amount, f.batch_uuid AS buuid,
         NULL AS pbatch, NULL AS pcompany
  FROM finance_transactions f
  WHERE f.type = 'Matumizi' AND f.voided = 0 AND f.batch_uuid IS NOT NULL
  UNION ALL
  SELECT f.uuid, f.amount, NULL, p.batch_id, p.company_id
  FROM finance_transactions f JOIN processing_records p ON p.uuid = f.source_uuid
  WHERE f.source = 'Uchakataji' AND f.type = 'Matumizi' AND f.voided = 0 AND f.batch_uuid IS NULL
) c ON (c.buuid = b.uuid) OR (c.pbatch = b.batch_id AND c.pcompany = b.company_id)
WHERE b.status <> 'Imefutwa'
GROUP BY b.uuid""")

# ---- Statements za runtime (void production -> hifadhi Batch ID) ---------------
ARCHIVE = [
    "UPDATE processing_records SET original_batch_id = batch_id, batch_id = ? WHERE company_id = ? AND batch_id = ? AND voided = 1",
    "UPDATE gold_inventory SET original_batch_id = batch_id, batch_id = ? WHERE company_id = ? AND batch_id = ?",
    "UPDATE ore_batches SET original_batch_id = batch_id, batch_id = ? WHERE company_id = ? AND batch_id = ?",
    "UPDATE production_records SET original_batch_id = batch_id, batch_id = ? WHERE company_id = ? AND batch_id = ?",
]

TRACE = {
  'batch': "SELECT * FROM ore_batches WHERE uuid = ?",
  'production': "SELECT * FROM production_records WHERE batch_uuid = ?",
  'children': "SELECT * FROM ore_batches WHERE parent_batch_uuid = ? ORDER BY id",
  'merged_sources': "SELECT b.*, m.weight_kg AS merged_weight_kg FROM batch_movements m JOIN ore_batches target ON target.uuid = m.child_batch_uuid JOIN ore_batches b ON b.uuid = m.batch_uuid WHERE target.uuid = ? AND b.status = 'Imeunganishwa' ORDER BY m.id",
  'movements': "SELECT m.* FROM batch_movements m WHERE m.batch_uuid = ? OR m.parent_batch_uuid = ? OR m.child_batch_uuid = ? ORDER BY m.id",
  'processing': "SELECT p.* FROM processing_records p WHERE p.batch_uuid = ? AND p.voided = 0 ORDER BY p.id",
  'lots': "SELECT g.* FROM gold_inventory g JOIN processing_records p ON p.uuid = g.processing_uuid WHERE g.batch_uuid = ? AND p.voided = 0 ORDER BY g.id",
  'sales': "SELECT s.uuid AS sale_uuid, s.sale_date, s.buyer, s.reference, a.grams, a.lot_uuid FROM gold_sale_allocations a JOIN sales s ON s.uuid = a.sale_uuid WHERE a.batch_uuid = ? AND s.voided = 0 ORDER BY s.sale_date, s.id",
  'sale_sources': "SELECT b.batch_id AS batch_id, b.uuid AS batch_uuid, p.uuid AS processing_uuid, g.uuid AS lot_uuid, a.grams AS grams FROM gold_sale_allocations a JOIN sales s ON s.uuid = a.sale_uuid JOIN gold_inventory g ON g.uuid = a.lot_uuid AND g.company_id = s.company_id AND g.mine_id = s.mine_id JOIN processing_records p ON p.uuid = g.processing_uuid AND p.company_id = s.company_id AND p.mine_id = s.mine_id JOIN ore_batches b ON b.uuid = a.batch_uuid AND b.company_id = s.company_id AND b.mine_id = s.mine_id WHERE a.sale_uuid = ? AND s.company_id = ? AND s.mine_id = ? ORDER BY a.id",
  'evidence': "SELECT * FROM attachments WHERE record_uuid = ? AND deleted_at IS NULL ORDER BY id",
}
DEBTS_DUE = ("SELECT d.*, IFNULL((SELECT SUM(p.amount) FROM debt_payments p WHERE p.debt_uuid = d.uuid), 0) AS paid "
  "FROM debts d WHERE d.company_id = ? AND d.voided = 0 AND d.due_date IS NOT NULL AND d.due_date <> '' "
  "AND d.due_date <= ? AND d.amount - IFNULL((SELECT SUM(p.amount) FROM debt_payments p WHERE p.debt_uuid = d.uuid), 0) > 0.005 "
  "ORDER BY d.due_date")

ORPHANS = [
    ("attendance_worker", "SELECT COUNT(*) FROM attendance a WHERE NOT EXISTS (SELECT 1 FROM workers w WHERE w.uuid = a.worker_uuid)"),
    ("payroll_worker", "SELECT COUNT(*) FROM payroll_payments a WHERE NOT EXISTS (SELECT 1 FROM workers w WHERE w.uuid = a.worker_uuid)"),
    ("debt_payment_debt", "SELECT COUNT(*) FROM debt_payments a WHERE NOT EXISTS (SELECT 1 FROM debts d WHERE d.uuid = a.debt_uuid)"),
    ("stock_move_item", "SELECT COUNT(*) FROM inventory_movements a WHERE NOT EXISTS (SELECT 1 FROM inventory_items i WHERE i.uuid = a.item_uuid)"),
    ("allocation_sale", "SELECT COUNT(*) FROM gold_sale_allocations a WHERE NOT EXISTS (SELECT 1 FROM sales s WHERE s.uuid = a.sale_uuid)"),
    ("allocation_lot", "SELECT COUNT(*) FROM gold_sale_allocations a WHERE NOT EXISTS (SELECT 1 FROM gold_inventory g WHERE g.uuid = a.lot_uuid)"),
    ("lot_processing", "SELECT COUNT(*) FROM gold_inventory a WHERE NOT EXISTS (SELECT 1 FROM processing_records p WHERE p.uuid = a.processing_uuid)"),
    ("batch_without_production", "SELECT COUNT(*) FROM ore_batches b WHERE b.parent_batch_uuid IS NULL AND b.source_production_uuid IS NULL AND NOT EXISTS (SELECT 1 FROM batch_movements m WHERE m.child_batch_uuid = b.uuid)"),
    ("movement_without_batch", "SELECT COUNT(*) FROM batch_movements m WHERE m.batch_uuid IS NULL OR NOT EXISTS (SELECT 1 FROM ore_batches b WHERE b.company_id = m.company_id AND b.uuid = m.batch_uuid)"),
    ("processing_without_batch", "SELECT COUNT(*) FROM processing_records p WHERE p.batch_uuid IS NULL OR NOT EXISTS (SELECT 1 FROM ore_batches b WHERE b.company_id = p.company_id AND b.uuid = p.batch_uuid)"),
    ("production_without_batch", "SELECT COUNT(*) FROM production_records p WHERE p.batch_uuid IS NULL OR NOT EXISTS (SELECT 1 FROM ore_batches b WHERE b.company_id = p.company_id AND b.uuid = p.batch_uuid)"),
    ("gold_without_batch", "SELECT COUNT(*) FROM gold_inventory g WHERE g.batch_uuid IS NULL OR NOT EXISTS (SELECT 1 FROM ore_batches b WHERE b.company_id = g.company_id AND b.uuid = g.batch_uuid)"),
    ("allocation_without_batch", "SELECT COUNT(*) FROM gold_sale_allocations a WHERE a.batch_uuid IS NULL OR NOT EXISTS (SELECT 1 FROM ore_batches b WHERE b.uuid = a.batch_uuid)"),
]

SEP = "\n-- @@\n"
(ROOT / 'docs/migrations/v8_up.sql').write_text(
    "-- Madini Track schema v7 -> v8 (imezalishwa na tools/gen_v8.py; usihariri kwa mkono)\n-- @@\n"
    + SEP.join(S) + "\n-- @@ ARCHIVE\n" + SEP.join(ARCHIVE) + "\n")

def dart_list(name, items):
    body = ",\n".join("  r'''" + s + "\n'''" for s in items)
    return f"const List<String> {name} = [\n{body},\n];\n"


def dart_map_entry(name, value):
    entry = f"  '{name}': r'''{value}'''"
    if len(entry) <= 80:
        return entry
    return f"  '{name}':\n      r'''{value}'''"


(ROOT / 'mobile/lib/migration_v8_sql.dart').write_text(
    "// IMEZALISHWA na tools/gen_v8.py kutoka docs/migrations/v8_up.sql. Usihariri.\n"
    "\n"
    + dart_list('kV8Statements', S) + "\n"
    + "/// Args: [batch_id_iliyohifadhiwa, company_id, batch_id_asili]\n"
    + dart_list('kArchiveBatchStatements', ARCHIVE) + "\n"
    + "/// Queries za Batch/Sale traceability (param moja: uuid).\n"
    + "const Map<String, String> kTraceQueries = {\n"
    + ",\n".join(dart_map_entry(n, q) for n, q in TRACE.items()) + ",\n};\n\n"
    + "/// Madeni yaliyofika/yanayokaribia due date. Args: [company_id, due_date_hadi].\n"
    + f"const String kDebtsDueSql =\n    r'''{DEBTS_DUE}''';\n\n"
    + "/// Ukaguzi wa orphan (mahusiano ya kimantiki). Kila SQL inarudisha COUNT.\n"
    + "const Map<String, String> kOrphanChecks = {\n"
    + ",\n".join(dart_map_entry(n, q) for n, q in ORPHANS)
    + ",\n};\n")
import json
(ROOT / 'docs/migrations/orphan_checks.json').write_text(json.dumps(dict(ORPHANS), indent=1))
(ROOT / 'docs/migrations/queries.json').write_text(json.dumps({'trace': TRACE, 'debts_due': DEBTS_DUE}, indent=1))
print(len(S), 'statements')
