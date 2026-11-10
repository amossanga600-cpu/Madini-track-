# Yaliyobaki (v11)
**Yanahitaji wewe / mazingira:** Supabase (`DATABASE_URL`, `JWT_SECRET`), host ya HTTPS, release keystore, simu za majaribio, UAT, wakili (privacy/terms/uhifadhi), viwango rasmi vya mrabaha/ada.
**Kwanza kabisa:** endesha CI/Codespaces (`flutter pub get && flutter analyze && flutter test`) na urekebishe makosa ya compile yatakayoonekana.
**Bado hayajafanyika kwa code / uthibitisho:**
- Kupakia attachments kwenye Supabase Storage.
- Usimbaji wa database ya SQLite; hash chain ya audit; certificate pinning.
- Mashine/opereta/kemikali kwenye processing; sarafu na deni la mauzo.
- Ripoti kamili za PDF/Excel zenye filters zote; ripoti za compliance (TRA/Tume).
- Kiingereza kamili (sasa ni hub, dashboard, mipangilio kuu, kurasa mpya).
- Migration tests kwa database halisi za v5/v6/v7; performance test; security review ya nje.
- Kuzuia kila kitufe kwa jukumu (sasa: moduli zinazoonekana + uandishi wa msingi kwa read-only).


## V11 — mambo ya lazima kabla ya matumizi halisi
- Flutter/Dart compile, analyzer, widget/database tests na APK install bado hazijathibitishwa.
- `PostgresRepo.process_event` na advisory locks mpya hazijaendeshwa dhidi ya PostgreSQL halisi; lazima zifanyiwe integration/concurrency tests staging.
- Database ya simu bado haijasimbwa. PIN default sasa ni PBKDF2-HMAC-SHA256 600,000; benchmark ya muda/UX kwenye simu dhaifu ya Android bado inahitajika.
- Batch merge imeongezwa kwa SQLite; bado ihakikiwe kwenye Flutter tests, multi-device sync na traceability ya pilot.
- Rate limiter bado ni ya instance moja; tumia shared limiter (kwa mfano Redis) au gateway/WAF yenye rate limit kabla ya deployment ya multi-instance.
- Supabase Storage upload, SQLite encryption, audit hash chain, certificate pinning, Batch merge na vipengele vingine vilivyoorodheshwa hapo juu bado vinahitaji kazi.
