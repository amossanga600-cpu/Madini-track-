# Mwongozo wa majaribio

## Flutter

```sh
cd mobile
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

`sqflite_common_ffi` huendesha majaribio ya SQLite bila Android. Hii
haithibitishi SQLCipher native engine. Usibadilishe test assertions ili
kuficha hitilafu. Release build inahitaji keystore iliyowekwa; haipaswi kutumia
debug signing.

## Python/SQLite/backend

Kutoka repository root:

```sh
python3 -m unittest discover -s tools/db_tests
python3 -m unittest discover -s backend/tests
python3 -m compileall -q backend tools/db_tests
git diff --check
```

SQLite tests hutumia fixtures za synthetic zinazotokana na schema ya repo;
haziwakilishi database zote za zamani za wateja. Backend unit tests hutumia
repo/test doubles pale ilivyoandikwa na **hazithibitishi PostgreSQL halisi**.

## Staging inayohitajika

Tumia PostgreSQL/Supabase tofauti na production. Endesha schema, tests za
auth/RBAC/tenant isolation, simultaneous push, retry/idempotency, pull cursor,
conflict resolution, deletion/void propagation na restore. Rekodi matokeo na
toleo la schema. Usitumie secrets za staging kwenye terminal transcript au
Git.

## Kifaa cha Android kinachohitajika

Kwenye simu halisi thibitisha:

1. SQLCipher clean install na header/faili isiyosomeka kama SQLite wazi.
2. Upgrade ya database iliyopo, interruption/restart na uhifadhi wa rekodi.
3. Missing-key fail-closed na restore kutoka `.mtbackup`.
4. Offline create → force-close → reopen → online push/pull.
5. Batch ID zinazofanana kwa mfululizo kwenye vifaa viwili na UUID tofauti.
6. KDF latency, startup, long lists, kamera, backup/restore na navigation.

Andika kila kipimo kama PASS/FAIL/NOT RUN. Usihitimishe kuwa encryption,
PostgreSQL au multi-device sync imethibitishwa kwa sababu ya unit tests pekee.
