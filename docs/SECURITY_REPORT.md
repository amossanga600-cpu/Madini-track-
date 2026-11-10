# Ripoti ya Usalama (v11) — hali halisi, si cheti
Hakuna ukaguzi wa nje wala penetration test uliofanyika.

| Eneo | Hali |
|---|---|
| PIN za akaunti na lock gate | PBKDF2-HMAC-SHA256, 600,000 iterations kwa default, chumvi ya random ya 16-byte na ulinganisho wa constant-time. Algorithm/iterations huhifadhiwa kwa akaunti; DB v9 huweka algorithm kwa hash za zamani bila kuzibadilisha. PIN za akaunti za 10,000 iterations na lock gate ya FNV huboreshwa baada tu ya PIN sahihi. KDF hukimbia kwenye isolate ili kuepusha kufunga UI. |
| Mkakati wa vifaa dhaifu | `MADINI_PIN_PBKDF2_ITERATIONS` inaweza kuwekwa 100,000–1,000,000 wakati wa build; default ni 600,000. Hakuna kipimo kwenye simu za kiwango cha chini kilichofanywa; chagua kiwango baada ya benchmark kwenye hardware halisi. |
| Database ya simu | **Haijasimbwa** (SQLite wazi); backup inaweza kusimbwa (AES-256-GCM) |
| Seva | Argon2, JWT, API inakataa kuanza bila `JWT_SECRET` ya angalau bytes 32, rate limit (kwenye kumbukumbu ya instance moja), RBAC, tenant isolation, idempotency, conflict — mantiki imejaribiwa kwa unit tests; **Postgres/FastAPI hazijaendeshwa** |
| RLS | Majedwali yamefungwa kwa anon/authenticated; tenant isolation halisi iko kwenye code ya seva |
| Audit | Seva: append-only kwa trigger. Simu: `writeAudit` huweka actor, kampuni, mgodi, muda na operation kuanzia schema v9. Log ya simu bado si append-only na haina hash chain; si tamper-evident. |
| Token | Secure storage (Android Keystore kupitia flutter_secure_storage); JWT 12h na refresh |
| Mapungufu | Hakuna certificate pinning, hakuna usimbaji wa SQLite, hakuna RBAC ya kila kitufe (jukumu linadhibiti moduli + uandishi wa msingi), RLS haijajaribiwa kwa Postgres halisi |

PIN hash si usimbaji wa database. Usalama wa data iliyohifadhiwa unategemea ulinzi wa kifaa na backup; usihifadhi data halisi ya mgodi kabla ya majaribio ya restore na ukaguzi wa kifaa.
