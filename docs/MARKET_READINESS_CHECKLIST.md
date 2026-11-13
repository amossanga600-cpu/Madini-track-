# Market readiness checklist — v12.1 encryption setup

Alama: ✅ imetekelezwa na kipimo husika kimepita • 🟡 ipo kwenye code lakini
uthibitisho wa mazingira halisi unasubiri • ❌ haijatekelezwa • 🔑 inahitaji
mmiliki/mtoa huduma.

- 🟡 Offline-first SQLite na sync outbox; FFI tests zipo, lakini end-to-end ya
  vifaa vingi na seva halisi bado inasubiri.
- 🟡 Batch UUID relationships, device-aware human IDs, split/merge genealogy
  na UUID API trace: SQLite/mobile tests zimepita; staging ya multi-device
  bado inasubiri.
- 🟡 SQLCipher production path, secure key storage na plaintext migration zipo
  kwenye code; Android device verification haijafanyika.
- ✅ Migration v11→v12 ya UUID ni additive; SQLite tests hutumia synthetic
  historical fixture, si database ya mteja.
- 🟡 Flutter analyzer/tests zinaendeshwa kwenye environment yenye SDK; angalia
  `docs/TEST_STATUS.md` kwa matokeo ya session ya mwisho.
- ❌ Debug APK build ya sasa imeshindwa kwa Gradle daemon kuondoka; hakuna APK
  mpya iliyothibitishwa.
- 🔑 Release APK/AAB inahitaji production keystore na owner-approved signing.
- 🟡 `.mtbackup` mpya na snapshot ya restore zinahitaji password na husimbwa;
  SQLCipher/device restore halisi bado lazima zijaribiwe kwenye kifaa.
- 🟡 FastAPI/PostgreSQL local integration tests zimepita (4/4); PostgreSQL
  staging/Supabase, DB grants/RLS behavior ya provider, HTTPS domain na live
  Flutter integration bado vinasubiri.
- 🟡 Backend tests za local container hazithibitishi production deployment,
  provider-specific RLS, backup/restore au load ya PostgreSQL.
- ❌ Upload/download ya attachments, certificate pinning na mobile audit
  hash-chain.
- 🟡 Ripoti za PDF/CSV za msingi zipo; Excel, filters zote na compliance
  reporting bado zinahitaji kazi/uthibitisho.
- 🔑 Security review huru, privacy/legal review, regulatory confirmation,
  accessibility/performance tests na UAT ya mgodi.

**Hitimisho:** hakuna msingi wa kuitangaza app kuwa commercially ready au
kuanza pilot yenye rekodi nyeti hadi vipengele vyote vya lazima hapo juu
vithibitishwe. Tazama [`docs/PENDING.md`](PENDING.md).
