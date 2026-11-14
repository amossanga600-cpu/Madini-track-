# Mwongozo wa Msimamizi

## Seva (mara ya kwanza)
1. Unda mradi wa Supabase; endesha `backend/schema.sql`.
2. Weka mazingira: `DATABASE_URL`, `JWT_SECRET` (siri ndefu, nasibu). **Usiweke service-role key kwenye app.**
3. Endesha seva nyuma ya HTTPS (`docs/DEPLOYMENT.md`, `backend/Dockerfile`).
4. Kwenye simu ya mmiliki: **Usawazishaji > Kitambulisho cha kampuni** — nakili jina na UUID.
5. `python bootstrap_owner.py` — ingiza jina la kampuni (LILE LILE la app), UUID hiyo, jina la mtumiaji na nywila (herufi 10+).
6. Kwenye simu: weka anwani ya seva, **Ingia**, **Sawazisha sasa**.

## Watumiaji
- Simu: Mipangilio > Watumiaji wa Kifaa (Mmiliki/Msimamizi anaongeza, anazima, anabadilisha PIN).
- Seva: `POST /v1/admin/users` (angalia `docs/API.md`).

## Majukumu
Mmiliki/Msimamizi: yote. Meneja: yote + kuidhinisha. Mhasibu: fedha, mauzo, ripoti + kuidhinisha. Msimamizi wa Uzalishaji, Opereta, Mtunza Stoo: moduli zao. Mkaguzi/Msomaji: ripoti tu, hawawezi kuandika.

## Viwango vya kodi
**Modules > Viwango vya Kodi na Ada**: ingiza kiwango, tarehe za uhalali na **rejea ya chanzo rasmi**; kinaanza kama draft hadi mtu mwenye mamlaka athibitishe. Mfumo hauna viwango vilivyojengwa ndani.

## Matatizo ya kawaida
- Sync inakataa tukio: angalia kuwa jina la kampuni na UUID kwenye seva vinalingana na vya simu.
- Mgongano: Usawazishaji > Migongano.
- Hitilafu ya database: baada ya upgrade ya sasa, nakala ya kabla ya schema v12 ni `madini_local.db.pre-v12.bak`; hifadhi na hakiki nakala hii kabla ya kuendelea. Ufunguo wa SQLCipher haujajumuishwa kwenye nakala; usifute app/data ikiwa ufunguo haupo.
