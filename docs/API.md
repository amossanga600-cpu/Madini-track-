# Madini Track API v2.1

Base URL ni anwani ya deployment. HTTPS ni lazima kwenye production.

## Health
- `GET /health` — process health.
- `GET /health/ready` — hujaribu muunganisho wa PostgreSQL.

## Authentication
Toleo hili linatumia username/password iliyohifadhiwa kwenye jedwali la `users`,
Argon2 password hashes na JWT zinazotolewa na FastAPI. HILI SI Supabase Auth
integration bado. Supabase inatumika kama PostgreSQL host; Supabase Auth inaweza
kuunganishwa kama awamu tofauti ikiwa tunataka identity management ya Supabase.
- `POST /v1/auth/login` — `{username,password,device_id,device_name}`; hurudisha bearer token.
- `POST /v1/auth/refresh` — token ya zamani hufutwa na token mpya hutolewa.
- `POST /v1/auth/logout` — hufuta token ya sasa.

Token inafungwa kwa `device_id`; push yenye kifaa tofauti inakataliwa. Login inahitaji username/password; kifaa huandikishwa baada ya uthibitishaji.

## Synchronization
- `POST /v1/sync/push` — `{device_id,events:[...]}`; hadi matukio 200.
- `GET /v1/sync/pull?company_uuid=<uuid>&cursor=0&limit=200`
- `GET /v1/sync/conflicts?company_uuid=<uuid>`
- `POST /v1/sync/conflicts/{id}/resolve?company_uuid=<uuid>` body: `{"decision":"accept_conflict"}` au `{"decision":"keep_server"}`.

Push event: `idempotency_key`, `entity`, `record_uuid`, `company_uuid`, `version`, `data`. `data.uuid` lazima ilingane na `record_uuid`. Payload ya rekodi imewekewa kikomo cha 256 KiB. Matokeo ya push ni `applied`, `duplicate`, `conflict` au `rejected`.

## User administration
- `POST /v1/admin/users` — company owner/admin huunda user kwenye kampuni yake.
  Body: `{username,password,role,company_uuid}`. Password lazima iwe na herufi 12 au zaidi.

Kampuni ya kwanza na owner wake huundwa kwa `python bootstrap_owner.py` baada ya schema kutumika.

## Security notes
- API hii ni server-to-server. Flutter haipaswi kuwa na `DATABASE_URL`, JWT signing secret au Supabase service-role key.
- Supabase anon/authenticated roles hazipewi policy ya kusoma majedwali ya sync; API hutumia database credential ya server.
- Weka HTTPS, secrets manager, backups za PostgreSQL, monitoring na rate limiting ya shared gateway/WAF kabla ya production.
- Rate limiter ya login iliyomo ni ya process moja; deployment yenye replicas lazima iwe na shared Redis/API gateway rate limiting.
- Conflict resolution inaruhusiwa kwa company owner/admin pekee.


## Nyongeza v10
- `GET /v1/auth/me` -> `{user_id, device_id, memberships}`. App inaitumia baada ya login kuthibitisha kuwa UUID ya kampuni ya simu ina uanachama.
- `GET /v1/sync/pull?company_uuid=&cursor=&limit=` -> `{records[], next_cursor, has_more}`. `cursor` ni `seq` ya `sync_records`; `seq` inabadilika kwa **kila** uandishi (pia masahihisho), kwa hiyo rekodi zilizohaririwa zinapakuliwa tena.
- `data.company_id` kwenye payload (jina la kampuni kama app inavyotuma) lazima lilingane na jina lililosajiliwa kwa `company_uuid`, au na uuid yenyewe. Rekodi ya `companies` lazima iwe ya `company_uuid` husika.
- Token default ni saa 12; app inaihuisha (`/v1/auth/refresh`) ikibaki chini ya saa 1.
- Kwenye `bootstrap_owner.py` weka **UUID ya kampuni kutoka app** (Usawazishaji > Kitambulisho cha kampuni) na jina lile lile.
