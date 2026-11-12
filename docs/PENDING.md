# Yaliyobaki kabla ya pilot na matumizi ya kibiashara

Hali hii inahusu v12.1 encryption setup. Kazi iliyoandikwa au kupita majaribio
ya unit pekee si uthibitisho wa utayari wa uzalishaji.

## Inahitaji kifaa au miundombinu halisi

- Thibitisha SQLCipher kwenye simu halisi: usakinishaji mpya, uhamishaji wa
  database ya zamani, kufunga/kufungua app, na kukosekana kwa ufunguo.
- Jaribu restore kutoka `.mtbackup` halisi; backup inaweza kuwa wazi ikiwa
  mtumiaji hakuweka nenosiri.
- Pima muda wa PIN ya PBKDF2 iterations 600,000 na matumizi ya kumbukumbu
  kwenye simu ya kiwango cha chini.
- Tekeleza API na schema dhidi ya PostgreSQL/Supabase ya staging. Thibitisha
  tenant isolation, RBAC, push/pull, cursors, idempotency, conflicts na writes
  zinazofanyika kwa wakati mmoja.
- Endesha majaribio ya vifaa viwili na ukaguzi wa batch genealogy kutoka
  uzalishaji hadi mauzo.
- Fanya UAT kwenye mgodi unaoshiriki kwa hiari, bila kutumia rekodi za
  uzalishaji kabla ya kukamilisha restore/recovery tests.
- Pata review ya usalama huru na ushauri wa kitaalamu kuhusu faragha,
  uhifadhi wa data na wajibu wa kisheria nchini Tanzania.

## Kazi/feature gaps zilizobaki

- Upload/download ya attachments kwenye object storage haijakamilika.
- SQLCipher key rotation, usimbaji wa picha/attachments, certificate pinning
  na audit hash-chain ya simu bado hazipo.
- Backup ya faili bado inaruhusu payload isiyosimbwa ikiwa nenosiri
  halijawekwa. Weka nenosiri lenye nguvu kabla ya kuhamisha backup.
- Rate limiter ya backend ni ya instance moja; multi-instance deployment
  inahitaji limiter ya pamoja au gateway/WAF.
- Ripoti kamili za biashara/compliance, Excel, filters zote na reconciliation
  ya kina hazijathibitishwa.
- Baadhi ya maandishi ya Kiingereza bado hayajakamilika; Kiswahili ndicho
  chaguo-msingi, lakini localization yote inahitaji review ya mhariri.
- RBAC ya backend ina unit tests; hakikisho la kila endpoint linahitaji
  integration tests za PostgreSQL. UI hiding si mpaka wa usalama.

## Mmiliki/matayarisho ya kutolewa

- Weka secrets za staging/production kwenye secret manager, tumia HTTPS na
  domain inayomilikiwa na mradi.
- Toa keystore ya production nje ya Git, sanidi
  `mobile/android/key.properties`, na weka nakala salama ya keystore.
- Thibitisha leseni na masharti ya SQLCipher kwa usambazaji wa kibiashara.
- Thibitisha viwango vya mrabaha/ada kwa vyanzo rasmi; app haitoi kauli ya
  kisheria kuhusu viwango hivyo.
- Panga msaada, uhifadhi wa backups na utaratibu wa tukio/urejeshaji.

Mradi **haujatangazwa kuwa commercially ready**. Tazama
[`docs/TEST_STATUS.md`](TEST_STATUS.md) na
[`docs/MARKET_READINESS_CHECKLIST.md`](MARKET_READINESS_CHECKLIST.md).
