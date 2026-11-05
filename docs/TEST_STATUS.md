# Test status for merged package

- ZIP archive integrity: checked successfully during packaging.
- Search SQL statements: syntax-checked against temporary SQLite table definitions.
- SQLite update-trigger pattern: tested with a temporary SQLite database.
- `flutter analyze`, `flutter test`, Android APK build, v5-to-v7 migration on a real v5 database, FIFO sale/reversal and backup/restore: **not run in this packaging environment** because Flutter/Dart SDK and the user's real database are not available here.

The GitHub Actions workflow now runs `flutter analyze`, `flutter test`, and the release APK build after the package is pushed. Review every result before field use.
