# Madini Track Tanzania — v12.1 encryption setup

Programu ya Flutter ya usimamizi wa shughuli za migodi, inayohifadhi rekodi
kwenye kifaa kwanza na kusawazisha na API inapopatikana. Kiolesura cha simu
kinatumia Kiswahili kama lugha ya msingi.

## Muundo wa mradi

- `mobile/` — programu ya Android, SQLite/SQLCipher, backup na usawazishaji.
- `backend/` — API ya FastAPI na hifadhi ya PostgreSQL.
- `docs/migrations/` — migrations za database ya simu hadi schema v11.
- `tools/db_tests/` — majaribio ya SQLite kwa migrations, constraints na outbox.

Toleo la app na toleo la schema ni vitu tofauti. App kwa sasa ni `2.2.0+6`;
schema ya SQLite ni v11. Usibadilishe schema version bila migration salama.

## Kuendesha na kupima

```sh
cd mobile
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

Majaribio ya backend na SQLite:

```sh
python3 -m pip install -r backend/requirements-dev.txt
PYTHONPATH=backend pytest -q
python3 -m compileall -q backend tools/db_tests
```

Majaribio ya PostgreSQL yanahitaji `TEST_DATABASE_URL` ya database ya majaribio
ya loopback yenye jina linaloishia au lenye `test`; bila hiyo integration tests
zinarukwa kwa makusudi. Usitumie URL/credentials za production. Kuanzisha
backend ya ndani na hatua za production: [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md).
API contract: [`docs/API.md`](docs/API.md).

Hali na mipaka ya uthibitisho imeandikwa katika
[`docs/TEST_STATUS.md`](docs/TEST_STATUS.md), [`docs/PENDING.md`](docs/PENDING.md)
na [`docs/MARKET_READINESS_CHECKLIST.md`](docs/MARKET_READINESS_CHECKLIST.md).

## Usimbaji na usalama

Njia ya database ya Android hutumia `sqflite_sqlcipher`; ufunguo wa database
huhifadhiwa kupitia `flutter_secure_storage`. Database ya zamani isiyosimbwa
inahitajika kuhamishwa kwa SQLCipher kabla ya kufunguliwa. Tazama
[`docs/DB_ENCRYPTION.md`](docs/DB_ENCRYPTION.md) kwa maelezo na hatua za
uthibitishaji. Jaribio la FFI hutumia SQLite isiyosimbwa na **halithibitishi**
usimbaji kwenye Android halisi.

Usiweke `DATABASE_URL`, `JWT_SECRET`, ufunguo wa huduma wa Supabase, au
keystore kwenye Git. Usiweke data halisi ya mgodi kabla ya majaribio ya
urejeshaji, uthibitishaji wa PostgreSQL na ukaguzi wa kifaa.

## APK ya kutolewa

APK ya debug ni ya majaribio. Build ya release inahitaji keystore halali na
`mobile/android/key.properties`; build itashindwa badala ya kutumia debug key
kimyakimya. Maelekezo yako katika [`docs/RELEASE.md`](docs/RELEASE.md).

**Mradi haujathibitishwa kuwa tayari kibiashara.** Majaribio ya kifaa halisi,
PostgreSQL/Supabase, usawazishaji wa vifaa vingi, majaribio ya mgodi na ukaguzi
wa kisheria bado yanahitajika.
