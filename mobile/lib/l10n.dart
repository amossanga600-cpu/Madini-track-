/// Lugha: Kiswahili (chaguo-msingi) na Kiingereza. Funguo ni maandishi ya Kiswahili.
/// Skrini ambazo hazijatafsiriwa zinabaki Kiswahili (angalia docs/PENDING.md).
class L10n {
  static String lang = 'sw';
  static bool get isEn => lang == 'en';
}

String tr(String sw) => L10n.isEn ? (_en[sw] ?? sw) : sw;

const Map<String, String> _en = {
  'Madini Track Tanzania': 'Madini Track Tanzania',
  'Uzalishaji leo': 'Production today',
  'Dhahabu haijauzwa': 'Unsold gold',
  'Salio la mwezi': 'Monthly balance',
  'Uingizaji wa Uzalishaji': 'Production entry',
  'Hifadhi Rekodi': 'Save record',
  'Rekodi za Karibuni': 'Recent records',
  'Zote': 'All',
  'Tafuta taarifa': 'Search records',
  'Batch ID, eneo, mfanyakazi, mnunuzi...': 'Batch ID, place, worker, buyer...',
  'Onyesha zaidi': 'Show more',
  'Hakuna taarifa zilizopatikana.': 'No records found.',
  'Andika neno au Batch ID kutafuta.': 'Type a word or Batch ID to search.',
  'Madeni yanayohitaji kipaumbele': 'Debts needing attention',
  'Imechelewa': 'Overdue',
  'Mwisho': 'Due',
  'Salio': 'Balance',
  // Hub
  'Uzalishaji': 'Production',
  'Ore & Batch Tracking': 'Ore & Batch Tracking',
  'Processing & Gold Recovery': 'Processing & Gold Recovery',
  'Wafanyakazi & Payroll': 'Workers & Payroll',
  'Fedha': 'Finance',
  'Inventory': 'Inventory',
  'Mauzo': 'Sales',
  'Usalama Mgodini': 'Mine Safety',
  'Rejista ya Ushahidi': 'Evidence Register',
  'Ukaguzi wa Data': 'Data Health',
  'Viwango vya Kodi na Ada': 'Tax & Fee Rates',
  'Usawazishaji (Sync)': 'Synchronization',
  'Reports': 'Reports',
  'Kampuni na Migodi': 'Companies & Mines',
  'Mipangilio': 'Settings',
  'Watumiaji wa Kifaa': 'Device Users',
  'Usalama': 'Safety',
  // Auth / common
  'Jina la mtumiaji': 'Username',
  'Ingia': 'Sign in',
  'Toka': 'Sign out',
  'Ghairi': 'Cancel',
  'Thibitisha': 'Confirm',
  'Thibitisha shahidi': 'Confirm witness',
  'Shahidi': 'Witness',
  'Hifadhi': 'Save',
  'Futa': 'Void',
  'Lugha': 'Language',
  'Idhinisha': 'Approve',
  'Kataa': 'Reject',
  'Inasubiri idhini': 'Pending approval',
  'Imeidhinishwa': 'Approved',
  'Imekataliwa': 'Rejected',
  'Ushahidi': 'Evidence',
  'Chanzo na historia': 'Source & history',
  'Pakua mabadiliko': 'Download changes',
  'Sawazisha sasa': 'Sync now',
  'Migongano': 'Conflicts',
};
