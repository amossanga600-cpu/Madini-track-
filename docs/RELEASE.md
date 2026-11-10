# Release
1. \`keytool -genkey -v -keystore madini.jks -keyalg RSA -keysize 2048 -validity 10000 -alias madini\`
2. Unda \`mobile/android/key.properties\` (HAIPAKIWI GitHub): storeFile, storePassword, keyAlias, keyPassword.
3. \`flutter build apk --release\` / \`flutter build appbundle --release\`.
Bila key.properties, APK inasainiwa kwa debug key (ya majaribio tu).
## Seva
\`cd backend && pip install -r requirements.txt\`; endesha \`schema.sql\` kwenye Supabase; weka JWT_SECRET na DATABASE_URL; \`uvicorn app.main:app\` nyuma ya HTTPS. Unda watumiaji (Argon2 hash) kwa SQL ya admin.
