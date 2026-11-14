# Usimbaji wa database ya simu (schema v12)

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
5. Huhifadhi database ya awali kama `.plain-old` wakati faili jipya linawekwa.
   WAL/SHM hushughulikiwa baada ya checkpoint iliyofanikiwa.
6. App huendesha migration ya schema, hufungua database ya mwisho, na hukagua
   `quick_check` pamoja na `foreign_key_check`. Nakala ya wazi haiondolewi kabla
   ya hatua hizi kufanikiwa; ikishindwa, startup inasimama na nakala hubaki.
7. Baada ya uhakiki wa database iliyofunguliwa kufanikiwa, nakala wazi za
   migration za zamani huondolewa; nakala za pre-upgrade zilizosimbwa huhifadhiwa.

Schema ya app ni v12 kwa migration ya UUID za Batch. Usimbaji wenyewe hauhitaji
kubadilisha `kDbVersion`. Majaribio ya migration ya schema na ya SQLCipher ni
masuala tofauti.

## Ufunguo ukikosekana au kuharibika

App inapaswa kusimama kwa ujumbe wa wazi badala ya kuunda ufunguo mpya kwa
database iliyosimbwa. Usifute app/data wala kujaribu kufungua database kwa
SQLite ya kawaida. Hifadhi kifaa na faili, kisha tumia backup halali au
wasiliana na msimamizi. Android Auto Backup imezimwa kwa makusudi kwa sababu
database na ufunguo wake lazima vihamishwe pamoja kwa utaratibu unaodhibitiwa.

## Backup na mipaka

`.mtbackup` mpya inahitaji nywila ya angalau herufi 12 na husimbwa kwa
AES-256-GCM, yenye ufunguo wa PBKDF2-HMAC-SHA256 wa raundi 600,000 na salt ya
kila backup. Snapshot ya hali ya sasa kabla ya restore pia inasimbwa; kwa
backup ya zamani isiyosimbwa, app huomba nywila mpya ya snapshot. Backup za
zamani zisizosimbwa bado zinaweza kuingizwa kwa ulinganifu, lakini hazipaswi
kusambazwa wala kuhifadhiwa bila ulinzi. Tumia password manager salama na
hifadhi nywila tofauti na faili. Faili za ushahidi/attachments hazisimbwi na
database key.

Tests za `flutter test` hutumia `DatabaseHelper.testFactory` na SQLite FFI ili
kuendesha schema tests kwenye Linux. Zinaangalia key validation na hali ya
fail-closed, lakini **hazithibitishi SQLCipher native engine**, key storage ya
Android, au migration kwenye simu. Kabla ya pilot, thibitisha kwenye Android
halisi: install mpya, upgrade ya database halisi ya zamani, interruption katika
hatua za export/rename/open, restart baada ya kila interruption, database
iliyokosekana key, backup ya SQLite yenye WAL, na restore ya `.mtbackup`.

Key rotation, usimbaji wa attachments, na ushauri wa leseni ya SQLCipher kwa
usambazaji wa kibiashara bado vinahitaji kushughulikiwa.
