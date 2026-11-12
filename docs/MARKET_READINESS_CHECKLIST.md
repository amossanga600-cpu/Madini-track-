# Market readiness checklist — v12.1 encryption setup

Alama: ✅ imetekelezwa na kipimo husika kimepita • 🟡 ipo kwenye code lakini
uthibitisho wa mazingira halisi unasubiri • ❌ haijatekelezwa • 🔑 inahitaji
mmiliki/mtoa huduma.

- 🟡 Offline-first SQLite na sync outbox; FFI tests zipo, lakini end-to-end ya
  vifaa vingi na seva halisi bado inasubiri.
- 🟡 Batch UUID, device-aware human IDs, split/merge genealogy na audit:
  SQLite/mobile tests zinapaswa kupita; staging ya multi-device bado inasubiri.
- 🟡 SQLCipher production path, secure key storage na plaintext migration zipo
  kwenye code; Android device verification haijafanyika.
- ✅ Migrations hadi schema v11 ni additive; SQLite tests hutumia synthetic
  historical fixture, si database ya mteja.
- 🟡 Flutter analyzer/tests zinaendeshwa kwenye environment yenye SDK; angalia
  `docs/TEST_STATUS.md` kwa matokeo ya session ya mwisho.
- 🟡 Debug APK inaweza kujengwa; haimaanishi install/launch kwenye kifaa.
- 🔑 Release APK/AAB inahitaji production keystore na owner-approved signing.
- 🟡 Backup ina preview/checksum na restore path; restore halisi na backup
  encrypted lazima zijaribiwe kwenye kifaa.
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
