# Hali ya majaribio

Matokeo haya yanahusu source tree ya v12 yenye migration ya SQLite v12 ya
Batch UUID, API genealogy kwa UUID na backup iliyosimbwa kwa nenosiri.

## Yaliyothibitishwa

- Flutter analyzer: **PASS**, hakuna masuala.
- `flutter test`: **PASS, 48 tests**.
- `python3 -m pytest tools/db_tests backend/tests -q`: **73 passed, 4 skipped**.
  Skips ni PostgreSQL integration tests zinazoihitaji `TEST_DATABASE_URL`.
  SQLite migration v12, UUID backfill, integrity triggers, trace queries,
  orphan handling na backend unit tests vimejumuishwa.
- PostgreSQL 16 API integration suite: **PASS, 4 tests** dhidi ya container
  mpya ya muda iliyofungwa loopback na kuhifadhi data kwenye tmpfs, ikiwa ni
  pamoja na migrations, JWT, rate limiting, company/mine isolation,
  idempotency, conflicts, pull pagination, audit, UUID Batch genealogy na
  concurrent duplicate delivery. Container ilisimamishwa baada ya majaribio;
  hakuna volume iliyotumika.
- `python3 -m compileall -q backend tools/db_tests`: **PASS**.
- Dart formatter check: **PASS**, hakuna faili zilizohitaji kubadilishwa.
- `git diff --check`: **PASS**.
- SQLite migration v11→v12 fixture: records za kihistoria zimehifadhiwa,
  mahusiano yanayoweza kutambuliwa yamejazwa kwa UUID, na mahusiano yasiyotambulika
  yanaandikwa kwenye `batch_traceability_issues`.
- Backup envelope tests: **PASS** kwa AES-256-GCM/PBKDF2 inspection, wrong
  password rejection na sharti la password mpya yenye angalau herufi 12.

Onyo moja la Starlette/TestClient kuhusu `httpx` lilionekana kwenye backend
suite; halikufeli jaribio.

## Haijathibitishwa / release blockers

- Debug APK: build ilishindwa kwenye `:app:mergeDebugNativeLibs` kwa sababu
  diski ilijaa (`No space left on device`); hakuna APK mpya iliyothibitishwa.
- Release APK: haijajengwa; production keystore/signing secrets hazipo.
- SQLCipher native engine, Android Keystore, WAL migration/recovery na restore
  ya database halisi **hazijathibitishwa kwenye kifaa cha Android**. FFI tests
  hazithibitishi SQLCipher.
- Migration ya SQLite ilijaribiwa kwenye synthetic historical fixture, si
  database ya uzalishaji ya mmiliki.
- Full Flutter-to-deployed-backend, multi-device field sync, mine pilot, HTTPS
  domain/certificate, production PostgreSQL provider, load/backup restore drill,
  legal/privacy review na regulatory confirmation: **PENDING**.
- Backup/restore ya PostgreSQL dump halisi: **PENDING**.

API/PostgreSQL integration tests dhidi ya database ya majaribio si ushahidi wa
deployment, data ya uzalishaji, Supabase permissions au uendeshaji wa simu halisi.
Project haijathibitishwa kuwa tayari kibiashara; mmiliki lazima akamilishe
hatua zilizo kwenye [`PENDING.md`](PENDING.md) na
[`MARKET_READINESS_CHECKLIST.md`](MARKET_READINESS_CHECKLIST.md).
