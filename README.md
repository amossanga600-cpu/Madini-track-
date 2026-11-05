# Madini Track Tanzania — Offline-first Mine Operations

**Toleo la pamoja: UI/Moduli kamili + SQLite schema v7 + maandalizi ya sync.**

Madini Track inalenga kuondoa daftari la karatasi kwenye shughuli za mgodi. Simu huhifadhi rekodi kwanza kwenye SQLite; app inaweza kurekodi kazi bila intaneti. Kiolesura ni Kiswahili na kinaunga mkono kampuni na migodi mingi kwa uteuzi wa kampuni/mgodi ndani ya app.

## Vilivyomo kwenye toleo hili

- Dashibodi ya kampuni/mgodi, PIN gate ya ndani na kubadili context.
- Uzalishaji: uzito, magunia, eneo, zamu, grade, shahidi na Batch inayoundwa ndani ya transaction moja.
- Batch: orodha, historia, uhamisho kamili au wa sehemu; uhamisho wa sehemu unatengeneza Batch mtoto na kuhifadhi uzito wa chanzo.
- Usindikaji: kupunguza salio la Batch, kurekodi gold recovery, tailings, gharama, mbinu na shahidi.
- Gold inventory: kila uchakataji huunda lot; mauzo hutumia FIFO, kwa gramu na purity, na yanarudisha lot balances yakighairiwa.
- Mauzo: mnunuzi, leseni, bei kwa gramu ya dhahabu safi, mrabaha/ada, malipo, audit na muamala wa fedha unaohusishwa.
- Wafanyakazi, mahudhurio, malipo ya wafanyakazi, fedha/gharama, madeni, stoo na movement za stoo.
- Kampuni na migodi, PIN lock ya ndani, mipangilio, ripoti, search na backup/restore pamoja na CSV export.
- Audit log na void/cancel yenye sababu; rekodi hazifutwi kimya kimya.
- Global search ya ndani inayoheshimu kampuni na mgodi uliochaguliwa.
- SQLite schema v7: UUID, device ID, updated_at, version, deleted_at, sync status, metadata ya Batch na pending sync bundle foundations.
- Migration v5 → v7 ni additive; inahifadhi UUID na data zilizokuwepo, na hujaza metadata ya sync kwa rekodi za zamani.

## Muhimu: mipaka ya utekelezaji

Hili ni **toleo la mobile/offline**, si mfumo uliokamilika wa uzalishaji wa kibiashara wala backend-ready. Vipengele vifuatavyo bado vinahitaji utekelezaji na uthibitisho:

- Hakuna Frappe API hai, authentication ya server, sync retry/idempotency, conflict resolution au multi-device sync.
- PIN ni lock ya ndani ya simu; si uthibitisho wa utambulisho salama wa server. Ruhusa za kampuni/mgodi lazima zilindwe server-side.
- Payroll bado inahitaji uthibitisho wa kanuni za overtime, makato ya kisheria, payslip na reconciliation ya mahudhurio.
- Stock inarekodi items na movements, lakini lazima ipitiwe kwa tests za ledger, valuation na reversal kabla ya kutegemewa kwa hesabu za kifedha.
- Backup/restore na exports zinahitaji majaribio ya kurejesha faili halisi, si kuangalia tu kuwa kitufe kinaonekana.
- Gold sale calculation na viwango vya mrabaha/ada vinahitaji kuhakikiwa dhidi ya kanuni za sasa za Tanzania na mtaalamu husika.
- Hakuna camera attachment pipeline/QR workflow kamili iliyothibitishwa.
- Ripoti ni za ndani ya app; hazijathibitishwa kama audited statutory reports.

## Kuanza kwenye Codespaces

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```

Kwa APK, tumia GitHub Actions workflow `.github/workflows/build-apk.yml` ikiwa Codespace haina Android SDK.

## Acceptance tests kabla ya pilot

1. Nakili database halisi ya v5, ifungue kwenye app v7, hakikisha idadi na UUID za rekodi zote za zamani zimehifadhiwa.
2. Rekodi uzalishaji; hakikisha Batch moja tu inaundwa na duplicate Batch ID inakataliwa bila rekodi nusu.
3. Hamisha 30 kg kati ya 100 kg; chanzo kibaki 70 kg, mtoto 30 kg na historia iwe sahihi.
4. Chakata 20 kg; Batch ipungue 20 kg na gold lot iundwe; zuia uzito unaozidi salio.
5. Uza dhahabu chini ya salio; hakikisha FIFO allocation, purity/bei na miamala ya fedha ni sahihi.
6. Ghairi mauzo; FIFO lots zirudishiwe gramu sahihi mara moja tu.
7. Jaribu kughairi processing baada ya kuuza lot yake; mfumo ukatae. Kabla ya mauzo, batch weight irudishwe na lot izimwe.
8. Jaribu void ya production baada ya movement/processing; mfumo ukatae.
9. Funga na fungua app; rekodi za offline zibaki.
10. Jaribu backup/restore kwenye database tofauti na linganisha idadi na jumla.
11. `flutter analyze` na `flutter test` zipite bila errors; kisha fanya test kwenye Android device.

**Usiingize data halisi ya mgodi kabla ya kukamilisha acceptance tests na backup/restore.** Wakati wa pilot, endelea na daftari sambamba hadi takwimu zithibitishwe.
