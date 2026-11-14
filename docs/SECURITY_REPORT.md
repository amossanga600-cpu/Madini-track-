# Ripoti ya Usalama — v12.1 encryption setup

Hii ni maelezo ya implementation ya sasa, si cheti cha usalama. Hakuna
penetration test wala review huru iliyofanyika.

| Eneo | Utekelezaji na ushahidi |
|---|---|
| PIN ya ndani | PBKDF2-HMAC-SHA256, default 600,000 iterations, salt ya random ya 16 bytes, metadata ya algorithm/iterations na ulinganisho wa constant-time. Legacy hashes huboreshwa baada ya PIN sahihi. KDF hukimbia kwenye isolate. |
| Database ya simu | Production database factory hutumia `sqflite_sqlcipher`; ufunguo wa hex wa bits 256 hutengenezwa kwa `Random.secure` na kuhifadhiwa kupitia `flutter_secure_storage` (Android Keystore-backed). Android Auto Backup imezimwa. Migrations za plaintext hutumia `sqlcipher_export`; nakala wazi huhifadhiwa hadi database ya mwisho ifunguke na ipite `quick_check` na `foreign_key_check`. SQLCipher native bado haijathibitishwa kwenye kifaa. |
| Hali ya uthibitisho wa encryption | Unit tests hujaribu key format, kutambua SQLite wazi na fail-closed kwa key iliyokosekana/haribika. Tests za SQLite hutumia FFI/plain SQLite kupitia test factory; hazithibitishi SQLCipher. Uhakiki wa kifaa halisi bado PENDING. |
| Backup | `.mtbackup` mpya na snapshot kabla ya restore zinahitaji password ya angalau herufi 12 na husimbwa AES-256-GCM kwa PBKDF2-HMAC-SHA256/600,000 iterations. Import ya backup ya zamani isiyosimbwa bado inaruhusiwa kwa ulinganifu; restore yake huunda snapshot iliyosimbwa. |
| Seva | Argon2, JWT lifecycle/revocation, RBAC, company/mine checks, idempotency na conflict rules zipo. FastAPI/PostgreSQL local integration tests zimepita 4/4; Supabase/staging bado haijathibitishwa. |
| Rate limiting | Login attempts huhesabiwa atomically kwenye PostgreSQL, hivyo replicas zinaweza kushiriki counter. Proxy client-IP, production abuse behavior na hosting monitoring bado havijajaribiwa. |
| Audit | Backend ina append-only trigger. Audit ya simu ina actor/kampuni/mgodi/muda/operation lakini si append-only wala tamper-evident yenye hash-chain. |
| DB privileges/RLS | Schema huwasha RLS bila client policies. API lazima itumie DB credential ya server pekee yenye `BYPASSRLS`, lakini bila DDL na bila audit update/delete; migration credential itengwe. `backend/grant_runtime.sql` ina grants zilizopendekezwa; role hizi hazijathibitishwa kwenye provider halisi. |
| Transport/tokens | Tokens huhifadhiwa kupitia secure storage. Production config ina Caddy TLS na API hukataa production URL isiyo HTTPS. HTTPS deployment halisi haijafanywa; certificate pinning haipo. |

## Hatari na tahadhari

- Kupotea kwa ufunguo wa SQLCipher bila backup yenye password kunaweza
  kusababisha data isiweze kusomeka. App inapaswa kusimama badala ya kuunda
  ufunguo mpya kwa database iliyosimbwa.
- Usifute app/data wala kujaribu kurekebisha database kwa mikono ikiwa key
  haipo; hifadhi faili na wasiliana na msimamizi.
- Mchakato wa kuhamisha database ya zamani na usomaji wa SQLCipher lazima
  uthibitishwe kwa kifaa halisi na nakala halisi ya database kabla ya pilot.
- SQLCipher haijathibitishwa kama ilivyo kwenye binary ya release, wala
  leseni yake ya matumizi ya kibiashara haijapitiwa.
- PIN hashing si sawa na usimbaji wa database; usalama wa key, backups na
  kifaa lazima vithibitishwe pamoja.

## Kabla ya production

Fanya Android device test, PostgreSQL staging/security tests, review huru ya
RBAC na grants, backup/restore test, PIN performance benchmark, na legal/privacy
review. API credential ya `BYPASSRLS` ni secret server-side; usiweke Flutter.
Hadi hapo, matumizi ya data halisi ya mgodi ni hatari.
