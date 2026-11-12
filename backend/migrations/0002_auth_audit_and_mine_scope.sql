CREATE TABLE IF NOT EXISTS login_rate_limits (
  bucket text PRIMARY KEY,
  window_started_at timestamptz NOT NULL,
  attempts integer NOT NULL CHECK (attempts > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS mine_memberships (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  mine_uuid text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, company_id, mine_uuid),
  FOREIGN KEY (user_id, company_id) REFERENCES memberships(user_id, company_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_mine_memberships_scope
  ON mine_memberships(company_id, mine_uuid, user_id);
ALTER TABLE memberships
  ADD COLUMN IF NOT EXISTS mine_scope_restricted boolean NOT NULL DEFAULT false;

ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS previous_hash text;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS entry_hash text;
CREATE INDEX IF NOT EXISTS idx_audit_company_cursor ON audit_log(company_id, id);

CREATE INDEX IF NOT EXISTS idx_sync_records_entity_mine
  ON sync_records(company_id, entity, (data->>'name'), (data->>'mine_id'));
CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_mines_company_name_unique
  ON sync_records(company_id, (data->>'name')) WHERE entity='mines';
CREATE INDEX IF NOT EXISTS idx_sync_events_company_received
  ON sync_events(company_id, received_at);
CREATE INDEX IF NOT EXISTS idx_revoked_tokens_expiry
  ON revoked_tokens(expires_at);

ALTER TABLE sync_conflicts DROP CONSTRAINT IF EXISTS sync_conflicts_status_check;
ALTER TABLE sync_conflicts ADD CONSTRAINT sync_conflicts_status_check
  CHECK (status IN ('open', 'accept_conflict', 'keep_server'));
