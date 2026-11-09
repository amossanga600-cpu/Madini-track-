const List<String> kV10Statements = [
  'DROP VIEW v_mass_balance',
  '''CREATE VIEW v_mass_balance AS
SELECT b.uuid AS batch_uuid, b.company_id, b.mine_id, b.batch_id,
  COALESCE(NULLIF(b.weight_initial_kg,0), b.initial_weight_kg, b.weight_kg) AS initial_kg,
  b.weight_kg AS remaining_kg,
  IFNULL((SELECT SUM(p.ore_processed_kg) FROM processing_records p
          WHERE p.company_id = b.company_id AND p.batch_id = b.batch_id AND p.voided = 0), 0) AS processed_kg,
  IFNULL((SELECT SUM(p.tailings_kg) FROM processing_records p
          WHERE p.company_id = b.company_id AND p.batch_id = b.batch_id AND p.voided = 0), 0) AS tailings_kg,
  IFNULL((SELECT SUM(p.gold_recovered_g) FROM processing_records p
          WHERE p.company_id = b.company_id AND p.batch_id = b.batch_id AND p.voided = 0), 0) AS gold_g,
  IFNULL((SELECT SUM(m.weight_kg) FROM batch_movements m
          WHERE m.company_id = b.company_id AND m.batch_id = b.batch_id
            AND m.child_batch_id IS NOT NULL), 0) AS split_out_kg
FROM ore_batches b WHERE b.status <> 'Imefutwa' ''',
];
