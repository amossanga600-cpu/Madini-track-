"""Transactional, advisory-locked PostgreSQL migration runner."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "schema.sql"
MIGRATIONS = ROOT / "migrations"


def migrate(connection) -> list[str]:
    applied_now = []
    with connection.transaction():
        connection.execute(
            "SELECT pg_advisory_xact_lock(hashtextextended('madini-schema-migrations', 0))"
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
              version text PRIMARY KEY,
              applied_at timestamptz NOT NULL DEFAULT now()
            )
            """
        )
        applied = {
            row[0] for row in connection.execute(
                "SELECT version FROM schema_migrations"
            ).fetchall()
        }
        if "0001_baseline" not in applied:
            connection.execute(BASELINE.read_text(encoding="utf-8"))
            connection.execute(
                "INSERT INTO schema_migrations(version) VALUES ('0001_baseline')"
            )
            applied_now.append("0001_baseline")

        for path in sorted(MIGRATIONS.glob("[0-9][0-9][0-9][0-9]_*.sql")):
            version = path.name.split("_", maxsplit=1)[0]
            if version in applied:
                continue
            connection.execute(path.read_text(encoding="utf-8"))
            connection.execute(
                "INSERT INTO schema_migrations(version) VALUES (%s)", (version,)
            )
            applied_now.append(version)
    return applied_now
