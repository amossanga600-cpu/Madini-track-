# Madini Track API v2.2

API hii ya FastAPI huhifadhi data kwenye PostgreSQL. Flutter hutuma records
kutoka transactional outbox na kuzitambua kuwa zimesawazishwa baada ya ACK ya
seva pekee. Base URL production lazima iwe HTTPS. JWT ni za HS256 na zina
issuer, audience, expiry, device binding na token revocation.

## Health na runtime

- `GET /health` — process liveness.
- `GET /health/ready` — hujibu `200` baada ya muunganisho wa PostgreSQL; vinginevyo `503`.
- Logs za JSON zina `request_id`, path, HTTP status na muda; hazijumuishi headers
  za Authorization au body ya request.

## Login na akaunti

- `POST /v1/auth/login` — `{username,password,device_id,device_name}`.
  `device_id` lazima iwe UUID; nywila huhakikiwa kwa Argon2id.
- `GET /v1/auth/me` — `user_id`, `device_id` na memberships za kampuni.
- `POST /v1/auth/refresh` — huzungusha access token; token ya awali hufutwa
  ndani ya transaction yenye lock ya mtumiaji.
- `POST /v1/auth/logout` — hufuta token ya sasa hadi muda wake wa mwisho.
- `POST /v1/admin/users` — owner/admin huunda akaunti.
  Body: `{username,password,role,company_uuid,mine_uuids?}`. Nywila angalau
  herufi 12. `mine_uuids` ikiachwa, user ana scope ya kampuni nzima; ikitolewa,
  user amefungwa kwenye hiyo orodha ya UUID za migodi (orodha tupu hairuhusu
  mgodi wowote).

Rate limit ya login huhifadhi counters kwenye PostgreSQL, hivyo inashirikiwa na
replicas. Username/IP huhashwa kwa HMAC kabla ya kuhifadhi; counters za zamani
husafishwa. Weka proxy inayosambaza client IP kwa usahihi na uweke pool limits
zinazolingana na connection limit ya PostgreSQL.

## Majukumu na data scope

Backend hukagua role kwa entity na uanachama kwa kila kampuni; kuthibitisha
token pekee hakutoshi. Majukumu: `company_owner`, `company_admin`,
`mine_manager`, `production_supervisor`, `processing_operator`, `storekeeper`,
`accountant`, `auditor`, `read_only`. `mine_id` ya rekodi lazima ilingane na
mgodi uliosawazishwa chini ya kampuni hiyo. User mwenye `mine_uuids` hupokea
na kuandika data ya migodi hiyo pekee. UUID ya kampuni kwenye request hutumika
kama tenant; `company_id` ya ndani ya payload lazima ilingane na kampuni.

## Push, pull na conflicts

- `POST /v1/sync/push` — `{device_id,events:[...]}`, hadi matukio 200.
- `GET /v1/sync/pull?company_uuid=<uuid>&cursor=0&limit=200`; limit 1–500.
- `GET /v1/sync/conflicts?company_uuid=<uuid>`.
- `POST /v1/sync/conflicts/{id}/resolve?company_uuid=<uuid>` body:
  `{"decision":"accept_conflict"}` au `{"decision":"keep_server"}`.

Event ina `idempotency_key`, `entity`, UUID `record_uuid`, UUID `company_uuid`,
`version` na `data`. `data.uuid` lazima ilingane na `record_uuid`; payload ya
rekodi ina kikomo cha 256 KiB. Hifadhi ya rekodi, idempotency outcome na audit
huandikwa transaction moja. PostgreSQL advisory locks huweka delivery ya key
moja mara moja na huweka cursor ya kampuni katika mpangilio wa commit.
Duplicate ya event iliyokuwa conflict hurudisha conflict tena, si ACK ya uongo.
Matokeo: `applied`, `duplicate`, `conflict`, `rejected`.

Conflict ikikubaliwa, server version huwa juu ya server na client versions,
ili merge isirudie version iliyopo. `keep_server` huhifadhi rekodi ya sasa.

## Audit na batch trace

- `GET /v1/audit?company_uuid=<uuid>&cursor=0&limit=200&mine_id=<jina-au-uuid>`
  — audit inahitaji role yenye `audit:read`.
- `GET /v1/batches/{batch_id-au-uuid}/trace?company_uuid=<uuid>` — hutafuta
  batches, movements, production, processing na gold allocation zinazohusiana.

Audit ya server ni append-only kupitia trigger ya PostgreSQL na kila entry
ina hash inayofungamana na entry iliyotangulia kwa kampuni. API hutoa
`chain_valid`; ulinzi huu hutambua mabadiliko, lakini DBA/superuser anaweza
kubadilisha schema/trigger kwa makusudi, kwa hiyo si ushahidi usioweza
kukanushwa bila nakala huru ya hashes.

## Flutter integration

`mobile/lib/sync_service.dart` inatumia routes hizi kwa login, token refresh,
push, pull, conflict list na resolution. Server URL huhifadhiwa kwenye app;
HTTPS inahitajika isipokuwa `localhost`, `127.0.0.1`, `::1` au `10.0.2.2`
kwa majaribio ya kifaa cha ndani. Flutter haipaswi kuwa na `DATABASE_URL`,
`JWT_SECRET` au Supabase service-role key. Live server ya mmiliki na Android
halisi zinahitajika kuthibitisha full device-to-PostgreSQL flow; PostgreSQL
integration tests pekee hazithibitishi hiyo.
