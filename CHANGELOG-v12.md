# Madini Track Tanzania — v12 (schema v11)

## Ajali / usalama ya kiufundi
- Kundi la tukio (miamba, mlipuko, mashine, kuanguka, gesi/vumbi, moto, kemikali, umeme, usafiri).
- Kiwango cha jeraha (hakuna, huduma ya kwanza, hospitali, siku za kupoteza kazi, ulemavu wa kudumu, kifo),
  sehemu ya mwili, aliyejeruhiwa, siku zilizopotea, PPE, kifaa, mashahidi, kazi kusimamishwa.
- Chanzo (root cause), hatua ya kurekebisha + tarehe, ripoti kwa mamlaka + namba ya rejea.
- Ukaguzi wa uthabiti: "Kifo" lazima kiendane na kiwango cha jeraha; majeruhi 0 hawezi kuwa na jeraha;
  siku zilizopotea zinahitaji kiwango sahihi.
- Kufunga tukio kunahitaji chanzo + hatua ya kurekebisha; tukio Kubwa/Kifo pia linahitaji
  ripoti kwa mamlaka (sera ya app, si kauli ya sheria) na angalau picha moja.
- Picha huombwa mara baada ya kuhifadhi tukio.

## Picha (kamera) kwenye sura zaidi
- Wafanyakazi (picha/kitambulisho), Uzalishaji, Uchakataji na Batch sasa zina "Piga picha".
- Aina mpya za ushahidi: Kitambulisho, Eneo la tukio, Majeruhi, Kifaa kilichohusika.

## Uhamisho
- SQLite schema v10 -> v11 ni additive (ALTER TABLE ADD COLUMN); rekodi za zamani hazibadilishwi.
- Hakuna kipengele cha v11 kilichoondolewa.

## Hali ya uthibitisho
Python/SQLite tests zinaendeshwa. Dart haijakompailiwa hapa; CI ya `mobile` ndiyo kipimo.
Kama CI inalalamika formatting, endesha workflow ya "Dart Format Fix".
