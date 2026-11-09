# Market Readiness Checklist (hali ya sasa)
✅ imefanyika na kujaribiwa • 🟡 imeandikwa, haijajaribiwa • ❌ haijafanyika • 🔑 inahitaji wewe

- 🟡 Compile + `flutter analyze` + `flutter test` (endesha CI)
- 🟡 APK/AAB (workflow imeandaliwa) • 🔑 release keystore (`docs/RELEASE.md`)
- 🟡 Seva kwenye Supabase • 🔑 DATABASE_URL, JWT_SECRET, domain ya HTTPS
- ✅ Migration v7→v8 kwenye fixture ya kujengwa • ❌ kwenye database halisi / v5, v6
- ✅ Mantiki ya sync ya seva (unit) • 🟡 Sync ya mwisho-hadi-mwisho • 🟡 pull + conflicts
- 🟡 Backup/restore ya faili • 🟡 Ushahidi wa picha • ❌ kupakia picha kwenye Storage
- 🟡 Login ya ndani, majukumu, shahidi aliyethibitishwa
- 🟡 Matumizi: Batch, risiti, idhini • 🟡 Traceability • 🟡 Search yenye pagination • 🟡 Reminder ya madeni
- 🟡 Kiingereza (sehemu: hub, dashboard, mipangilio kuu)
- ✅ Docs: README, user/admin guide, privacy (rasimu), terms (rasimu), API, deployment, pilot plan
- 🔑 Wakili: privacy/terms/uhifadhi wa rekodi • 🔑 Viwango rasmi vya mrabaha/ada • 🔑 Maudhui ya app icon/branding
- ❌ Performance test • ❌ Security review ya nje • ❌ UAT ya watumiaji halisi
- ❌ Ripoti za PDF/Excel zote (PDF/CSV za msingi zipo kwenye Reports) • ❌ Batch merge • ❌ Mashine/opereta/kemikali kwenye processing • ❌ Ukaguzi wa compliance wa TRA/Tume
