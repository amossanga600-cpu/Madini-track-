# Madini Track Tanzania (v11)
Mfumo wa Flutter (offline-first, SQLite) + FastAPI/Supabase kwa usimamizi wa migodi.
- `mobile/` programu ya Android • `backend/` seva • `docs/migrations/` migrations v8–v10 • `tools/` generator + majaribio ya SQLite.
- Hali halisi: `docs/TESTING.md` (kilichojaribiwa na kisichojaribiwa) na `docs/PENDING.md`.
- **Hii si bidhaa iliyothibitishwa kuwa market-ready.** Dart haijakompailiwa wala APK kujengwa bado.
## Kujenga APK (Codespaces)
`cd mobile && flutter pub get && flutter analyze && flutter test && flutter build apk --release`
APK: `mobile/build/app/outputs/flutter-apk/app-release.apk`. Au push kwenye GitHub: workflow ya Actions inatoa APK kama artifact.


## v9 preparation update
Angalia `CHANGELOG-v9.md`, `docs/API.md`, `docs/DEPLOYMENT.md` na `docs/PENDING.md`.
Backend endpoints sasa zinajumuisha login/logout/refresh, push/pull, conflict review,
user provisioning na readiness check. Ripoti za simu zina export PDF/CSV kama mafaili
yanayoweza kushirikiwa. Haya bado yanahitaji Flutter build na Postgres staging tests;
usiweke secrets kwenye mobile app au repository.


## v11 handoff
- Angalia `CHANGELOG-v11.md` na `docs/CODESPACES_HANDOFF.md`.
- PostgreSQL push idempotency na pull-stream ordering zimeimarishwa kwa transaction/advisory locks; bado zinahitaji staging PostgreSQL verification.
- CI inakagua Dart formatting bila kurekebisha files yenyewe.
- Schema ya simu v10 huongeza metadata ya PIN, actor/mine kwenye audit na mass-balance ledger ya movements kupitia migrations za nyongeza. PIN mpya hutumia PBKDF2-HMAC-SHA256 rounds 600,000 kwa default na huweza kusanidiwa kwa `MADINI_PIN_PBKDF2_ITERATIONS`; thibitisha kasi kwenye simu dhaifu kabla ya pilot.
- Batch merge huweka vyanzo, uzito, movements, audit na Batch mpya ndani ya transaction moja; historia ya kila chanzo inaonekana kwenye traceability.
