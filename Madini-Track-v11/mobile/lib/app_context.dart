import 'package:flutter/foundation.dart';

import 'database_helper.dart';
import 'db_v8.dart';
import 'l10n.dart';
import 'local_auth.dart';
import 'utils.dart';

/// Hubadilishwa kuamsha upya AppRoot (kuingia/kutoka, lugha).
final ValueNotifier<int> appReload = ValueNotifier<int>(0);

/// Hali ya sasa ya app: kampuni, mgodi, mtumiaji na mipangilio.
/// Kila rekodi mpya inaandikwa kwa kampuni na mgodi ulio hai.
class AppCtx {
  static String company = '';
  static String mine = '';
  static String user = '';
  static String deviceId = '';

  // Mipangilio (thamani za chaguo-msingi; mmiliki anaweza kubadilisha).
  // THIBITISHA viwango vya mrabaha/ada na Tume ya Madini / TRA.
  static double royaltyPercent = 6;
  static double inspectionPercent = 1;
  static double minRecoveryPercent = 70;
  static bool requireWitness = true;
  static bool blockOversell = true;
  static bool hasPin = false;
  static bool expenseApproval = false;

  // Kikao cha mtumiaji wa kifaa (angalia local_auth.dart).
  static String userUuid = '';
  static String sessionName = '';
  static String role = 'company_owner';
  static bool localAuthActive = false;

  static bool get canWrite => !localAuthActive || roleCanWrite(role);
  static bool get canApprove => !localAuthActive || roleCanApprove(role);

  static void requireWrite() {
    if (!canWrite) {
      throw AppError(
          'Jukumu lako (${kRoleLabels[role] ?? role}) haliruhusu kuandika rekodi.');
    }
  }

  static bool get ready =>
      company.isNotEmpty && mine.isNotEmpty && user.isNotEmpty;

  static Future<void> load() async {
    final db = DatabaseHelper.instance;
    deviceId = await db.getDeviceId();

    user = (await db.getSetting('user_name')) ?? '';
    if (userUuid.isNotEmpty) user = sessionName;
    L10n.lang = (await db.getSetting('lang')) ?? 'sw';
    expenseApproval = (await db.getSetting('expense_approval') ?? '0') == '1';
    company = (await db.getSetting('active_company')) ?? '';
    mine = (await db.getSetting('active_mine')) ?? '';

    royaltyPercent =
        double.tryParse(await db.getSetting('royalty_percent') ?? '') ?? 6;
    inspectionPercent =
        double.tryParse(await db.getSetting('inspection_percent') ?? '') ?? 1;
    minRecoveryPercent =
        double.tryParse(await db.getSetting('min_recovery_percent') ?? '') ??
            70;
    requireWitness = (await db.getSetting('require_witness') ?? '1') == '1';
    blockOversell = (await db.getSetting('block_oversell') ?? '1') == '1';
    hasPin = (await db.getSetting('pin_hash')) != null ||
        (await db.getSetting('pin_salt')) != null ||
        (await db.getSetting('pin_algorithm')) != null ||
        (await db.getSetting('pin_iterations')) != null;

    final companies = await db.getCompanies();
    if (companies.isEmpty) {
      company = '';
      mine = '';
      return;
    }

    if (!companies.any((c) => c['name'] == company)) {
      company = companies.first['name'] as String;
    }

    final mines = await db.getMines(company);
    if (mines.isEmpty) {
      mine = '';
    } else if (!mines.any((m) => m['name'] == mine)) {
      mine = mines.first['name'] as String;
    }

    await db.setSetting('active_company', company);
    if (mine.isNotEmpty) await db.setSetting('active_mine', mine);

    localAuthActive = await LocalAuth.hasUsers();
    if (!localAuthActive) {
      userUuid = '';
      role = 'company_owner';
    }

    // Viwango vilivyothibitishwa (tax_rates) vina kipaumbele juu ya mipangilio ya mkono.
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final royalty = await db.effectiveRatePercent(company, 'Mrabaha', today);
    if (royalty != null) royaltyPercent = royalty;
    final inspection =
        await db.effectiveRatePercent(company, 'Ada ya ukaguzi', today);
    if (inspection != null) inspectionPercent = inspection;
  }

  static Future<void> setActive(String c, String m) async {
    company = c;
    mine = m;
    await DatabaseHelper.instance.setSetting('active_company', c);
    await DatabaseHelper.instance.setSetting('active_mine', m);
  }
}
