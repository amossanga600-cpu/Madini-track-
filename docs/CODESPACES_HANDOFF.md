# Madini Track v12 — handoff ya Codespaces

Schema ya simu ni v12. Migrations za v11→v12 zinaunganisha uzalishaji,
movements, processing, gold lots na allocations kwa UUID bila kufuta Batch ID
za kihistoria. Jaribu migration ya database halisi kwenye nakala salama pekee;
usitumie staging au production data bila idhini.

## Flutter na Android

```bash
cd mobile
flutter --version
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

Release build inahitaji keystore na `android/key.properties`; fuata
[`RELEASE.md`](RELEASE.md). Build ya Linux/FFI haithibitishi SQLCipher,
Android Keystore au install ya kifaa. Angalia
[`DB_ENCRYPTION.md`](DB_ENCRYPTION.md) na [`TEST_STATUS.md`](TEST_STATUS.md).

## Python na backend

```bash
python3 -m pip install -r backend/requirements-dev.txt
PYTHONPATH=backend python3 -m pytest -q
python3 -m pytest tools/db_tests -q
python3 -m compileall -q backend tools/db_tests
```

PostgreSQL integration tests zinahitaji `TEST_DATABASE_URL` ya database ya
majaribio ya loopback yenye jina lenye `test`; usitumie production credentials.
Docker Compose ya maendeleo na maelekezo ya production yako
[`DEPLOYMENT.md`](DEPLOYMENT.md). Weka `DATABASE_URL`, `JWT_SECRET` na
migration credentials kwenye secret manager; usiziweke kwenye Git, mobile app
au screenshots.

## Kabla ya pilot

Thibitisha migration kwenye nakala ya database halisi; jaribu SQLCipher,
WAL/recovery, backup restore, APK install, vifaa viwili na push/pull dhidi ya
staging PostgreSQL/HTTPS. Pima PIN KDF kwenye simu dhaifu, fanya security,
privacy/legal review, UAT mgodini, na pata idhini ya mmiliki.
