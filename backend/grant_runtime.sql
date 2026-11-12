-- Run as the database owner after migrations and after creating madini_api.
-- Create the login role securely with psql's interactive \password command:
--   CREATE ROLE madini_api LOGIN BYPASSRLS;
--   \password madini_api
-- Keep this password only in the backend secret manager.
-- The API is the trusted tenant boundary: never give these credentials to a
-- mobile client. Use a dedicated database for this service.

GRANT USAGE ON SCHEMA public TO madini_api;

GRANT SELECT ON companies TO madini_api;
GRANT SELECT, INSERT, UPDATE ON memberships TO madini_api;
GRANT SELECT, INSERT ON mine_memberships TO madini_api;
GRANT SELECT, INSERT, UPDATE ON users TO madini_api;
GRANT SELECT, INSERT, UPDATE ON devices TO madini_api;
GRANT SELECT, INSERT, UPDATE ON sync_records TO madini_api;
GRANT SELECT, INSERT ON sync_events TO madini_api;
GRANT SELECT, INSERT, UPDATE ON sync_conflicts TO madini_api;
GRANT SELECT, INSERT ON audit_log TO madini_api;
GRANT SELECT, INSERT, DELETE ON revoked_tokens TO madini_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON login_rate_limits TO madini_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO madini_api;

REVOKE UPDATE, DELETE, TRUNCATE ON audit_log FROM madini_api;
REVOKE CREATE ON SCHEMA public FROM madini_api;
