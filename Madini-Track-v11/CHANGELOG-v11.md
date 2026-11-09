# Madini Track Tanzania — v11

## Maboresho dhidi ya v10
- SQLite schema v9 huongeza metadata ya algorithm ya PIN kwa migration additive; hash, salt na iterations za akaunti zilizopo hubaki bila kubadilishwa.
- PIN za kifaa na akaunti mpya hutumia PBKDF2-HMAC-SHA256 rounds 600,000 kwa default, chumvi ya kriptografia, uthibitisho wa constant-time na derivation kwenye isolate; PIN za zamani huboreshwa baada ya uthibitisho uliofanikiwa.
- Kiwango cha iterations kinaweza kusanidiwa kwa `MADINI_PIN_PBKDF2_ITERATIONS` (100,000–1,000,000); kipimo kwenye simu za Android za kiwango cha chini bado kinahitajika.
- `writeAudit` huhifadhi `actor_uuid` na `mine_id` kwa matukio mapya. Historia iliyopo hubaki salama; audit ya ndani bado si append-only wala hash-chained.
- API sasa hukataa kuanza bila `JWT_SECRET` ya angalau bytes 32 na bila `DATABASE_URL`.
- SQLite schema v10 huunganisha ledger ya Batch movement na mass-balance report. Merge ya vyanzo viwili au zaidi hufanyika atomically, huhifadhi source records na movement/audit history, na huonyesha kila chanzo kwenye traceability.
- PostgreSQL push sasa ina njia ya `process_event` inayofanya ukaguzi wa idempotency, uamuzi wa version, uandishi wa rekodi/conflict, event na audit ndani ya transaction moja.
- Advisory locks za PostgreSQL zinalinda delivery ya event inayofanana na kupanga commit za stream ya kampuni ili cursor-based pull isiruke commit iliyochelewa.
- Conflict resolution inatumia lock ileile ya stream ya kampuni.
- CI sasa hukagua formatting bila kubadilisha mafaili kimyakimya.
- Mobile package version imepandishwa kuwa 2.2.0+6.

## Hali ya uthibitisho
Majaribio ya Python/SQLite na backend core yanaendeshwa kwenye mazingira ya sasa. PostgresRepo mpya haijajaribiwa dhidi ya PostgreSQL halisi; Flutter/Dart haijakompailiwa hapa. Hivyo v11 ni candidate ya kuingia Codespaces, si tamko la market-ready.
