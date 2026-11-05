# Local database notes

- SQLite database: `madini_local.db`.
- Current schema version: 7.
- Version 5 contains core operations plus companies/mines, workers, attendance, payroll payments, finance, debts, inventory, sales and audit log.
- Version 7 adds device identity and sync metadata (`uuid`, `updated_at`, `device_id`, `version`, `deleted_at`) to syncable records, Batch lineage fields, gold FIFO lots and sale allocations.
- Migration is additive and retains local integer IDs and existing UUIDs.
- `voided` remains the business-facing cancellation flag for compatibility; `deleted_at` is its sync tombstone.
- Keep database backups before every app upgrade. Never clear app storage while operational data exists.
