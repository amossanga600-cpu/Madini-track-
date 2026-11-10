const List<String> kV9Statements = [
  '''ALTER TABLE local_users ADD COLUMN pin_algorithm TEXT NOT NULL
     DEFAULT 'pbkdf2-hmac-sha256'
     CHECK (pin_algorithm = 'pbkdf2-hmac-sha256')''',
  'ALTER TABLE audit_log ADD COLUMN actor_uuid TEXT',
  'ALTER TABLE audit_log ADD COLUMN mine_id TEXT',
];
