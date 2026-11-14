"""Apply the tracked schema migrations using the configured migration DSN."""

import os

from .db import PostgresRepo


def main():
    dsn = os.environ.get('MIGRATION_DATABASE_URL') or os.environ.get('DATABASE_URL')
    if not dsn:
        raise SystemExit('Weka MIGRATION_DATABASE_URL au DATABASE_URL kwenye environment.')
    repo = PostgresRepo(dsn, min_size=1, max_size=1)
    try:
        repo.open()
        applied = repo.migrate()
        for version in applied:
            print(f'Applied migration {version}')
        if not applied:
            print('Database schema is already current.')
    finally:
        repo.close()


if __name__ == '__main__':
    main()
