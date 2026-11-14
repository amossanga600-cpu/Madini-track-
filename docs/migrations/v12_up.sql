-- Madini Track schema v11 -> v12.
-- Adds UUID-to-UUID links for the material genealogy without removing legacy IDs.
ALTER TABLE production_records ADD COLUMN batch_uuid TEXT;
ALTER TABLE batch_movements ADD COLUMN mine_id TEXT;
ALTER TABLE batch_movements ADD COLUMN batch_uuid TEXT;
ALTER TABLE batch_movements ADD COLUMN parent_batch_uuid TEXT;
ALTER TABLE batch_movements ADD COLUMN child_batch_uuid TEXT;
ALTER TABLE processing_records ADD COLUMN batch_uuid TEXT;
ALTER TABLE gold_inventory ADD COLUMN batch_uuid TEXT;
ALTER TABLE gold_sale_allocations ADD COLUMN batch_uuid TEXT;

CREATE TABLE batch_traceability_issues (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  company_id TEXT,
  mine_id TEXT,
  entity TEXT NOT NULL,
  record_uuid TEXT NOT NULL,
  relation TEXT NOT NULL,
  legacy_batch_id TEXT,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL,
  resolved_at TEXT,
  UNIQUE(entity, record_uuid, relation)
);

UPDATE production_records
SET batch_uuid = (
  SELECT b.uuid FROM ore_batches AS b
  WHERE b.company_id = production_records.company_id
    AND b.mine_id = production_records.mine_id
    AND b.batch_id = production_records.batch_id
    AND (b.source_production_uuid = production_records.uuid
         OR b.source_production_uuid IS NULL)
)
WHERE production_records.batch_uuid IS NULL
  AND (SELECT COUNT(*) FROM ore_batches AS b
       WHERE b.company_id = production_records.company_id
         AND b.mine_id = production_records.mine_id
         AND b.batch_id = production_records.batch_id
         AND (b.source_production_uuid = production_records.uuid
              OR b.source_production_uuid IS NULL)) = 1;

UPDATE batch_movements
SET batch_uuid = (
  SELECT b.uuid FROM ore_batches AS b
  WHERE b.company_id = batch_movements.company_id
    AND b.batch_id = batch_movements.batch_id
  LIMIT 1
)
WHERE batch_movements.batch_uuid IS NULL
  AND (SELECT COUNT(*) FROM ore_batches AS b
       WHERE b.company_id = batch_movements.company_id
         AND b.batch_id = batch_movements.batch_id) = 1;

UPDATE batch_movements
SET child_batch_uuid = (
  SELECT b.uuid FROM ore_batches AS b
  WHERE b.company_id = batch_movements.company_id
    AND b.batch_id = batch_movements.child_batch_id
  LIMIT 1
)
WHERE batch_movements.child_batch_id IS NOT NULL
  AND batch_movements.child_batch_uuid IS NULL
  AND (SELECT COUNT(*) FROM ore_batches AS b
       WHERE b.company_id = batch_movements.company_id
         AND b.batch_id = batch_movements.child_batch_id) = 1;

UPDATE batch_movements
SET parent_batch_uuid = (
  SELECT b.parent_batch_uuid FROM ore_batches AS b
  WHERE b.company_id = batch_movements.company_id
    AND b.uuid = batch_movements.batch_uuid
  LIMIT 1
)
WHERE batch_movements.parent_batch_uuid IS NULL
  AND batch_movements.batch_uuid IS NOT NULL;

UPDATE batch_movements
SET mine_id = (
  SELECT b.mine_id FROM ore_batches AS b
  WHERE b.company_id = batch_movements.company_id
    AND b.uuid = batch_movements.batch_uuid
  LIMIT 1
)
WHERE batch_movements.mine_id IS NULL
  AND batch_movements.batch_uuid IS NOT NULL;

UPDATE processing_records
SET batch_uuid = (
  SELECT b.uuid FROM ore_batches AS b
  WHERE b.company_id = processing_records.company_id
    AND b.mine_id = processing_records.mine_id
    AND b.batch_id = processing_records.batch_id
  LIMIT 1
)
WHERE processing_records.batch_uuid IS NULL
  AND (SELECT COUNT(*) FROM ore_batches AS b
       WHERE b.company_id = processing_records.company_id
         AND b.mine_id = processing_records.mine_id
         AND b.batch_id = processing_records.batch_id) = 1;

UPDATE gold_inventory
SET batch_uuid = COALESCE(
  (SELECT p.batch_uuid FROM processing_records AS p
   WHERE p.uuid = gold_inventory.processing_uuid
     AND p.company_id = gold_inventory.company_id
     AND p.mine_id = gold_inventory.mine_id),
  (SELECT b.uuid FROM ore_batches AS b
   WHERE b.company_id = gold_inventory.company_id
     AND b.mine_id = gold_inventory.mine_id
     AND b.batch_id = gold_inventory.batch_id)
)
WHERE gold_inventory.batch_uuid IS NULL
  AND (
    (SELECT COUNT(*) FROM processing_records AS p
     WHERE p.uuid = gold_inventory.processing_uuid
       AND p.company_id = gold_inventory.company_id
       AND p.mine_id = gold_inventory.mine_id AND p.batch_uuid IS NOT NULL) = 1
    OR
    (SELECT COUNT(*) FROM ore_batches AS b
     WHERE b.company_id = gold_inventory.company_id
       AND b.mine_id = gold_inventory.mine_id
       AND b.batch_id = gold_inventory.batch_id) = 1
  );

UPDATE gold_sale_allocations
SET batch_uuid = (
  SELECT g.batch_uuid FROM gold_inventory AS g
  WHERE g.uuid = gold_sale_allocations.lot_uuid
  LIMIT 1
)
WHERE gold_sale_allocations.batch_uuid IS NULL
  AND (SELECT COUNT(*) FROM gold_inventory AS g
       WHERE g.uuid = gold_sale_allocations.lot_uuid
         AND g.batch_uuid IS NOT NULL) = 1;

CREATE INDEX idx_production_batch_uuid
  ON production_records(company_id, mine_id, batch_uuid);
CREATE INDEX idx_movement_batch_uuid
  ON batch_movements(company_id, batch_uuid);
CREATE INDEX idx_movement_parent_uuid ON batch_movements(parent_batch_uuid);
CREATE INDEX idx_movement_child_uuid ON batch_movements(child_batch_uuid);
CREATE INDEX idx_processing_batch_uuid
  ON processing_records(company_id, mine_id, batch_uuid);
CREATE INDEX idx_gold_batch_uuid
  ON gold_inventory(company_id, mine_id, batch_uuid);
CREATE INDEX idx_allocation_batch_uuid ON gold_sale_allocations(batch_uuid);

DROP VIEW IF EXISTS v_mass_balance;
CREATE VIEW v_mass_balance AS
SELECT b.uuid AS batch_uuid, b.company_id, b.mine_id, b.batch_id,
  COALESCE(NULLIF(b.weight_initial_kg,0), b.initial_weight_kg, b.weight_kg) AS initial_kg,
  b.weight_kg AS remaining_kg,
  IFNULL((SELECT SUM(p.ore_processed_kg) FROM processing_records p
          WHERE p.company_id = b.company_id AND p.batch_uuid = b.uuid AND p.voided = 0), 0) AS processed_kg,
  IFNULL((SELECT SUM(p.tailings_kg) FROM processing_records p
          WHERE p.company_id = b.company_id AND p.batch_uuid = b.uuid AND p.voided = 0), 0) AS tailings_kg,
  IFNULL((SELECT SUM(p.gold_recovered_g) FROM processing_records p
          WHERE p.company_id = b.company_id AND p.batch_uuid = b.uuid AND p.voided = 0), 0) AS gold_g,
  IFNULL((SELECT SUM(m.weight_kg) FROM batch_movements m
          WHERE m.company_id = b.company_id AND m.batch_uuid = b.uuid
            AND m.child_batch_uuid IS NOT NULL), 0) AS split_out_kg
FROM ore_batches b WHERE b.status <> 'Imefutwa';

INSERT OR IGNORE INTO batch_traceability_issues
  (company_id,mine_id,entity,record_uuid,relation,legacy_batch_id,reason,created_at)
SELECT p.company_id,p.mine_id,'production_records',p.uuid,'batch',
       p.batch_id,'Batch UUID haikuweza kutambuliwa bila utata.',strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM production_records p WHERE p.batch_uuid IS NULL;

INSERT OR IGNORE INTO batch_traceability_issues
  (company_id,mine_id,entity,record_uuid,relation,legacy_batch_id,reason,created_at)
SELECT m.company_id,m.mine_id,'batch_movements',m.uuid,'batch',
       m.batch_id,'Batch UUID ya uhamisho haikuweza kutambuliwa bila utata.',strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM batch_movements m WHERE m.batch_uuid IS NULL;

INSERT OR IGNORE INTO batch_traceability_issues
  (company_id,mine_id,entity,record_uuid,relation,legacy_batch_id,reason,created_at)
SELECT m.company_id,m.mine_id,'batch_movements',m.uuid,'child',
       m.child_batch_id,'Batch UUID ya mtoto haikuweza kutambuliwa bila utata.',strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM batch_movements m
WHERE m.child_batch_id IS NOT NULL AND m.child_batch_uuid IS NULL;

INSERT OR IGNORE INTO batch_traceability_issues
  (company_id,mine_id,entity,record_uuid,relation,legacy_batch_id,reason,created_at)
SELECT p.company_id,p.mine_id,'processing_records',p.uuid,'batch',
       p.batch_id,'Batch UUID ya uchakataji haikuweza kutambuliwa bila utata.',strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM processing_records p WHERE p.batch_uuid IS NULL;

INSERT OR IGNORE INTO batch_traceability_issues
  (company_id,mine_id,entity,record_uuid,relation,legacy_batch_id,reason,created_at)
SELECT g.company_id,g.mine_id,'gold_inventory',g.uuid,'batch',
       g.batch_id,'Batch UUID ya gold lot haikuweza kutambuliwa bila utata.',strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM gold_inventory g WHERE g.batch_uuid IS NULL;

INSERT OR IGNORE INTO batch_traceability_issues
  (company_id,mine_id,entity,record_uuid,relation,legacy_batch_id,reason,created_at)
SELECT s.company_id,s.mine_id,'gold_sale_allocations',a.uuid,'batch',
       NULL,'Batch UUID ya allocation haikuweza kutambuliwa bila utata.',strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM gold_sale_allocations a
JOIN sales s ON s.uuid = a.sale_uuid
WHERE a.batch_uuid IS NULL;

INSERT OR IGNORE INTO batch_traceability_issues
  (company_id,mine_id,entity,record_uuid,relation,legacy_batch_id,reason,created_at)
SELECT b.company_id,b.mine_id,'ore_batches',b.uuid,'parent',
       b.parent_batch_id,'Batch UUID ya mzazi haikuweza kutambuliwa bila utata.',strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM ore_batches b
WHERE b.parent_batch_id IS NOT NULL AND b.parent_batch_uuid IS NULL;

INSERT OR IGNORE INTO batch_traceability_issues
  (company_id,mine_id,entity,record_uuid,relation,legacy_batch_id,reason,created_at)
SELECT b.company_id,b.mine_id,'ore_batches',b.uuid,'source_production',
       b.batch_id,'Rekodi ya uzalishaji wa chanzo haipo au haikuweza kuunganishwa.',strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM ore_batches b
WHERE b.parent_batch_uuid IS NULL AND b.source_production_uuid IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM batch_movements m WHERE m.child_batch_uuid = b.uuid
  );

CREATE TRIGGER production_batch_uuid_insert
BEFORE INSERT ON production_records
WHEN NEW.batch_uuid IS NULL OR NOT EXISTS (
  SELECT 1 FROM ore_batches b
  WHERE b.uuid = NEW.batch_uuid AND b.company_id = NEW.company_id
    AND b.mine_id = NEW.mine_id AND b.batch_id = NEW.batch_id
    AND b.source_production_uuid = NEW.uuid
)
BEGIN
  SELECT RAISE(ABORT, 'production record requires matching batch UUID');
END;

CREATE TRIGGER production_batch_uuid_update
BEFORE UPDATE OF batch_uuid,company_id,mine_id,batch_id,uuid ON production_records
WHEN NEW.batch_uuid IS NULL OR NOT EXISTS (
  SELECT 1 FROM ore_batches b
  WHERE b.uuid = NEW.batch_uuid AND b.company_id = NEW.company_id
    AND b.mine_id = NEW.mine_id AND b.batch_id = NEW.batch_id
    AND b.source_production_uuid = NEW.uuid
)
BEGIN
  SELECT RAISE(ABORT, 'production record requires matching batch UUID');
END;

CREATE TRIGGER ore_batch_uuid_immutable
BEFORE UPDATE OF uuid ON ore_batches
WHEN NEW.uuid <> OLD.uuid
BEGIN
  SELECT RAISE(ABORT, 'batch UUID is immutable');
END;

CREATE TRIGGER batch_movement_uuid_insert
BEFORE INSERT ON batch_movements
WHEN NEW.batch_uuid IS NULL OR NOT EXISTS (
  SELECT 1 FROM ore_batches b
  WHERE b.uuid = NEW.batch_uuid AND b.company_id = NEW.company_id
    AND b.mine_id = NEW.mine_id AND b.batch_id = NEW.batch_id
)
OR (NEW.child_batch_id IS NOT NULL AND (
  NEW.child_batch_uuid IS NULL OR NOT EXISTS (
    SELECT 1 FROM ore_batches b
    WHERE b.uuid = NEW.child_batch_uuid AND b.company_id = NEW.company_id
      AND b.mine_id = NEW.mine_id AND b.batch_id = NEW.child_batch_id
  )
))
OR (NEW.parent_batch_uuid IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM ore_batches b
  WHERE b.uuid = NEW.parent_batch_uuid AND b.company_id = NEW.company_id
    AND b.mine_id = NEW.mine_id
))
BEGIN
  SELECT RAISE(ABORT, 'batch movement requires matching batch UUIDs');
END;

CREATE TRIGGER batch_movement_uuid_update
BEFORE UPDATE OF batch_uuid,parent_batch_uuid,child_batch_uuid,company_id,mine_id,batch_id,child_batch_id ON batch_movements
WHEN NEW.batch_uuid IS NULL OR NOT EXISTS (
  SELECT 1 FROM ore_batches b
  WHERE b.uuid = NEW.batch_uuid AND b.company_id = NEW.company_id
    AND b.mine_id = NEW.mine_id AND b.batch_id = NEW.batch_id
)
OR (NEW.child_batch_id IS NOT NULL AND (
  NEW.child_batch_uuid IS NULL OR NOT EXISTS (
    SELECT 1 FROM ore_batches b
    WHERE b.uuid = NEW.child_batch_uuid AND b.company_id = NEW.company_id
      AND b.mine_id = NEW.mine_id AND b.batch_id = NEW.child_batch_id
  )
))
OR (NEW.parent_batch_uuid IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM ore_batches b
  WHERE b.uuid = NEW.parent_batch_uuid AND b.company_id = NEW.company_id
    AND b.mine_id = NEW.mine_id
))
BEGIN
  SELECT RAISE(ABORT, 'batch movement requires matching batch UUIDs');
END;

CREATE TRIGGER processing_batch_uuid_insert
BEFORE INSERT ON processing_records
WHEN NEW.batch_uuid IS NULL OR NOT EXISTS (
  SELECT 1 FROM ore_batches b
  WHERE b.uuid = NEW.batch_uuid AND b.company_id = NEW.company_id
    AND b.mine_id = NEW.mine_id AND b.batch_id = NEW.batch_id
)
BEGIN
  SELECT RAISE(ABORT, 'processing record requires matching batch UUID');
END;

CREATE TRIGGER processing_batch_uuid_update
BEFORE UPDATE OF batch_uuid,company_id,mine_id,batch_id ON processing_records
WHEN NEW.batch_uuid IS NULL OR NOT EXISTS (
  SELECT 1 FROM ore_batches b
  WHERE b.uuid = NEW.batch_uuid AND b.company_id = NEW.company_id
    AND b.mine_id = NEW.mine_id AND b.batch_id = NEW.batch_id
)
BEGIN
  SELECT RAISE(ABORT, 'processing record requires matching batch UUID');
END;

CREATE TRIGGER gold_inventory_batch_uuid_insert
BEFORE INSERT ON gold_inventory
WHEN NEW.batch_uuid IS NULL OR NOT EXISTS (
  SELECT 1 FROM processing_records p
  WHERE p.uuid = NEW.processing_uuid AND p.batch_uuid = NEW.batch_uuid
    AND p.company_id = NEW.company_id AND p.mine_id = NEW.mine_id
    AND p.batch_id = NEW.batch_id
)
BEGIN
  SELECT RAISE(ABORT, 'gold lot requires matching processing and batch UUIDs');
END;

CREATE TRIGGER gold_inventory_batch_uuid_update
BEFORE UPDATE OF batch_uuid,processing_uuid,company_id,mine_id,batch_id ON gold_inventory
WHEN NEW.batch_uuid IS NULL OR NOT EXISTS (
  SELECT 1 FROM processing_records p
  WHERE p.uuid = NEW.processing_uuid AND p.batch_uuid = NEW.batch_uuid
    AND p.company_id = NEW.company_id AND p.mine_id = NEW.mine_id
    AND p.batch_id = NEW.batch_id
)
BEGIN
  SELECT RAISE(ABORT, 'gold lot requires matching processing and batch UUIDs');
END;

CREATE TRIGGER gold_allocation_batch_uuid_insert
BEFORE INSERT ON gold_sale_allocations
WHEN NEW.batch_uuid IS NULL OR NOT EXISTS (
  SELECT 1 FROM gold_inventory g
  WHERE g.uuid = NEW.lot_uuid AND g.batch_uuid = NEW.batch_uuid
)
BEGIN
  SELECT RAISE(ABORT, 'gold allocation requires matching batch UUID');
END;

CREATE TRIGGER gold_allocation_batch_uuid_update
BEFORE UPDATE OF batch_uuid,lot_uuid ON gold_sale_allocations
WHEN NEW.batch_uuid IS NULL OR NOT EXISTS (
  SELECT 1 FROM gold_inventory g
  WHERE g.uuid = NEW.lot_uuid AND g.batch_uuid = NEW.batch_uuid
)
BEGIN
  SELECT RAISE(ABORT, 'gold allocation requires matching batch UUID');
END;
