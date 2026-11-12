# Madini Track Tanzania — v12.1 encryption setup

v12.1 is an engineering setup revision; the app version stays `2.2.0+6` and the
SQLite schema stays at v11.

- Production database access now uses SQLCipher; the encryption key is stored
  through `flutter_secure_storage` and the Android app disables OS Auto Backup.
- Legacy plaintext SQLite files are exported to an encrypted database and
  checked before replacing the original. Missing/invalid keys fail closed.
- The database helper supports an injected SQLite FFI factory for tests. FFI
  tests do not establish native SQLCipher or Android Keystore behavior.
- Generated production/split/merge Batch IDs include a stable device tag;
  UUID remains the primary cross-device record identity. Production creation
  checks the Batch ID against both production and ore Batch tables.
- Release signing now requires the configured production keystore and cannot
  silently fall back to the debug key.
- Documentation now distinguishes code implementation from device, PostgreSQL,
  restore, legal and pilot verification.

This revision does not change application versioning or database schema
versioning. SQLCipher device verification and all external production checks
remain pending; see `docs/TEST_STATUS.md` and `docs/PENDING.md`.
