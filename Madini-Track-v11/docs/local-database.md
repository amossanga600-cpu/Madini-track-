# Local database notes

- SQLite database: `madini_local.db`.
- Current schema version: 10.
- Version 5 contains core operations plus companies/mines, workers, attendance, payroll payments, finance, debts, inventory, sales and audit log.
- Version 7 adds device identity and sync metadata (`uuid`, `updated_at`, `device_id`, `version`, `deleted_at`) to syncable records, Batch lineage fields, gold FIFO lots and sale allocations.
- Version 8 adds the sync outbox, attachment metadata, tax rates, safety records, and historical Batch ID archival; see `migrations/v8_up.sql`.
- Version 9 labels existing local-account PIN hashes and adds actor UUID/mine fields for new audit records; it does not rewrite existing hashes or delete historical audit rows; see `migrations/v9_up.sql`.
- Version 10 updates the mass-balance view to use source-to-child movement quantities, including merged Batches; see `migrations/v10_up.sql`.
- Migration is additive and retains local integer IDs and existing UUIDs.
- `voided` remains the business-facing cancellation flag for compatibility; `deleted_at` is its sync tombstone.
- Keep database backups before every app upgrade. Never clear app storage while operational data exists.
