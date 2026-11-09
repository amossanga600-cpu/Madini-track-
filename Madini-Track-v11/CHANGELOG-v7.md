# Madini Track — Merged v7

- Preserved the complete multi-module application as the UI/business-module base.
- Upgraded the local SQLite schema to v7 using additive migration from the supplied v5 schema.
- Added persistent device identity, updated timestamps, version numbers and soft-delete sync tombstones.
- Added Batch source/parent UUID lineage and original-weight tracking.
- Added recovered-gold inventory lots and FIFO sale allocations; voiding a sale restores the exact lots.
- Blocked voiding processing when its own recovered-gold lot has active sale allocations.
- Added a scoped global search across production, Batch, movement, processing, workers, sales, finance and inventory.
- Added a pending-sync bundle export contract for a future backend adapter.
- Added global search scoped to the selected company and mine.
- Kept backup/restore and CSV exports; included gold lots and allocations in backup data.
- No live backend sync, server authentication or multi-device conflict handling is claimed.
