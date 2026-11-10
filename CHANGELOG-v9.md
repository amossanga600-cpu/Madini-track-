# Madini Track Tanzania — v9 preparation

## Changes in this working update
- Expanded FastAPI authentication with device-bound JWT, token refresh and logout/revocation.
- Added database readiness endpoint.
- Added pull synchronization API with stable cursor pagination.
- Added conflict listing and owner/admin conflict resolution endpoints.
- Added company-scoped user creation and first-company/owner bootstrap utility.
- Added entity-level role permissions and payload tenant/size validation in sync core.
- Added PostgreSQL repository methods for device validation, pull, conflicts, revocation and provisioning.
- Added API and server deployment documentation.
- Changed report export from clipboard-only to shareable PDF and CSV files.
- Added `pdf` and `cross_file` dependencies.
- Removed `|| true` from Dart format CI step so formatting failures are visible.

## Verification performed in this environment
- Backend core unit tests: 10 passed.
- SQLite migration/view tests: 28 passed.
- Python source compilation: passed.
- `flutter analyze`, Dart formatting, Flutter tests, APK build, and PostgreSQL integration: not run here.
