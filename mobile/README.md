# Madini Track Tanzania — programu ya simu

Programu ya Flutter ya offline-first. Taarifa huhifadhiwa kwenye database ya
kifaa kabla ya kujaribu kusawazisha. Schema ya SQLite ni v11; encryption ya
production hutumia SQLCipher, lakini lazima ithibitishwe kwenye Android halisi.

Kutoka folda hii:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

Tazama `../docs/DB_ENCRYPTION.md`, `../docs/BACKUP_RESTORE_SW.md`,
`../docs/INSTALLATION_SW.md` na `../docs/TEST_STATUS.md`. APK ya debug si ya
uzalishaji; release inahitaji keystore na `android/key.properties`.
