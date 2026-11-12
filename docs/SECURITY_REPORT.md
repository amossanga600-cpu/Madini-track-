# Ripoti ya Usalama — v12.1 encryption setup

Hii ni maelezo ya implementation ya sasa, si cheti cha usalama. Hakuna
penetration test wala review huru iliyofanyika.

| Eneo | Utekelezaji na ushahidi |
|---|---|
| PIN ya ndani | PBKDF2-HMAC-SHA256, default 600,000 iterations, salt ya random ya 16 bytes, metadata ya algorithm/iterations na ulinganisho wa constant-time. Legacy hashes huboreshwa baada ya PIN sahihi. KDF hukimbia kwenye isolate. |
| Database ya simu | Production database factory hutumia `sqflite_sqlcipher`; ufunguo wa hex wa bits 256 hutengenezwa kwa `Random.secure` na kuhifadhiwa kupitia `flutter_secure_storage` (Android Keystore-backed). Android Auto Backup imezimwa. Migrations za plaintext zinatumia `sqlcipher_export` na huhakikiwa kabla ya kubadilisha faili. |
| Hali ya uthibitisho wa encryption | Unit tests hujaribu key format, kutambua SQLite wazi na fail-closed kwa key iliyokosekana/haribika. Tests za SQLite hutumia FFI/plain SQLite kupitia test factory; hazithibitishi SQLCipher. Uhakiki wa kifaa halisi bado PENDING. |
| Backup | `.mtbackup` ina checksum; inaweza kusimbwa AES-256-GCM kwa PBKDF2. Password ni ya hiari kwa API ya sasa; backup bila password si ya kushirikishwa kwa usalama. |
| Seva | Argon2, JWT, RBAC/tenant checks, idempotency na conflict rules zipo kwenye code. Backend unit tests zimepita; FastAPI/PostgreSQL/Supabase integration haijathibitishwa hapa. |
| Rate limiting | Inafanya kazi ndani ya instance moja tu. Si kinga kamili kwa multi-instance bila shared limiter/gateway. |
| Audit | Backend ina append-only trigger. Audit ya simu ina actor/kampuni/mgodi/muda/operation lakini si append-only wala tamper-evident yenye hash-chain. |
| Transport/tokens | Tokens huhifadhiwa kupitia secure storage. Production lazima itumie HTTPS. Certificate pinning haipo. |

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
RBAC na secrets, backup/restore test, PIN performance benchmark, na legal/privacy
review. Hadi hapo, matumizi ya data halisi ya mgodi ni hatari.
