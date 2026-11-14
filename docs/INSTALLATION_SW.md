# Kusakinisha Madini Track kwenye Android

## Mahitaji

- Simu ya Android inayotumika na nafasi ya kutosha kwa database na backups.
- APK ya majaribio au release iliyotolewa na msimamizi wa mradi.
- PIN ya ndani na utaratibu wa backup uliokubaliwa na kampuni.

## Kusakinisha kwa mtumiaji

1. Pata APK kutoka chanzo rasmi cha kampuni; hakiki checksum iliyotolewa na
   msimamizi.
2. Fungua APK na fuata maelekezo ya Android. Ruhusu usakinishaji kutoka chanzo
   hicho kwa muda unaohitajika, kisha zima ruhusa hiyo tena.
3. Fungua **Madini Track**, sanidi kampuni/mgodi na jina la mtumiaji kulingana
   na mwongozo wa msimamizi.
4. Weka PIN ya kifaa na tengeneza backup yenye nenosiri kabla ya kuingiza data
   halisi.
5. Rekodi taarifa za majaribio kwanza; hakiki batch, ripoti, backup na restore.

APK ya debug ni ya majaribio pekee. Release ya uzalishaji lazima isainiwe kwa
keystore ya kampuni; usisakinishe release isiyothibitishwa. Hadi migration ya
SQLCipher ithibitishwe kwenye simu halisi, tumia data isiyo nyeti tu.

## Kujenga kutoka source

Tumia Flutter SDK inayolingana na `mobile/pubspec.yaml`:

```sh
cd mobile
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

APK ya debug huwekwa kwenye
`mobile/build/app/outputs/flutter-apk/app-debug.apk`. Release inahitaji
`mobile/android/key.properties` na keystore salama nje ya Git; angalia
[`RELEASE.md`](RELEASE.md).
