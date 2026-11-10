# Madini Track v8 (2.0.0) — mabadiliko kutoka v7

## Database (migration v7 -> v8, additive, ndani ya transaction)
- `PRAGMA foreign_keys=ON` kwa kila connection (`onConfigure`); `sync_attempts` ina FK halisi (CASCADE).
- FK za kimantiki za majedwali ya zamani zinalindwa na triggers `trg_fk_*` (insert) + `integrityReport()`.
- Batch ID iliyobatilishwa inahifadhiwa kwenye `original_batch_id` (UUID hazibadiliki); ID inaweza kutumika tena; UNIQUE haijaondolewa.
- Majedwali mapya: `sync_outbox`, `sync_attempts`, `sync_state`, `attachments`, `tax_rates` (bila viwango vilivyojazwa), `safety_incidents`.
- Transactional Outbox kupitia triggers (rekodi na event ni statement moja, kwa hiyo transaction moja). Backfill ya rekodi za v7 zilizo Pending.
- Views: `v_mass_balance`, `v_batch_costs`; safu `finance_transactions.batch_uuid`.
- **Bug ya v7 iliyorekebishwa**: `batch_movements` haikuwa na `created_at` ingawa kila uhamisho uliiingiza (uhamisho ungeshindwa).
- Meta trigger mpya: kuweka `Synced` hakuongezi version wala kutengeneza event; kuhariri rekodi `Synced` huirudisha `Pending`.
- Nakala ya kinga `madini_local.db.pre-v8.bak` kabla ya upgrade.

## App
- `SyncService` halisi (outbox, retry+backoff, idempotency key, conflict, hakuna ack = si success), token kwenye secure storage.
- Backup ya faili (`.mtbackup`): schema version, SHA-256, AES-256-GCM hiari, preview, snapshot kabla ya restore, share/file picker.
- Moduli mpya: Usalama, Rejista ya Ushahidi (picha kama faili + checksum), Viwango vya Kodi (draft -> verified, chanzo lazima), Ukaguzi wa Data (mass balance, gharama kwa Batch, orphans), Usawazishaji.
- Mrabaha/ada vinasomwa kutoka `tax_rates` zilizothibitishwa; bila hizo mipangilio ya mkono inatumika.
- Release signing kupitia `android/key.properties`.

## Backend
- Frappe stub imeondolewa. FastAPI (`backend/app`): login (Argon2, rate limit, JWT), `/v1/sync/push`, RBAC, tenant isolation, idempotency, conflict -> `sync_conflicts`. Schema: `backend/schema.sql`.
