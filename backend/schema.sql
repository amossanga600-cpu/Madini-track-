-- Schema ya seva (Supabase PostgreSQL). Endesha kwa SQL editor / psql kwa akaunti ya admin.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE companies (id uuid PRIMARY KEY, name text NOT NULL, created_at timestamptz DEFAULT now());
CREATE TABLE users (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), username text UNIQUE NOT NULL,
  password_hash text NOT NULL, active boolean NOT NULL DEFAULT true, created_at timestamptz DEFAULT now());
CREATE TABLE memberships (user_id uuid REFERENCES users(id), company_id uuid REFERENCES companies(id),
  role text NOT NULL CHECK (role IN ('company_owner','company_admin','mine_manager','production_supervisor',
  'processing_operator','storekeeper','accountant','auditor','read_only')), PRIMARY KEY (user_id, company_id));
CREATE TABLE devices (user_id uuid REFERENCES users(id), device_id text, name text,
  first_seen timestamptz DEFAULT now(), last_seen timestamptz DEFAULT now(), PRIMARY KEY (user_id, device_id));
CREATE SEQUENCE IF NOT EXISTS sync_records_seq;
CREATE TABLE sync_records (seq bigint NOT NULL DEFAULT nextval('sync_records_seq') UNIQUE, company_id uuid NOT NULL REFERENCES companies(id), entity text NOT NULL,
  record_uuid text NOT NULL, version int NOT NULL, data jsonb NOT NULL, device_id text NOT NULL,
  updated_by uuid REFERENCES users(id), updated_at timestamptz DEFAULT now(),
  PRIMARY KEY (company_id, entity, record_uuid));
CREATE TABLE sync_events (device_id text NOT NULL, idempotency_key text NOT NULL, company_id uuid NOT NULL,
  outcome text NOT NULL, user_id uuid, received_at timestamptz DEFAULT now(), PRIMARY KEY (device_id, idempotency_key));
CREATE TABLE sync_conflicts (id bigserial PRIMARY KEY, company_id uuid NOT NULL, entity text NOT NULL,
  record_uuid text NOT NULL, device_id text NOT NULL, version int NOT NULL, data jsonb NOT NULL,
  status text NOT NULL DEFAULT 'open', created_at timestamptz DEFAULT now(), resolved_by uuid REFERENCES users(id), resolved_at timestamptz);
CREATE TABLE audit_log (id bigserial PRIMARY KEY, company_id uuid, user_id uuid, action text NOT NULL,
  entity text, record_uuid text, detail jsonb, created_at timestamptz DEFAULT now());
-- Audit append-only
CREATE FUNCTION audit_immutable() RETURNS trigger AS $$ BEGIN RAISE EXCEPTION 'audit_log ni append-only'; END $$ LANGUAGE plpgsql;
CREATE TRIGGER audit_no_change BEFORE UPDATE OR DELETE ON audit_log FOR EACH ROW EXECUTE FUNCTION audit_immutable();
-- RLS: funga majedwali kwa roles za Supabase (anon/authenticated). Seva inatumia role ya DB ya server pekee.
ALTER TABLE sync_records ENABLE ROW LEVEL SECURITY; ALTER TABLE sync_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_conflicts ENABLE ROW LEVEL SECURITY; ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY; ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices ENABLE ROW LEVEL SECURITY; ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
-- Hakuna policy kwa anon/authenticated => hawaoni chochote. Tenant isolation halisi inafanywa na seva (SyncEngine).

-- Device/token controls and stable pull cursor.
ALTER TABLE devices ADD COLUMN IF NOT EXISTS revoked_at timestamptz;
CREATE TABLE IF NOT EXISTS revoked_tokens (
  jti text PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id),
  expires_at timestamptz NOT NULL, revoked_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE revoked_tokens ENABLE ROW LEVEL SECURITY;
-- Indexes for pull, conflict queue and membership checks.
CREATE INDEX IF NOT EXISTS idx_sync_records_pull ON sync_records(company_id,seq);
CREATE INDEX IF NOT EXISTS idx_conflicts_open ON sync_conflicts(company_id,id) WHERE status='open';
CREATE INDEX IF NOT EXISTS idx_memberships_company_role ON memberships(company_id,role);
