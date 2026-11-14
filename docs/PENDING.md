# Yaliyobaki kabla ya pilot na matumizi ya kibiashara

Hali hii inahusu v12.1 encryption setup. Kazi iliyoandikwa au kupita majaribio
ya unit pekee si uthibitisho wa utayari wa uzalishaji.

## Inahitaji kifaa au miundombinu halisi

- Thibitisha SQLCipher kwenye simu halisi: usakinishaji mpya, uhamishaji wa
  database ya zamani, kufunga/kufungua app, interruption/restart, WAL, na
  kukosekana kwa ufunguo.
- Jaribu create/restore ya `.mtbackup` halisi, pamoja na snapshot kabla ya
  restore; import ya backup ya zamani isiyosimbwa ibaki kwenye staging pekee.
- Pima muda wa PIN ya PBKDF2 iterations 600,000 na matumizi ya kumbukumbu
  kwenye simu ya kiwango cha chini.
- Deploy API kwenye PostgreSQL/Supabase ya staging. Local PostgreSQL
  integration tests sasa zimepita, lakini staging haijatumika. Thibitisha
  runtime/migration DB roles, TLS, tenant isolation, RBAC, push/pull, cursors,
  idempotency, conflicts na concurrency.
- Endesha majaribio ya vifaa viwili na ukaguzi wa batch genealogy kutoka
  uzalishaji hadi mauzo.
- Jaribu Flutter dhidi ya API iliyodeployiwa kwa HTTPS; build, install na
  kuzindua APK ya sasa kwenye Android halisi.
- Fanya PostgreSQL backup/restore drill, thibitisha retention, PITR, RPO/RTO,
  alerting na access ya recovery.
- Fanya UAT kwenye mgodi unaoshiriki kwa hiari, bila kutumia rekodi za
  uzalishaji kabla ya kukamilisha restore/recovery tests.
- Pata review ya usalama huru na ushauri wa kitaalamu kuhusu faragha,
  uhifadhi wa data na wajibu wa kisheria nchini Tanzania.

## Kazi/feature gaps zilizobaki

- Upload/download ya attachments kwenye object storage haijakamilika.
- SQLCipher key rotation, usimbaji wa picha/attachments, certificate pinning
  na audit hash-chain ya simu bado hazipo.
- Import ya legacy backup isiyosimbwa bado inaruhusiwa kwa backward
  compatibility; usitumie payload hiyo nje ya kifaa kabla ya kuisimbwa.
- Rate limiter ya login huhifadhi counters PostgreSQL na inaweza kushirikiwa
  na replicas, lakini deployment, proxy client-IP configuration, monitoring na
  rate-limit tests za hosting bado hazijathibitishwa.
- Ripoti kamili za biashara/compliance, Excel, filters zote na reconciliation
  ya kina hazijathibitishwa.
- Baadhi ya maandishi ya Kiingereza bado hayajakamilika; Kiswahili ndicho
  chaguo-msingi, lakini localization yote inahitaji review ya mhariri.
- RBAC, tenant/mine isolation na sync zina PostgreSQL integration tests za
  local container. Review ya endpoints zote na uthibitisho wa staging bado
  unahitajika; UI hiding si mpaka wa usalama.

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
