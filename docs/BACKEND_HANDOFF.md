# Backend handoff — Madini Track v7

## Local-first contract
- SQLite remains the source of truth while offline.
- Every syncable row has UUID, device_id, updated_at, version, deleted_at and sync_status.
- Integer IDs are local-only; server identity is UUID.
- Preserve audit events and void/cancellation reasons. Do not physically delete operational rows.
- `gold_inventory` and `gold_sale_allocations` are required for auditable FIFO stock movements.

## Server work required
1. Frappe DocTypes for companies, mines, users/roles, production, batches, movements, processing, gold lots, sales, payroll, finance, debts, inventory and audit.
2. Enforce company/mine access on the server; never trust client-provided scope.
3. Idempotent upsert keyed by UUID + device ID; accept version and tombstone metadata.
4. Conflict policy for concurrent edits and immutable audit trail.
5. Auth, token refresh, device registration/revocation and secure transport.
6. Sync cursor, retry/backoff, partial failure reporting and server acknowledgement.
7. Backup, restore and cross-device recovery tests.

## Not claimed
This repository currently contains no production Frappe API or completed sync implementation. `sync_service.dart` is a placeholder.
