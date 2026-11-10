// Imezalishwa kutoka docs/migrations/v11_up.sql (test_v11 inalinganisha).
const List<String> kV11Statements = [
  '''ALTER TABLE safety_incidents ADD COLUMN incident_category TEXT CHECK (incident_category IS NULL OR incident_category IN ('Kuanguka kwa miamba/udongo','Mlipuko/baruti','Mashine/vifaa','Kuanguka kutoka juu','Gesi/vumbi/hewa','Moto','Kemikali (zebaki/sianidi)','Umeme','Usafiri/magari','Nyingine'))''',
  '''ALTER TABLE safety_incidents ADD COLUMN root_cause TEXT CHECK (root_cause IS NULL OR root_cause IN ('Haijulikani bado','Kitendo kisicho salama','Hali isiyo salama','Ukosefu wa mafunzo','Kasoro ya vifaa','Hali ya hewa/mazingira','Usimamizi hafifu'))''',
  '''ALTER TABLE safety_incidents ADD COLUMN injury_class TEXT CHECK (injury_class IS NULL OR injury_class IN ('Hakuna','Huduma ya kwanza','Matibabu hospitalini','Siku za kupoteza kazi','Ulemavu wa kudumu','Kifo'))''',
  '''ALTER TABLE safety_incidents ADD COLUMN injured_name TEXT''',
  '''ALTER TABLE safety_incidents ADD COLUMN body_part TEXT''',
  '''ALTER TABLE safety_incidents ADD COLUMN lost_work_days INTEGER NOT NULL DEFAULT 0 CHECK (lost_work_days >= 0)''',
  '''ALTER TABLE safety_incidents ADD COLUMN witnesses TEXT''',
  '''ALTER TABLE safety_incidents ADD COLUMN equipment_involved TEXT''',
  '''ALTER TABLE safety_incidents ADD COLUMN ppe_worn INTEGER CHECK (ppe_worn IS NULL OR ppe_worn IN (0,1))''',
  '''ALTER TABLE safety_incidents ADD COLUMN work_stopped INTEGER NOT NULL DEFAULT 0 CHECK (work_stopped IN (0,1))''',
  '''ALTER TABLE safety_incidents ADD COLUMN reported_to_authority INTEGER NOT NULL DEFAULT 0 CHECK (reported_to_authority IN (0,1))''',
  '''ALTER TABLE safety_incidents ADD COLUMN authority_reference TEXT''',
  '''ALTER TABLE safety_incidents ADD COLUMN corrective_action TEXT''',
  '''ALTER TABLE safety_incidents ADD COLUMN corrective_due TEXT''',
  '''ALTER TABLE safety_incidents ADD COLUMN closed_by TEXT''',
  '''ALTER TABLE safety_incidents ADD COLUMN closed_at TEXT''',
];
