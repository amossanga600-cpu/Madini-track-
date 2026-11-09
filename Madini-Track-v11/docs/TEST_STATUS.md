# Test status (v11 engineering completion)

- Python SQLite migration suite: 47 tests pass, including synthetic v7-to-v8 and v8-to-v10 schema checks.
- Backend core suite: 16 tests pass, including JWT secret length validation.
- `flutter analyze`, `dart format`, `flutter test`, Android APK build, real v5/v6/v7 database upgrade, physical-device PIN benchmark, backup/restore on device, and Supabase/PostgreSQL tests: **not run here**. Flutter, Dart, Android SDK, and PostgreSQL are unavailable.
- SQLite migration fixtures and MemoryRepo tests do not establish Flutter runtime or PostgreSQL integration correctness.

Run the commands in `TESTING.md` and the staging steps in `CODESPACES_HANDOFF.md` before field use.
