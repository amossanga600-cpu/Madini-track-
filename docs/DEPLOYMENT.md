# Backend deployment — FastAPI + PostgreSQL

Hii ni deployment package ya mradi, si uthibitisho wa deployment kwenye hosting
ya production. Production inahitaji PostgreSQL ya mmiliki, DNS/domain, secrets
na ruhusa za kuendesha Docker. API code hutumia username/Argon2/JWT yake; hii
si Supabase Auth. Supabase inaweza kutumika kama PostgreSQL host.

## 1. Maendeleo ya ndani kwa Docker Compose

Mahitaji: Docker Compose v2 na nafasi ya diski ya PostgreSQL volume.

```bash
cd backend
cp .env.example .env
```

Badilisha `POSTGRES_PASSWORD` iwe random alphanumeric na `JWT_SECRET` iwe
angalau bytes 32. Usihifadhi `.env` kwenye Git wala kuishiriki kwenye chat.
Kisha:

```bash
docker compose --env-file .env up --build -d
docker compose --env-file .env ps
curl http://127.0.0.1:8000/health/ready
```

API ya development inapatikana kwenye `http://127.0.0.1:8000`; HTTP inaruhusiwa
kwa majaribio ya ndani pekee. Flutter Android emulator inaweza kutumia
`http://10.0.2.2:8000`. Migrations `0001_baseline` na `0002` hutumika wakati API
inaanza na PostgreSQL iko tayari. Data huhifadhiwa kwenye named volume
`madini_postgres_data`; usiiondoe kwa `down -v` ikiwa ina data inayohitajika.

Kuangalia logs:

```bash
docker compose --env-file .env logs --tail=100 api
docker compose --env-file .env exec db pg_isready
```

## 2. Production deployment yenye HTTPS

Mahitaji ya mmiliki: Linux host yenye Docker Compose v2, domain inayomilikiwa,
DNS A/AAAA inayoelekea kwenye host, firewall inayoruhusu TCP 80/443, managed
PostgreSQL yenye TLS, backups/PITR, na secret manager. Caddy itapata na
kufanya renewal ya TLS certificate kiotomatiki baada ya DNS/ports kuthibitishwa.

1. Tumia PostgreSQL iliyosimamiwa; `DATABASE_URL` ya API role lazima iwe na
   `sslmode=verify-full` (au `verify-ca` yenye CA trust iliyosanidiwa).
2. Tumia DB roles tofauti: `MIGRATION_DATABASE_URL` iwe ya migration/bootstrap
   tu; `DATABASE_URL` itumie role maalumu `madini_api`, isiwe superuser/table owner,
   isiwe na `CREATE`, `ALTER`, `DROP`, wala `UPDATE/DELETE` kwenye `audit_log`.
   Kwa kuwa schema inawasha RLS bila policies za client, role hii ya server
   inayotumika nyuma ya API lazima iwe na `BYPASSRLS`; ruhusa zake za DML
   zibaki kwenye jedwali/sequences zinazohitajika tu. Tumia
   [`../backend/grant_runtime.sql`](../backend/grant_runtime.sql) baada ya
   migrations. DBA athibitishe `CONNECT`, grants, RLS behavior na TLS. Hii
   ni credential nyeti ya backend pekee—usiweke kwenye Flutter.
3. Nakili template, kisha weka values kupitia secret manager:

   ```bash
   cd backend
   cp .env.production.example .env.production
   chmod 600 .env.production
   ```

   Weka `DATABASE_URL` ya `madini_api`, `MIGRATION_DATABASE_URL`, `JWT_SECRET` (angalau random
   bytes 32), `API_PUBLIC_URL=https://api.example.tz`, na `API_DOMAIN` halisi.
   Usitumie sample values. `API_DOMAIN` lazima ilingane na `API_PUBLIC_URL`.
4. Endesha migrations na huduma nyuma ya TLS proxy:

   ```bash
   docker compose --env-file .env.production \
     -f compose.production.yaml up --build -d
   docker compose --env-file .env.production \
     -f compose.production.yaml ps
   docker compose --env-file .env.production \
     -f compose.production.yaml logs --tail=100 api migrate proxy
   ```

   API huanza na `AUTO_MIGRATE=false`; huduma ya migration hutumia
   `MIGRATION_DATABASE_URL` kabla ya API kuanza. API port hufungwa kwenye
   loopback pekee; Caddy ndiyo entrypoint ya umma. Uvicorn huamini forwarded
   headers kwa sababu API iko kwenye Docker network ya Caddy pekee; usichapishe
   port 8000 moja kwa moja kiweko cha umma wala kuunganisha containers zisizo
   za kuaminika kwenye network hiyo.
5. Thibitisha `https://api.example.tz/health` na `/health/ready`. Hakiki logs za
   JSON na alerts. Health endpoints hazithibitishi authorization wala tenant
   separation; endesha staging integration test.
6. Unda owner kwa kuendesha bootstrap kwa migration credentials kutoka terminal
   salama:

   ```bash
   docker compose --env-file .env.production \
     -f compose.production.yaml run --rm migrate python /app/bootstrap_owner.py
   ```

   Tumia UUID na jina la kampuni kutoka `Usawazishaji > Kitambulisho cha kampuni`.
   Script huuliza password bila kuiweka kwenye command history.
7. Weka URL ya `https://...` kwenye ukurasa wa Usawazishaji wa Flutter, login,
   kisha thibitisha push, pull na conflicts kwa akaunti za kampuni/mgodi tofauti.

Usitumie `backend/schema.sql` kwa mkono baada ya kuanzisha migrations; tumia
runner ya `python -m app.migrate_cli` kwa admin DSN. Migration runner ina
advisory lock na historia `schema_migrations`. Jaribu migration backup/restore
kwanza kwenye staging copy. Migrations production destructive changes
hazijajumuishwa.

## 3. Migrations, backup, monitoring

- Baseline: `backend/schema.sql`; migrations: `backend/migrations/NNNN_*.sql`.
- Local dev: API startup auto-migrate. Production: migration job admin DSN,
  API runtime DSN tofauti.
- PostgreSQL backup/PITR lazima iwe imesanidiwa na mtoa huduma na ijumuishwe
  kwenye alerting. Fuata [`BACKUP_RESTORE_SW.md`](BACKUP_RESTORE_SW.md)
  na jaribu restore kwenye database mpya.
- Tuma structured stdout logs kwa log collector; weka alerts za API 5xx,
  readiness failures, PostgreSQL connection exhaustion, disk/backup/PITR, na
  rate-limit spikes. Mfumo huu hautoi metrics/alerting ya provider moja kwa moja.
- Panga pool limits kwa jumla ya replicas (`instances × DB_POOL_MAX_SIZE`)
  kuwa chini ya DB connection limit, ukiacha nafasi ya migrations/DBA.
- Caddy huhifadhi certificates kwenye volumes zake; linda volumes/backups.
- Hakuna secrets za production au deployment permissions zilizopatikana katika
  session hii; hakuna deployment ya umma iliyofanywa.
