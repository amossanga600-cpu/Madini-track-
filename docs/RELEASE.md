# Maandalizi ya Android release

APK ya debug ni ya majaribio tu. Build ya release inahitaji keystore ya kampuni
na `mobile/android/key.properties`; Gradle inakataa release ikiwa faili hilo
halipo ili kuzuia debug key kutumika kimyakimya.

1. Tengeneza keystore kwenye mashine salama kwa kutumia `keytool`; weka
   passwords kwa prompt salama, si kwenye shell history.
2. Hifadhi keystore kwenye storage iliyolindwa na tengeneza backup yake
   iliyosimbwa. Kupoteza keystore kunaweza kuzuia kusasisha app iliyosambazwa.
3. Weka `mobile/android/key.properties` nje ya Git, yenye `storeFile`,
   `storePassword`, `keyAlias`, na `keyPassword`. Thibitisha `storeFile`
   inatumia path inayotatuliwa kutoka `mobile/android/`.
4. Hakikisha `key.properties` na keystore havipo kwenye staged changes.
5. Jenga na hakiki:

```sh
cd mobile
flutter pub get
flutter build apk --release
flutter build appbundle --release
```

Kagua package ID, version, certificate fingerprint, APK/AAB checksum, install
na startup kabla ya distribusheni. Usitaje artifact kuwa Play-ready bila
keystore ya production, install test, SQLCipher device validation na required
security/privacy approvals.

## Backend

Tazama [`DEPLOYMENT.md`](DEPLOYMENT.md). Production inahitaji PostgreSQL ya
staging/production, `DATABASE_URL` yenye TLS, `JWT_SECRET` iliyozalishwa na
secret manager, HTTPS reverse proxy/domain, backups/monitoring na shared rate
limiter kwa multi-instance. Usiweke Supabase service-role key kwenye app.
