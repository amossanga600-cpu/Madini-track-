"""Unda kampuni ya kwanza na owner. Endesha kwa mazingira salama ya server."""
import getpass
import os
from argon2 import PasswordHasher
from app.db import PostgresRepo

def main():
    dsn = os.environ.get('DATABASE_URL')
    if not dsn:
        raise SystemExit('Weka DATABASE_URL kwenye environment.')
    company = input('Jina la kampuni (LIFANANE na jina ndani ya app): ').strip()
    company_uuid = input('Kitambulisho (UUID) cha kampuni kutoka app: ').strip()
    if len(company_uuid) != 36:
        raise SystemExit('UUID si sahihi; ichukue kwenye app: Usawazishaji > Kitambulisho cha kampuni.')
    username = input('Username ya owner: ').strip()
    password = getpass.getpass('Password (angalau herufi 12): ')
    if len(password) < 12:
        raise SystemExit('Password ni fupi; tumia angalau herufi 12.')
    confirm = getpass.getpass('Rudia password: ')
    if password != confirm:
        raise SystemExit('Password hazifanani.')
    result = PostgresRepo(dsn).bootstrap_company_owner(
        company, username, PasswordHasher().hash(password), company_uuid)
    print('Kampuni na owner vimeundwa.')
    print('company_uuid:', result['company_uuid'])
    print('user_id:', result['user_id'])

if __name__ == '__main__':
    main()
