# Kutatua matatizo ya kawaida

## App inasema ufunguo wa database haupo au si sahihi

Usifute app/data, usifungue database kwa SQLite ya kawaida, na usisakinishe upya
kwa majaribio. Hifadhi kifaa na faili zilizoathirika. Tumia backup ya
`.mtbackup` na nenosiri lake au wasiliana na msimamizi. Backup isiyosimbwa
inaweza kurejeshwa tu ikiwa faili haijaharibika.

## Rekodi zinasubiri kusawazishwa

Rekodi huhifadhiwa kwenye kifaa kwanza. Hakiki mtandao, API base URL na akaunti
ya mtumiaji; jaribu **Sawazisha sasa**. Usirudie kuingiza rekodi ileile kwa
sababu tu ya kutopatikana kwa mtandao. Hali ya sync ya app/server ihakikiwe kabla
ya kuchukulia rekodi kuwa zimefika seva.

## Sync inakataa kampuni au kifaa

Thibitisha kuwa akaunti ina membership ya UUID ya kampuni hiyo na device
registration haijazimwa. Usibadilishe company UUID kwenye request kwa mkono.
Msimamizi aangalie logi za server bila kuchapisha token au taarifa nyeti.

## Batch ID imekataliwa

Batch ID inapaswa kuwa ya kipekee ndani ya kampuni. Tumia kitufe cha kutengeneza
ID; ID hiyo inajumuisha tarehe na tag ya kifaa. UUID ndiyo utambulisho mkuu
kwenye sync. Usifute rekodi ya zamani ili kutumia ID tena; tumia workflow ya
void yenye sababu.

## Backup haifunguki au restore imeshindwa

Hakikisha faili ni `.mtbackup` halisi na nenosiri ni sahihi. Usibadilishe
faili kwa editor. Restore inahitaji nafasi ya kutosha na huchukua muda kwa
database kubwa. Snapshot ya sasa hutengenezwa kabla ya restore; ikiwa hitilafu
itatokea, usiondoe faili lolote kabla ya kuwasiliana na msimamizi.

## Ripoti au matumizi hayaendani

Hakiki kipindi, kampuni, mgodi na hali ya rekodi (void/imeidhinishwa). Hifadhi
nakala ya ripoti na UUID za rekodi zinazohusika; usirekebishe database moja kwa
moja. Marekebisho ya uzito/hesabu yafanyike kwa utaratibu wa audit na sababu.

## Hitilafu ya kusakinisha au kujenga

Tumia Flutter/Dart zinazokidhi mipaka ya `mobile/pubspec.yaml`, kisha endesha
`flutter pub get`. Kwa Android, weka `ANDROID_HOME`/`ANDROID_SDK_ROOT`, Java
inayoungwa mkono na Android SDK platforms zinazohitajika. Release build
haitafanikiwa bila keystore/configuration sahihi.
