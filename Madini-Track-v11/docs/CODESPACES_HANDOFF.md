# Madini Track v11 — Codespaces handoff

Fanya kazi kwenye `Madini-Track-v11/`; SQLite schema ya sasa ni v10. Hifadhi nakala ya database halisi kabla ya kujaribu migration. Flutter/Dart, Postgres staging, na kifaa halisi lazima vithibitishwe kabla ya pilot.

## 1. Flutter
```bash
cd Madini-Track-v11/mobile
flutter --version
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release
```

Rekebisha compile/analyzer/test failures kabla ya kujaribu backend live.

## 2. APK ya majaribio
```bash
flutter build apk --release
```
APK: `mobile/build/app/outputs/flutter-apk/app-release.apk`. Bila release keystore, signing inaweza kuwa debug key na APK si ya Play Store.

## 3. Python/backend
```bash
cd Madini-Track-v11
python -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt
python -m unittest discover -s backend/tests -v
python -m unittest discover -s tools/db_tests -v
```

## 4. PostgreSQL/Supabase staging
```bash
cd Madini-Track-v11
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/schema.sql
cd backend
uvicorn app.main:app --host 0.0.0.0 --port 8000
```
- Tumia project ya staging, si production.
- Weka `DATABASE_URL` na `JWT_SECRET` kama Codespaces Secrets/environment; usiziweke kwenye ZIP, Git, Flutter au screenshots.
- `JWT_SECRET` iwe random na ya siri (angalau 32 bytes).
- Hakiki `/health/ready`, login, push duplicate, conflict, pull pagination na resolve conflict.
- Jaribu concurrency ya duplicate idempotency key na pull cursor kwa Postgres halisi.

## 5. Kabla ya pilot
Jaribu upgrade kwenye nakala za database halisi v5/v6/v7/v8/v9; hakiki backup/restore; fanya majaribio ya simu mbili na offline, hasa merge/mass-balance; pima muda wa PIN KDF kwenye simu dhaifu; fanya security review na UAT mgodini.
