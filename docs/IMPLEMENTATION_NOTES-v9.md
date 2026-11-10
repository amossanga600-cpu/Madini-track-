# Implementation notes — v9 source update

This is an implementation increment on the supplied v8 source, not a claim of production readiness.

## Implemented in this update
- Backend: device-bound JWT claims; access token refresh/revocation; device active-state check; DB readiness.
- Backend: pull endpoint with cursor pagination; conflict listing and explicit owner/admin resolution.
- Backend: company-scoped user provisioning and interactive first-owner bootstrap.
- Backend: entity-level role allowlists, cross-tenant payload guard and 256 KiB event data cap.
- Backend: Postgres repo support for new endpoints.
- Mobile: report PDF/CSV files are generated and passed to Android share sheet rather than copied to clipboard.
- CI: Dart format check no longer masks failure.
- Docs: API, deployment, implementation limits and pending work.

## Tests run in this environment
- `python -m unittest discover -s backend/tests -v`: 10 tests passed.
- `python -m unittest discover -s tools/db_tests -v`: 28 tests passed.
- Python source compile check: passed.
- Migration generator: produced 136 SQL statements.

## Not run
Flutter/Dart are not installed in this environment. Therefore Dart format/analyze/test, Android APK build and device installation were not run.
PostgreSQL/FastAPI runtime integration was not run. Supabase Storage upload is not implemented. Flutter does not yet consume the new pull/conflict endpoints.
