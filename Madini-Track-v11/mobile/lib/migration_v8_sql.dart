// IMEZALISHWA na tools/gen_v8.py kutoka docs/migrations/v8_up.sql. Usihariri.

const List<String> kV8Statements = [
  r'''ALTER TABLE production_records ADD COLUMN original_batch_id TEXT
''',
  r'''ALTER TABLE ore_batches ADD COLUMN original_batch_id TEXT
''',
  r'''ALTER TABLE processing_records ADD COLUMN original_batch_id TEXT
''',
  r'''ALTER TABLE gold_inventory ADD COLUMN original_batch_id TEXT
''',
  r'''ALTER TABLE finance_transactions ADD COLUMN batch_uuid TEXT
''',
  r'''ALTER TABLE finance_transactions ADD COLUMN approval_status TEXT NOT NULL DEFAULT 'Imeidhinishwa'
''',
  r'''ALTER TABLE finance_transactions ADD COLUMN approved_by TEXT
''',
  r'''ALTER TABLE finance_transactions ADD COLUMN approved_at TEXT
''',
  r'''ALTER TABLE production_records ADD COLUMN witness_user_uuid TEXT
''',
  r'''ALTER TABLE production_records ADD COLUMN witness_verified INTEGER NOT NULL DEFAULT 0
''',
  r'''ALTER TABLE batch_movements ADD COLUMN created_at TEXT
''',
  r'''UPDATE batch_movements SET created_at = movement_date WHERE created_at IS NULL
''',
  r'''UPDATE ore_batches SET original_batch_id = batch_id, batch_id = batch_id || '~V' || (SELECT substr(p.uuid,1,8) FROM production_records p WHERE p.company_id = ore_batches.company_id AND p.batch_id = ore_batches.batch_id AND p.voided = 1) WHERE original_batch_id IS NULL AND EXISTS (SELECT 1 FROM production_records p WHERE p.company_id = ore_batches.company_id AND p.batch_id = ore_batches.batch_id AND p.voided = 1)
''',
  r'''UPDATE processing_records SET original_batch_id = batch_id, batch_id = batch_id || '~V' || (SELECT substr(p.uuid,1,8) FROM production_records p WHERE p.company_id = processing_records.company_id AND p.batch_id = processing_records.batch_id AND p.voided = 1) WHERE original_batch_id IS NULL AND EXISTS (SELECT 1 FROM production_records p WHERE p.company_id = processing_records.company_id AND p.batch_id = processing_records.batch_id AND p.voided = 1)
''',
  r'''UPDATE gold_inventory SET original_batch_id = batch_id, batch_id = batch_id || '~V' || (SELECT substr(p.uuid,1,8) FROM production_records p WHERE p.company_id = gold_inventory.company_id AND p.batch_id = gold_inventory.batch_id AND p.voided = 1) WHERE original_batch_id IS NULL AND EXISTS (SELECT 1 FROM production_records p WHERE p.company_id = gold_inventory.company_id AND p.batch_id = gold_inventory.batch_id AND p.voided = 1)
''',
  r'''UPDATE production_records SET original_batch_id = batch_id, batch_id = batch_id || '~V' || substr(uuid,1,8) WHERE voided = 1 AND original_batch_id IS NULL
''',
  r'''CREATE TABLE sync_outbox (
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
)
''',
  r'''CREATE UNIQUE INDEX uq_outbox_open ON sync_outbox(entity, record_uuid) WHERE sync_status IN ('pending','failed')
''',
  r'''CREATE INDEX idx_outbox_due ON sync_outbox(sync_status, next_retry_at)
''',
  r'''CREATE TABLE sync_attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  outbox_uuid TEXT NOT NULL REFERENCES sync_outbox(uuid) ON DELETE CASCADE,
  attempted_at TEXT NOT NULL,
  http_status INTEGER,
  result TEXT NOT NULL,
  error TEXT
)
''',
  r'''CREATE INDEX idx_attempts_outbox ON sync_attempts(outbox_uuid)
''',
  r'''CREATE TABLE local_users (
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
)
''',
  r'''CREATE TABLE sync_state (
  key TEXT PRIMARY KEY,
  value TEXT,
  updated_at TEXT NOT NULL
)
''',
  r'''CREATE TABLE attachments (
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
  uuid TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  device_id TEXT,
  version INTEGER NOT NULL DEFAULT 1,
  deleted_at TEXT,
  sync_status TEXT NOT NULL DEFAULT 'Pending'
)
''',
  r'''CREATE INDEX idx_attachments_record ON attachments(record_entity, record_uuid)
''',
  r'''CREATE INDEX idx_attachments_upload ON attachments(upload_status)
''',
  r'''CREATE TABLE tax_rates (
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
  uuid TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  device_id TEXT,
  version INTEGER NOT NULL DEFAULT 1,
  deleted_at TEXT,
  sync_status TEXT NOT NULL DEFAULT 'Pending',
  CHECK (effective_to IS NULL OR effective_to >= effective_from)
)
''',
  r'''CREATE INDEX idx_tax_rates_lookup ON tax_rates(company_id, rate_type, status, effective_from)
''',
  r'''CREATE TABLE safety_incidents (
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
  uuid TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  device_id TEXT,
  version INTEGER NOT NULL DEFAULT 1,
  deleted_at TEXT,
  sync_status TEXT NOT NULL DEFAULT 'Pending'
)
''',
  r'''CREATE INDEX idx_safety_scope ON safety_incidents(company_id, mine_id, occurred_at)
''',
  r'''CREATE INDEX idx_fin_batch ON finance_transactions(batch_uuid)
''',
  r'''CREATE TRIGGER trg_fk_attendance_worker_uuid BEFORE INSERT ON attendance
FOR EACH ROW WHEN NOT EXISTS (SELECT 1 FROM workers WHERE uuid = NEW.worker_uuid)
BEGIN
  SELECT RAISE(ABORT, 'FK: attendance.worker_uuid -> workers.uuid haipo');
END
''',
  r'''CREATE TRIGGER trg_fk_payroll_payments_worker_uuid BEFORE INSERT ON payroll_payments
FOR EACH ROW WHEN NOT EXISTS (SELECT 1 FROM workers WHERE uuid = NEW.worker_uuid)
BEGIN
  SELECT RAISE(ABORT, 'FK: payroll_payments.worker_uuid -> workers.uuid haipo');
END
''',
  r'''CREATE TRIGGER trg_fk_debt_payments_debt_uuid BEFORE INSERT ON debt_payments
FOR EACH ROW WHEN NOT EXISTS (SELECT 1 FROM debts WHERE uuid = NEW.debt_uuid)
BEGIN
  SELECT RAISE(ABORT, 'FK: debt_payments.debt_uuid -> debts.uuid haipo');
END
''',
  r'''CREATE TRIGGER trg_fk_inventory_movements_item_uuid BEFORE INSERT ON inventory_movements
FOR EACH ROW WHEN NOT EXISTS (SELECT 1 FROM inventory_items WHERE uuid = NEW.item_uuid)
BEGIN
  SELECT RAISE(ABORT, 'FK: inventory_movements.item_uuid -> inventory_items.uuid haipo');
END
''',
  r'''CREATE TRIGGER trg_fk_gold_sale_allocations_sale_uuid BEFORE INSERT ON gold_sale_allocations
FOR EACH ROW WHEN NOT EXISTS (SELECT 1 FROM sales WHERE uuid = NEW.sale_uuid)
BEGIN
  SELECT RAISE(ABORT, 'FK: gold_sale_allocations.sale_uuid -> sales.uuid haipo');
END
''',
  r'''CREATE TRIGGER trg_fk_gold_sale_allocations_lot_uuid BEFORE INSERT ON gold_sale_allocations
FOR EACH ROW WHEN NOT EXISTS (SELECT 1 FROM gold_inventory WHERE uuid = NEW.lot_uuid)
BEGIN
  SELECT RAISE(ABORT, 'FK: gold_sale_allocations.lot_uuid -> gold_inventory.uuid haipo');
END
''',
  r'''CREATE TRIGGER trg_fk_gold_inventory_processing_uuid BEFORE INSERT ON gold_inventory
FOR EACH ROW WHEN NOT EXISTS (SELECT 1 FROM processing_records WHERE uuid = NEW.processing_uuid)
BEGIN
  SELECT RAISE(ABORT, 'FK: gold_inventory.processing_uuid -> processing_records.uuid haipo');
END
''',
  r'''DROP TRIGGER IF EXISTS trg_companies_v7_meta
''',
  r'''CREATE TRIGGER trg_companies_v8_meta AFTER UPDATE ON companies
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE companies SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = NEW.deleted_at,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_mines_v7_meta
''',
  r'''CREATE TRIGGER trg_mines_v8_meta AFTER UPDATE ON mines
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE mines SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = NEW.deleted_at,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_production_records_v7_meta
''',
  r'''CREATE TRIGGER trg_production_records_v8_meta AFTER UPDATE ON production_records
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE production_records SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = CASE WHEN NEW.voided = 1 THEN COALESCE(NEW.deleted_at, strftime('%Y-%m-%dT%H:%M:%fZ','now')) ELSE NEW.deleted_at END,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_ore_batches_v7_meta
''',
  r'''CREATE TRIGGER trg_ore_batches_v8_meta AFTER UPDATE ON ore_batches
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE ore_batches SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = NEW.deleted_at,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_batch_movements_v7_meta
''',
  r'''CREATE TRIGGER trg_batch_movements_v8_meta AFTER UPDATE ON batch_movements
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE batch_movements SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = NEW.deleted_at,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_processing_records_v7_meta
''',
  r'''CREATE TRIGGER trg_processing_records_v8_meta AFTER UPDATE ON processing_records
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE processing_records SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = CASE WHEN NEW.voided = 1 THEN COALESCE(NEW.deleted_at, strftime('%Y-%m-%dT%H:%M:%fZ','now')) ELSE NEW.deleted_at END,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_workers_v7_meta
''',
  r'''CREATE TRIGGER trg_workers_v8_meta AFTER UPDATE ON workers
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE workers SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = NEW.deleted_at,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_attendance_v7_meta
''',
  r'''CREATE TRIGGER trg_attendance_v8_meta AFTER UPDATE ON attendance
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE attendance SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = NEW.deleted_at,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_payroll_payments_v7_meta
''',
  r'''CREATE TRIGGER trg_payroll_payments_v8_meta AFTER UPDATE ON payroll_payments
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE payroll_payments SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = CASE WHEN NEW.voided = 1 THEN COALESCE(NEW.deleted_at, strftime('%Y-%m-%dT%H:%M:%fZ','now')) ELSE NEW.deleted_at END,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_finance_transactions_v7_meta
''',
  r'''CREATE TRIGGER trg_finance_transactions_v8_meta AFTER UPDATE ON finance_transactions
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE finance_transactions SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = CASE WHEN NEW.voided = 1 THEN COALESCE(NEW.deleted_at, strftime('%Y-%m-%dT%H:%M:%fZ','now')) ELSE NEW.deleted_at END,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_debts_v7_meta
''',
  r'''CREATE TRIGGER trg_debts_v8_meta AFTER UPDATE ON debts
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE debts SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = CASE WHEN NEW.voided = 1 THEN COALESCE(NEW.deleted_at, strftime('%Y-%m-%dT%H:%M:%fZ','now')) ELSE NEW.deleted_at END,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_debt_payments_v7_meta
''',
  r'''CREATE TRIGGER trg_debt_payments_v8_meta AFTER UPDATE ON debt_payments
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE debt_payments SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = NEW.deleted_at,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_inventory_items_v7_meta
''',
  r'''CREATE TRIGGER trg_inventory_items_v8_meta AFTER UPDATE ON inventory_items
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE inventory_items SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = NEW.deleted_at,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_inventory_movements_v7_meta
''',
  r'''CREATE TRIGGER trg_inventory_movements_v8_meta AFTER UPDATE ON inventory_movements
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE inventory_movements SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = CASE WHEN NEW.voided = 1 THEN COALESCE(NEW.deleted_at, strftime('%Y-%m-%dT%H:%M:%fZ','now')) ELSE NEW.deleted_at END,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_sales_v7_meta
''',
  r'''CREATE TRIGGER trg_sales_v8_meta AFTER UPDATE ON sales
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sales SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = CASE WHEN NEW.voided = 1 THEN COALESCE(NEW.deleted_at, strftime('%Y-%m-%dT%H:%M:%fZ','now')) ELSE NEW.deleted_at END,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_audit_log_v7_meta
''',
  r'''CREATE TRIGGER trg_audit_log_v8_meta AFTER UPDATE ON audit_log
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE audit_log SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = NEW.deleted_at,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_gold_inventory_v7_meta
''',
  r'''CREATE TRIGGER trg_gold_inventory_v8_meta AFTER UPDATE ON gold_inventory
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE gold_inventory SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = NEW.deleted_at,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_gold_sale_allocations_v7_meta
''',
  r'''CREATE TRIGGER trg_gold_sale_allocations_v8_meta AFTER UPDATE ON gold_sale_allocations
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE gold_sale_allocations SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = NEW.deleted_at,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_attachments_v7_meta
''',
  r'''CREATE TRIGGER trg_attachments_v8_meta AFTER UPDATE ON attachments
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE attachments SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = NEW.deleted_at,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_tax_rates_v7_meta
''',
  r'''CREATE TRIGGER trg_tax_rates_v8_meta AFTER UPDATE ON tax_rates
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE tax_rates SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = NEW.deleted_at,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''DROP TRIGGER IF EXISTS trg_safety_incidents_v7_meta
''',
  r'''CREATE TRIGGER trg_safety_incidents_v8_meta AFTER UPDATE ON safety_incidents
FOR EACH ROW WHEN NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE safety_incidents SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    device_id = COALESCE(NULLIF(NEW.device_id,''), (SELECT value FROM app_metadata WHERE key = 'device_id')),
    version = MAX(COALESCE(NEW.version,1), COALESCE(OLD.version,1) + 1),
    deleted_at = CASE WHEN NEW.voided = 1 THEN COALESCE(NEW.deleted_at, strftime('%Y-%m-%dT%H:%M:%fZ','now')) ELSE NEW.deleted_at END,
    sync_status = CASE WHEN NEW.sync_status = 'Synced' THEN 'Pending' ELSE NEW.sync_status END
  WHERE id = NEW.id;
END
''',
  r'''CREATE TRIGGER trg_companies_v8_ob_ins AFTER INSERT ON companies
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'companies:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'companies' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'companies', NEW.uuid, NEW.name, 'upsert', NEW.version,
      'companies:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'companies' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_companies_v8_ob_upd AFTER UPDATE ON companies
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'companies:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'companies' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'companies', NEW.uuid, NEW.name, 'upsert', NEW.version,
      'companies:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'companies' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_mines_v8_ob_ins AFTER INSERT ON mines
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'mines:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'mines' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'mines', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'mines:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'mines' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_mines_v8_ob_upd AFTER UPDATE ON mines
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'mines:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'mines' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'mines', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'mines:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'mines' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_production_records_v8_ob_ins AFTER INSERT ON production_records
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'production_records:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'production_records' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'production_records', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'production_records:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'production_records' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_production_records_v8_ob_upd AFTER UPDATE ON production_records
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'production_records:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'production_records' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'production_records', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'production_records:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'production_records' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_ore_batches_v8_ob_ins AFTER INSERT ON ore_batches
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'ore_batches:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'ore_batches' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'ore_batches', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'ore_batches:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'ore_batches' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_ore_batches_v8_ob_upd AFTER UPDATE ON ore_batches
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'ore_batches:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'ore_batches' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'ore_batches', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'ore_batches:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'ore_batches' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_batch_movements_v8_ob_ins AFTER INSERT ON batch_movements
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'batch_movements:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'batch_movements' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'batch_movements', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'batch_movements:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'batch_movements' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_batch_movements_v8_ob_upd AFTER UPDATE ON batch_movements
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'batch_movements:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'batch_movements' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'batch_movements', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'batch_movements:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'batch_movements' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_processing_records_v8_ob_ins AFTER INSERT ON processing_records
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'processing_records:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'processing_records' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'processing_records', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'processing_records:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'processing_records' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_processing_records_v8_ob_upd AFTER UPDATE ON processing_records
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'processing_records:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'processing_records' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'processing_records', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'processing_records:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'processing_records' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_workers_v8_ob_ins AFTER INSERT ON workers
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'workers:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'workers' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'workers', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'workers:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'workers' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_workers_v8_ob_upd AFTER UPDATE ON workers
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'workers:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'workers' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'workers', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'workers:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'workers' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_attendance_v8_ob_ins AFTER INSERT ON attendance
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'attendance:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'attendance' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'attendance', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'attendance:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'attendance' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_attendance_v8_ob_upd AFTER UPDATE ON attendance
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'attendance:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'attendance' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'attendance', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'attendance:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'attendance' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_payroll_payments_v8_ob_ins AFTER INSERT ON payroll_payments
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'payroll_payments:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'payroll_payments' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'payroll_payments', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'payroll_payments:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'payroll_payments' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_payroll_payments_v8_ob_upd AFTER UPDATE ON payroll_payments
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'payroll_payments:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'payroll_payments' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'payroll_payments', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'payroll_payments:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'payroll_payments' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_finance_transactions_v8_ob_ins AFTER INSERT ON finance_transactions
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'finance_transactions:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'finance_transactions' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'finance_transactions', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'finance_transactions:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'finance_transactions' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_finance_transactions_v8_ob_upd AFTER UPDATE ON finance_transactions
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'finance_transactions:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'finance_transactions' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'finance_transactions', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'finance_transactions:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'finance_transactions' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_debts_v8_ob_ins AFTER INSERT ON debts
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'debts:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'debts' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'debts', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'debts:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'debts' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_debts_v8_ob_upd AFTER UPDATE ON debts
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'debts:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'debts' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'debts', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'debts:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'debts' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_debt_payments_v8_ob_ins AFTER INSERT ON debt_payments
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'debt_payments:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'debt_payments' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'debt_payments', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'debt_payments:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'debt_payments' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_debt_payments_v8_ob_upd AFTER UPDATE ON debt_payments
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'debt_payments:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'debt_payments' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'debt_payments', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'debt_payments:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'debt_payments' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_inventory_items_v8_ob_ins AFTER INSERT ON inventory_items
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'inventory_items:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'inventory_items' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'inventory_items', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'inventory_items:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'inventory_items' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_inventory_items_v8_ob_upd AFTER UPDATE ON inventory_items
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'inventory_items:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'inventory_items' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'inventory_items', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'inventory_items:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'inventory_items' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_inventory_movements_v8_ob_ins AFTER INSERT ON inventory_movements
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'inventory_movements:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'inventory_movements' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'inventory_movements', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'inventory_movements:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'inventory_movements' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_inventory_movements_v8_ob_upd AFTER UPDATE ON inventory_movements
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'inventory_movements:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'inventory_movements' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'inventory_movements', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'inventory_movements:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'inventory_movements' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_sales_v8_ob_ins AFTER INSERT ON sales
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'sales:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'sales' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'sales', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'sales:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'sales' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_sales_v8_ob_upd AFTER UPDATE ON sales
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'sales:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'sales' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'sales', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'sales:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'sales' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_audit_log_v8_ob_ins AFTER INSERT ON audit_log
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'audit_log:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'audit_log' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'audit_log', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'audit_log:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'audit_log' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_audit_log_v8_ob_upd AFTER UPDATE ON audit_log
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'audit_log:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'audit_log' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'audit_log', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'audit_log:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'audit_log' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_gold_inventory_v8_ob_ins AFTER INSERT ON gold_inventory
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'gold_inventory:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'gold_inventory' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'gold_inventory', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'gold_inventory:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'gold_inventory' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_gold_inventory_v8_ob_upd AFTER UPDATE ON gold_inventory
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'gold_inventory:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'gold_inventory' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'gold_inventory', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'gold_inventory:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'gold_inventory' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_gold_sale_allocations_v8_ob_ins AFTER INSERT ON gold_sale_allocations
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'gold_sale_allocations:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'gold_sale_allocations' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'gold_sale_allocations', NEW.uuid, (SELECT s.company_id FROM sales s WHERE s.uuid = NEW.sale_uuid), 'upsert', NEW.version,
      'gold_sale_allocations:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'gold_sale_allocations' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_gold_sale_allocations_v8_ob_upd AFTER UPDATE ON gold_sale_allocations
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'gold_sale_allocations:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'gold_sale_allocations' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'gold_sale_allocations', NEW.uuid, (SELECT s.company_id FROM sales s WHERE s.uuid = NEW.sale_uuid), 'upsert', NEW.version,
      'gold_sale_allocations:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'gold_sale_allocations' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_attachments_v8_ob_ins AFTER INSERT ON attachments
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'attachments:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'attachments' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'attachments', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'attachments:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'attachments' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_attachments_v8_ob_upd AFTER UPDATE ON attachments
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'attachments:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'attachments' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'attachments', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'attachments:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'attachments' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_tax_rates_v8_ob_ins AFTER INSERT ON tax_rates
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'tax_rates:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'tax_rates' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'tax_rates', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'tax_rates:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'tax_rates' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_tax_rates_v8_ob_upd AFTER UPDATE ON tax_rates
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'tax_rates:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'tax_rates' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'tax_rates', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'tax_rates:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'tax_rates' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_safety_incidents_v8_ob_ins AFTER INSERT ON safety_incidents
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'safety_incidents:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'safety_incidents' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'safety_incidents', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'safety_incidents:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'safety_incidents' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''CREATE TRIGGER trg_safety_incidents_v8_ob_upd AFTER UPDATE ON safety_incidents
FOR EACH ROW WHEN NEW.uuid IS NOT NULL AND NOT (COALESCE(OLD.sync_status,'') <> 'Synced' AND NEW.sync_status = 'Synced') AND COALESCE((SELECT value FROM sync_state WHERE key = 'applying_pull'), '0') <> '1'
BEGIN
  UPDATE sync_outbox SET
    record_version = MAX(record_version, NEW.version),
    idempotency_key = 'safety_incidents:' || NEW.uuid || ':' || MAX(record_version, NEW.version),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE entity = 'safety_incidents' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed');
  INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
      idempotency_key, sync_status, created_at, updated_at)
  SELECT lower(hex(randomblob(16))), 'safety_incidents', NEW.uuid, NEW.company_id, 'upsert', NEW.version,
      'safety_incidents:' || NEW.uuid || ':' || NEW.version, 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS (SELECT 1 FROM sync_outbox
      WHERE entity = 'safety_incidents' AND record_uuid = NEW.uuid AND sync_status IN ('pending','failed'));
END
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'companies', r.uuid, r.name, 'upsert', COALESCE(r.version,1),
    'companies:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM companies r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'companies'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'mines', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'mines:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM mines r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'mines'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'production_records', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'production_records:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM production_records r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'production_records'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'ore_batches', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'ore_batches:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM ore_batches r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'ore_batches'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'batch_movements', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'batch_movements:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM batch_movements r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'batch_movements'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'processing_records', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'processing_records:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM processing_records r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'processing_records'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'workers', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'workers:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM workers r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'workers'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'attendance', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'attendance:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM attendance r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'attendance'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'payroll_payments', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'payroll_payments:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM payroll_payments r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'payroll_payments'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'finance_transactions', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'finance_transactions:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM finance_transactions r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'finance_transactions'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'debts', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'debts:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM debts r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'debts'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'debt_payments', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'debt_payments:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM debt_payments r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'debt_payments'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'inventory_items', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'inventory_items:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM inventory_items r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'inventory_items'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'inventory_movements', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'inventory_movements:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM inventory_movements r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'inventory_movements'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'sales', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'sales:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM sales r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'sales'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'audit_log', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'audit_log:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM audit_log r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'audit_log'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'gold_inventory', r.uuid, r.company_id, 'upsert', COALESCE(r.version,1),
    'gold_inventory:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM gold_inventory r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'gold_inventory'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''INSERT INTO sync_outbox (uuid, entity, record_uuid, company_name, op, record_version,
    idempotency_key, sync_status, created_at, updated_at)
SELECT lower(hex(randomblob(16))), 'gold_sale_allocations', r.uuid, (SELECT s.company_id FROM sales s WHERE s.uuid = r.sale_uuid), 'upsert', COALESCE(r.version,1),
    'gold_sale_allocations:' || r.uuid || ':' || COALESCE(r.version,1), 'pending', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM gold_sale_allocations r WHERE r.uuid IS NOT NULL AND COALESCE(r.sync_status,'Pending') <> 'Synced'
  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity = 'gold_sale_allocations'
      AND o.record_uuid = r.uuid AND o.sync_status IN ('pending','failed'))
''',
  r'''CREATE VIEW v_mass_balance AS
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
FROM ore_batches b WHERE b.status <> 'Imefutwa'
''',
  r'''CREATE VIEW v_batch_costs AS
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
GROUP BY b.uuid
''',
];

/// Args: [batch_id_iliyohifadhiwa, company_id, batch_id_asili]
const List<String> kArchiveBatchStatements = [
  r'''UPDATE processing_records SET original_batch_id = batch_id, batch_id = ? WHERE company_id = ? AND batch_id = ? AND voided = 1
''',
  r'''UPDATE gold_inventory SET original_batch_id = batch_id, batch_id = ? WHERE company_id = ? AND batch_id = ?
''',
  r'''UPDATE ore_batches SET original_batch_id = batch_id, batch_id = ? WHERE company_id = ? AND batch_id = ?
''',
  r'''UPDATE production_records SET original_batch_id = batch_id, batch_id = ? WHERE company_id = ? AND batch_id = ?
''',
];

/// Queries za Batch/Sale traceability (param moja: uuid).
const Map<String, String> kTraceQueries = {
  'batch': r'''SELECT * FROM ore_batches WHERE uuid = ?''',
  'production':
      r'''SELECT p.* FROM production_records p JOIN ore_batches b ON b.source_production_uuid = p.uuid WHERE b.uuid = ?''',
  'children':
      r'''SELECT * FROM ore_batches WHERE parent_batch_uuid = ? ORDER BY id''',
  'merged_sources':
      r'''SELECT b.*, m.weight_kg AS merged_weight_kg FROM batch_movements m JOIN ore_batches target ON target.company_id = m.company_id AND target.batch_id = m.child_batch_id JOIN ore_batches b ON b.company_id = m.company_id AND b.batch_id = m.batch_id WHERE target.uuid = ? AND b.status = 'Imeunganishwa' AND m.notes LIKE 'Imeunganishwa kuwa Batch %' ORDER BY m.id''',
  'movements':
      r'''SELECT m.* FROM batch_movements m JOIN ore_batches b ON b.company_id = m.company_id AND b.batch_id = m.batch_id WHERE b.uuid = ? ORDER BY m.id''',
  'processing':
      r'''SELECT p.* FROM processing_records p JOIN ore_batches b ON b.company_id = p.company_id AND b.batch_id = p.batch_id WHERE b.uuid = ? AND p.voided = 0 ORDER BY p.id''',
  'lots':
      r'''SELECT g.* FROM gold_inventory g JOIN processing_records p ON p.uuid = g.processing_uuid JOIN ore_batches b ON b.company_id = p.company_id AND b.batch_id = p.batch_id WHERE b.uuid = ? AND p.voided = 0 ORDER BY g.id''',
  'sales':
      r'''SELECT s.uuid AS sale_uuid, s.sale_date, s.buyer, s.reference, a.grams, a.lot_uuid FROM gold_sale_allocations a JOIN sales s ON s.uuid = a.sale_uuid JOIN gold_inventory g ON g.uuid = a.lot_uuid JOIN processing_records p ON p.uuid = g.processing_uuid JOIN ore_batches b ON b.company_id = p.company_id AND b.batch_id = p.batch_id WHERE b.uuid = ? AND s.voided = 0 ORDER BY s.sale_date, s.id''',
  'sale_sources':
      r'''SELECT b.batch_id AS batch_id, b.uuid AS batch_uuid, p.uuid AS processing_uuid, g.uuid AS lot_uuid, a.grams AS grams FROM gold_sale_allocations a JOIN gold_inventory g ON g.uuid = a.lot_uuid JOIN processing_records p ON p.uuid = g.processing_uuid JOIN ore_batches b ON b.company_id = p.company_id AND b.batch_id = p.batch_id WHERE a.sale_uuid = ? ORDER BY a.id''',
  'evidence':
      r'''SELECT * FROM attachments WHERE record_uuid = ? AND deleted_at IS NULL ORDER BY id''',
};

/// Madeni yaliyofika/yanayokaribia due date. Args: [company_id, due_date_hadi].
const String kDebtsDueSql =
    r'''SELECT d.*, IFNULL((SELECT SUM(p.amount) FROM debt_payments p WHERE p.debt_uuid = d.uuid), 0) AS paid FROM debts d WHERE d.company_id = ? AND d.voided = 0 AND d.due_date IS NOT NULL AND d.due_date <> '' AND d.due_date <= ? AND d.amount - IFNULL((SELECT SUM(p.amount) FROM debt_payments p WHERE p.debt_uuid = d.uuid), 0) > 0.005 ORDER BY d.due_date''';

/// Ukaguzi wa orphan (mahusiano ya kimantiki). Kila SQL inarudisha COUNT.
const Map<String, String> kOrphanChecks = {
  'attendance_worker':
      r'''SELECT COUNT(*) FROM attendance a WHERE NOT EXISTS (SELECT 1 FROM workers w WHERE w.uuid = a.worker_uuid)''',
  'payroll_worker':
      r'''SELECT COUNT(*) FROM payroll_payments a WHERE NOT EXISTS (SELECT 1 FROM workers w WHERE w.uuid = a.worker_uuid)''',
  'debt_payment_debt':
      r'''SELECT COUNT(*) FROM debt_payments a WHERE NOT EXISTS (SELECT 1 FROM debts d WHERE d.uuid = a.debt_uuid)''',
  'stock_move_item':
      r'''SELECT COUNT(*) FROM inventory_movements a WHERE NOT EXISTS (SELECT 1 FROM inventory_items i WHERE i.uuid = a.item_uuid)''',
  'allocation_sale':
      r'''SELECT COUNT(*) FROM gold_sale_allocations a WHERE NOT EXISTS (SELECT 1 FROM sales s WHERE s.uuid = a.sale_uuid)''',
  'allocation_lot':
      r'''SELECT COUNT(*) FROM gold_sale_allocations a WHERE NOT EXISTS (SELECT 1 FROM gold_inventory g WHERE g.uuid = a.lot_uuid)''',
  'lot_processing':
      r'''SELECT COUNT(*) FROM gold_inventory a WHERE NOT EXISTS (SELECT 1 FROM processing_records p WHERE p.uuid = a.processing_uuid)''',
  'batch_without_production':
      r'''SELECT COUNT(*) FROM ore_batches b WHERE b.parent_batch_id IS NULL AND NOT EXISTS (SELECT 1 FROM production_records p WHERE p.company_id = b.company_id AND (p.batch_id = b.batch_id OR p.uuid = b.source_production_uuid))''',
  'movement_without_batch':
      r'''SELECT COUNT(*) FROM batch_movements m WHERE NOT EXISTS (SELECT 1 FROM ore_batches b WHERE b.company_id = m.company_id AND b.batch_id = m.batch_id)''',
  'processing_without_batch':
      r'''SELECT COUNT(*) FROM processing_records p WHERE NOT EXISTS (SELECT 1 FROM ore_batches b WHERE b.company_id = p.company_id AND b.batch_id = p.batch_id)''',
};
