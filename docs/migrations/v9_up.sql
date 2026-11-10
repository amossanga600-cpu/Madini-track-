-- Madini Track schema v8 -> v9.
-- Existing PIN hashes were already PBKDF2-HMAC-SHA256; the default labels
-- their algorithm without changing hashes, salts, or iteration counts.
ALTER TABLE local_users ADD COLUMN pin_algorithm TEXT NOT NULL
  DEFAULT 'pbkdf2-hmac-sha256'
  CHECK (pin_algorithm = 'pbkdf2-hmac-sha256');
ALTER TABLE audit_log ADD COLUMN actor_uuid TEXT;
ALTER TABLE audit_log ADD COLUMN mine_id TEXT;
