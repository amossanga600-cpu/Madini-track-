# Sera ya Faragha — Madini Track Tanzania (DRAFT)
> Hii ni rasimu ya kiufundi. **Lazima ipitiwe na wakili** (Sheria ya Ulinzi wa Taarifa Binafsi ya Tanzania, 2022) kabla ya kutumika. Si ushauri wa kisheria.

1. **Data tunayokusanya:** rekodi za mgodi (uzalishaji, Batch, usindikaji, mauzo, fedha, stoo), taarifa za wafanyakazi (jina, simu, mshahara, mahudhurio), picha za ushahidi, majina ya watumiaji, kitambulisho cha kifaa, kumbukumbu za ukaguzi.
2. **Mahali data inakaa:** kwanza kwenye simu (SQLite). Ukiunganisha seva, kwenye PostgreSQL ya mwenye mfumo (mfano Supabase) kulingana na mkataba wake.
3. **Nani anaona:** watumiaji wa kampuni husika kulingana na jukumu lao. Kampuni moja haioni data ya nyingine.
4. **PIN na nywila:** PIN za kifaa zinahifadhiwa kama hash ya PBKDF2 yenye chumvi; nywila za seva kwa Argon2. Hazihifadhiwi wazi.
5. **Backup:** faili za backup zinaweza kusimbwa kwa nywila ya mtumiaji; nywila ikipotea faili haifunguki.
6. **Haki zako:** kuomba nakala, marekebisho au ufutaji wa taarifa binafsi kupitia msimamizi wa kampuni. Rekodi za kifedha/ukaguzi zinaweza kuhitajika kisheria kubaki; sera ya uhifadhi inapaswa kuthibitishwa na mshauri wa sheria.
7. **Usalama:** angalia `docs/SECURITY_REPORT.md` kwa hali halisi na mapungufu.
8. **Mawasiliano:** [ jaza jina/anwani ya mwenye mfumo ]
