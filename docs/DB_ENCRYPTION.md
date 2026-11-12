# Usimbaji wa database ya simu (v12.1)

Production database ya Android hutumia `sqflite_sqlcipher` (SQLCipher/AES-256).
Ufunguo wa bits 256 huzalishwa kwa `Random.secure()` na huhifadhiwa kupitia
`flutter_secure_storage`, inayotumia Android Keystore kwenye Android. Ufunguo
haujumuishwi kwenye database backup.

## Uhamishaji wa database ya SQLite ya zamani

Wakati app ya SQLCipher inapofungua database ya zamani:

1. Hutambua header ya SQLite isiyosimbwa.
2. Hutengeneza au kusoma ufunguo wa kifaa.
3. Hutumia `sqlcipher_export` kutengeneza faili jipya lililosimbwa.
4. Hulinganisha database version na idadi ya SQLite objects, na kuendesha
   `PRAGMA quick_check`.
5. Huchukua nafasi ya faili la zamani baada ya uhakiki. Faili za muda
   huhifadhiwa/kurudishwa ikiwa hatua ya kubadilisha inakatika.
6. Nakala za migration za zamani zilizo wazi huondolewa baada ya uhamishaji
   uliofaulu, ili zisibaki kama nakala isiyosimbwa ya data nyeti.

Schema ya app inabaki v11; usimbaji hauhitaji kubadilisha `kDbVersion`.
Majaribio ya migration ya schema na ya SQLCipher ni masuala tofauti.

## Ufunguo ukikosekana au kuharibika

App inapaswa kusimama kwa ujumbe wa wazi badala ya kuunda ufunguo mpya kwa
database iliyosimbwa. Usifute app/data wala kujaribu kufungua database kwa
SQLite ya kawaida. Hifadhi kifaa na faili, kisha tumia backup halali au
wasiliana na msimamizi. Android Auto Backup imezimwa kwa makusudi kwa sababu
database na ufunguo wake lazima vihamishwe pamoja kwa utaratibu unaodhibitiwa.

## Backup na mipaka

`.mtbackup` inaweza kusimbwa kwa nenosiri la mtumiaji (AES-256-GCM). UI huruhusu
nenosiri kuachwa wazi, kwa hiyo backup hiyo haitakuwa imesimbwa. Tumia password
manager salama, hifadhi nenosiri tofauti na faili, na jaribu restore kabla ya
kuitegemea. Faili za ushahidi/attachments hazisimbwi na database key.

Tests za `flutter test` hutumia `DatabaseHelper.testFactory` na SQLite FFI ili
kuendesha schema tests kwenye Linux. Zinaangalia key validation na hali ya
fail-closed, lakini **hazithibitishi SQLCipher native engine**, key storage ya
Android, au migration kwenye simu. Kabla ya pilot, thibitisha kwenye Android
halisi: install mpya, upgrade ya database halisi ya zamani, restart baada ya
kuingiliwa kwa migration, database iliyosimbwa bila key, na restore ya
`.mtbackup`.

Key rotation, usimbaji wa attachments, na ushauri wa leseni ya SQLCipher kwa
usambazaji wa kibiashara bado vinahitaji kushughulikiwa.
