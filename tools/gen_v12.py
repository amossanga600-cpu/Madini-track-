#!/usr/bin/env python3
"""Generate the Dart v12 statements from the reviewed SQLite migration SQL."""

import pathlib
import sqlite3

root = pathlib.Path(__file__).resolve().parents[1]
source = root / "docs/migrations/v12_up.sql"
target = root / "mobile/lib/migration_v12_sql.dart"

statements = []
current = ""
for line in source.read_text().splitlines():
    if line.lstrip().startswith("--"):
        continue
    current += line + "\n"
    if sqlite3.complete_statement(current):
        statement = current.strip().removesuffix(";").strip()
        if statement:
            statements.append(statement)
        current = ""
if current.strip():
    raise SystemExit("Incomplete SQL statement in v12 migration.")

body = ",\n".join(f'  r"""{statement}"""' for statement in statements)
target.write_text(
    "// Generated from docs/migrations/v12_up.sql by tools/gen_v12.py.\n"
    f"const List<String> kV12Statements = [\n{body},\n];\n"
)
