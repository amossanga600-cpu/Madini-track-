# Mwongozo wa backup na urejeshaji

## Kutengeneza backup

1. Fungua **Mipangilio** kisha chagua **Backup ya Faili (inapendekezwa)**.
2. Weka nenosiri la angalau herufi 12. Backup mpya husimbwa; hifadhi nenosiri
   kando na faili, kwa mfano kwenye password manager ya shirika.
3. Hifadhi faili la `.mtbackup` kwenye eneo salama. Hifadhi nenosiri kando,
   kwa mfano kwenye password manager ya shirika.
4. Tengeneza backup mara kwa mara na kabla ya restore, kubadilisha simu au
   kufanya matengenezo makubwa.

Njia za backup na restore za Settings zote hutumia faili lililosimbwa. Backup
za zamani zisizosimbwa bado zinaweza kuingizwa kwa ulinganifu, lakini app
haitengenezi tena nakala mpya ya maandishi/JSON isiyosimbwa kupitia UI.

## Kuthibitisha na kurejesha

1. Chagua **Rejesha Backup ya Faili** na faili la `.mtbackup`.
2. Weka nenosiri ikiwa backup ilisimbwa.
3. Soma preview na idadi za rekodi kabla ya kuthibitisha.
4. Restore hubadilisha data ya sasa; app hutengeneza snapshot ya hali ya sasa
   iliyosimbwa kwa nenosiri kabla ya kufanya restore. Kwa backup ya zamani
   isiyosimbwa, weka nenosiri jipya la snapshot.
5. Baada ya restore, hakiki kampuni/mgodi, uzalishaji, batches, mauzo, matumizi
   na ripoti muhimu. Kisha fanya sync pale seva inapopatikana.

Checksum na preview husaidia kugundua faili iliyoharibika; si mbadala wa jaribio
la restore. Mpango wa kuhifadhi nakala nyingi, retention na backup ya server
bado lazima uandaliwe na mmiliki wa huduma.

## Usimbaji wa database ya kifaa

Database ya Android hutumia SQLCipher na ufunguo wa kifaa unaohifadhiwa na
`flutter_secure_storage`. Usifute app/data ikiwa ujumbe unasema ufunguo haupo.
Rejesha kutoka backup halali; usijaribu kufungua database kwa SQLite ya kawaida.
Uhamishaji wa database ya kihistoria na restore lazima zijaribiwe kwenye simu
halisi kabla ya kutegemea data hii kibiashara.

## PostgreSQL ya backend

Mwongozo huu unaeleza utaratibu wa kufanya backup na kurejesha PostgreSQL ya
backend. Hakuna backup ya production wala restore drill iliyotekelezwa katika
mazingira haya; usanidi wa provider, ratiba, retention na uthibitisho wa
urejeshaji ni jukumu la mmiliki wa huduma.

### Sera inayopaswa kuidhinishwa

- Washa automated encrypted backups na point-in-time recovery (PITR) kwa
  PostgreSQL provider, kwenye eneo/region linalokubalika kwa sera ya data.
- Pendekezo la kuanzia tu: daily backups kwa siku 30 na monthly kwa miezi 12;
  mmiliki/ushauri wa kisheria athibitishe retention, gharama na eneo kabla ya
  matumizi halisi. Hii haijasanidiwa na package hii.
- Monitor mafanikio ya backup, muda wa mwisho wa recovery point (RPO), na
  alert kwa backup iliyokosekana au storage kujaa.
- Backup iwe na encryption at rest ya provider; export inayopakuliwa ihifadhiwe
  ikiwa imesimbwa kwa ufunguo ulio nje ya server/database. Dhibiti ufikiaji wa
  encryption key tofauti na ufikiaji wa backup. Usihifadhi password, dump au
  private key ndani ya Git.
- Usichukulie Docker named volume kama backup. `docker compose down -v` inaweza
  kufuta data ya development; usiitumie kwenye data inayohitajika.

### Export ya PostgreSQL kwa nakala inayosimbwa

Tumia host yenye `pg_dump` na `age`, `.pgpass` yenye ruhusa `0600` au
credential helper ya provider, na recipient public key iliyohifadhiwa salama.
Usiweke password kwenye command line, shell history au log. Mfano huu hutiririsha
dump moja kwa moja kwenda kwenye faili ya ciphertext ili kuepuka faili ya dump
wazi ya muda:

```bash
set -o pipefail
pg_dump --host=DB_HOST --port=5432 --username=BACKUP_USER \
  --dbname=madini --format=custom --no-owner --no-acl \
  | age --recipient "$AGE_RECIPIENT" --output madini-$(date -u +%Y%m%dT%H%M%SZ).dump.age
```

Weka nakala kwenye storage tofauti na database na hakikisha exit code ni sifuri,
ukubwa si sifuri, checksum imeandikwa kwenye inventory, na encryption key
inaweza kupatikana kwa watu walioidhinishwa. `AGE_RECIPIENT` si private key;
private identity ihifadhiwe kando. Backup za provider/PITR na export hii ni
taratibu tofauti; chagua na ujaribu angalau moja inayokidhi RPO/RTO iliyoidhinishwa.

### Restore ya majaribio kwenye database mpya

Usijaribu kurejesha juu ya database pekee yenye data ya uzalishaji. Tengeneza
database tupu ya staging yenye PostgreSQL version inayolingana, TLS, nafasi ya
diski ya kutosha na role ya restore. Thibitisha checksum na orodha ya archive,
kisha urejeshe:

```bash
age --decrypt --identity "$AGE_IDENTITY_FILE" madini-backup.dump.age \
  | pg_restore --host=STAGING_DB_HOST --port=5432 \
      --username=RESTORE_USER --dbname=madini_restore \
      --no-owner --no-acl --exit-on-error
```

`AGE_IDENTITY_FILE` ina private key; isome kutoka secret manager/secured mount,
usiweke thamani yake kwenye command. Rejesho liwe kwenye database tofauti.
Baada ya restore:

1. Hakiki `pg_restore --list` kabla ya kurejesha, command exit code na logs.
2. Kagua `schema_migrations`, idadi za `companies`, `users`,
   `sync_records`, `sync_events`, `sync_conflicts` na `audit_log`.
3. Endesha `python -m app.migrate_cli` kwa staging migration DSN ili kuthibitisha
   schema imefika toleo la sasa bila migration isiyotarajiwa.
4. Anzisha API ya staging na `/health/ready`; thibitisha login ya test,
   push/pull ya rekodi za test, company/mine scoping, conflict na audit chain.
5. Linganisha rekodi muhimu na checksum/inventory ya kabla ya backup. Rekodi
   muda wa backup, restore, RPO/RTO iliyopatikana, verifier na makosa.
6. Safisha staging data kwa utaratibu ulioidhinishwa baada ya matokeo kuhifadhiwa.

Usielekeze production API kwenye restore mpaka mmiliki aidhinishe recovery
point, wafanyakazi wasimamishe writes kwa utaratibu, na hatua ya rollback
imejaribiwa. Kwa provider PITR, rejesha kwenye instance mpya kwanza; usi-overwrite
instance ya awali kabla ya kuthibitisha data.

### Hali ya uthibitisho wa server

- Uwezo wa PostgreSQL `pg_dump`/`pg_restore` kwenye data halisi: **PENDING**.
- Encryption ya export kwa public-key age/provider: **PENDING** hadi key na
  staging restore ya mmiliki vitumike.
- Retention, PITR, alerts, RPO/RTO na recovery permissions: **PENDING**.
- Automated PostgreSQL integration tests hazijaribu backup/restore ya dump.
