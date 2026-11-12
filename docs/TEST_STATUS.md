# Hali ya majaribio

Hii inaonyesha matokeo ya session ya sasa pekee; si uthibitisho wa mazingira ya
uzalishaji. Rekebisha namba baada ya kila run mpya.

## Matokeo yaliyotekelezwa

- `flutter pub get`: **PASS**.
- `dart format --output=none --set-exit-if-changed lib test`: **PASS**, faili
  36 zimekaguliwa, 0 zimebadilishwa.
- `flutter analyze`: **PASS**, hakuna issues.
- `flutter test`: **PASS, 45/45**.
- SQLite migration/unit suite (`tools/db_tests`): **PASS, 52/52**.
- Backend unit suite (`backend/tests`): **PASS, 16/16**.
- `python3 -m compileall -q backend tools/db_tests`: **PASS**.
- `git diff --check`: **PASS**.
- Android debug APK: **FAIL**. `compileSdk` ni 36 na Android SDK 36 ipo.
  Gradle daemon inatoweka wakati wa `:app:compileFlutterBuildDebug`; majaribio
  kwa JDK 21, heap ndogo ya Kotlin na compilation ya Kotlin ndani ya process
  hayakutatua tatizo. APK haikutengenezwa. `memory.events` haikuonyesha OOM,
  kwa hiyo chanzo cha daemon kuisha hakijathibitishwa.
- Release APK: **NOT RUN**; production keystore na `key.properties` hazipo.

## Bado haijathibitishwa

- SQLCipher native encryption, Android Keystore na plaintext database migration
  kwenye simu halisi.
- PostgreSQL/Supabase schema, RLS, locking, concurrency na API integration.
- APK install/launch kwenye Android device/emulator; hakuna kifaa kilicho
  attached. Release signing haijasanidiwa.
- Restore ya backup halisi yenye data kubwa, vifaa viwili, field UAT, PIN
  latency ya simu nafuu na legal/privacy review.

SQLite FFI tests ni tests za SQLite wazi. Backend unit tests si ushahidi wa
PostgreSQL. Tazama [`TESTING.md`](TESTING.md) kwa commands na utaratibu wa
uthibitishaji.
