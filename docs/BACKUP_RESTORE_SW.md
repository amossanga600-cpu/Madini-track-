# Mwongozo wa backup na urejeshaji

## Kutengeneza backup

1. Fungua **Mipangilio** kisha chagua **Backup ya Faili (inapendekezwa)**.
2. Weka nenosiri la backup. Nenosiri ni la hiari kwenye app, lakini backup bila
   nenosiri haijasimbwa na haipaswi kutumwa kwa mtu mwingine.
3. Hifadhi faili la `.mtbackup` kwenye eneo salama. Hifadhi nenosiri kando,
   kwa mfano kwenye password manager ya shirika.
4. Tengeneza backup mara kwa mara na kabla ya restore, kubadilisha simu au
   kufanya matengenezo makubwa.

App pia ina backup ya maandishi na kurejesha kwa kubandika JSON. Njia hiyo si
njia inayopendekezwa kwa faili kubwa na maandishi yanaweza kuwa na data nyeti.

## Kuthibitisha na kurejesha

1. Chagua **Rejesha Backup ya Faili** na faili la `.mtbackup`.
2. Weka nenosiri ikiwa backup ilisimbwa.
3. Soma preview na idadi za rekodi kabla ya kuthibitisha.
4. Restore hubadilisha data ya sasa; app hutengeneza snapshot ya hali ya sasa
   kabla ya kufanya restore.
5. Baada ya restore, hakiki kampuni/mgodi, uzalishaji, batches, mauzo, matumizi
   na ripoti muhimu. Kisha fanya sync pale seva inapopatikana.

Checksum na preview husaidia kugundua faili iliyoharibika; si mbadala wa jaribio
la restore. Mpango wa kuhifadhi nakala nyingi, retention na backup ya server
bado lazima uandaliwe na mmiliki wa huduma.

## Usimbaji wa database ya kifaa

Database ya Android hutumia SQLCipher na ufunguo wa kifaa unaohifadhiwa na
`flutter_secure_storage`. Usifute app/data ikiwa ujumbe unasema ufunguo haupo.
Rejesha kutoka backup halali; usijaribu kufungua database kwa SQLite ya kawaida.
Uhamishaji wa database ya kihistoria na restore lazima zijaribiwe kwenye simu
halisi kabla ya kutegemea data hii kibiashara.
