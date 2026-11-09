# Ripoti ya majaribio (v11) — uaminifu kwanza

## Yaliyoendeshwa HAPA
| Test | Command | Matokeo |
|---|---|---|
| Migration v7→v10, Batch reuse, merge mass-balance ledger, outbox, FK triggers, constraints, views, pull-flag, traceability, madeni, local_users, approval (47) | `python3 -m unittest discover -s tools/db_tests` | 47 zimepita |
| Backend core: idempotency, tenant isolation (jina/uuid), RBAC, conflict, pull cursor yenye masahihisho, validation, rate limit, JWT secret validation (16) | `python3 -m unittest discover -s backend/tests` | 16 zimepita |
| PIN algorithm/audit metadata v8→v9 huhifadhi hash/salt/iterations; v10 mass-balance view | Jaribio la SQLite kwenye `tools/db_tests/test_v10.py` | Limepita |

## HAIJAENDESHWA (hakuna Flutter/Dart/Postgres/Android kwenye mazingira ya ujenzi)
- `flutter analyze`, `dart format`, `flutter test` — `mobile/test/` imeandikwa lakini **haijaendeshwa** hapa.
- **Code yote ya Dart haijakompailiwa** (schema v10 na mobile v11): makosa ya compile yanawezekana. Endesha CI/Codespaces kwanza.
- APK/AAB, usakinishaji, performance, UAT.
- FastAPI app, PostgresRepo, schema.sql dhidi ya Postgres; Argon2/JWT.
- Migration v5/v6→v7 (hakuna fixtures halisi). Fixture ya v7 ni **synthetic**, imetoka SQL ya `database_helper.dart`.
- Pull/sync mwisho-hadi-mwisho kati ya app na seva halisi.
- PIN KDF performance kwenye simu dhaifu ya Android haijapimwa. Default ni 600,000 iterations; jaribu UX na muda wa login kabla ya kuchagua config ya pilot.

## Mkakati wa PIN
Default ya production ni `MADINI_PIN_PBKDF2_ITERATIONS=600000`. Ikiwa benchmark kwenye simu halisi inaonyesha kuchelewa kusikokubalika, build inaweza kuweka thamani iliyo wazi kati ya 100,000 na 1,000,000, kwa mfano:
`flutter test --dart-define=MADINI_PIN_PBKDF2_ITERATIONS=200000`
Hii ni mfano wa kusanidi majaribio tu, si pendekezo la kupunguza thamani bila threat-model na kipimo kwenye vifaa lengwa. KDF inaendeshwa kwenye isolate; muda wa login bado hutegemea uwezo wa kifaa.
