import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:sqflite/sqflite.dart';

import 'app_context.dart';
import 'database_helper.dart';
import 'db_modules.dart';
import 'migration_v8_sql.dart';
import 'utils.dart';

const List<String> kTaxRateTypes = [
  'Mrabaha',
  'Ada ya ukaguzi',
  'Ada ya kibali',
  'Kodi nyingine'
];
const List<String> kSafetyTypes = [
  'Ajali',
  'Tukio hatarishi',
  'Near miss',
  'Ukaguzi wa usalama',
  'PPE'
];
const List<String> kSafetySeverities = ['Ndogo', 'Wastani', 'Kubwa', 'Kifo'];
const List<String> kFollowUp = ['Wazi', 'Inaendelea', 'Imefungwa'];
const List<String> kIncidentCategories = [
  'Kuanguka kwa miamba/udongo',
  'Mlipuko/baruti',
  'Mashine/vifaa',
  'Kuanguka kutoka juu',
  'Gesi/vumbi/hewa',
  'Moto',
  'Kemikali (zebaki/sianidi)',
  'Umeme',
  'Usafiri/magari',
  'Nyingine',
];
const List<String> kRootCauses = [
  'Haijulikani bado',
  'Kitendo kisicho salama',
  'Hali isiyo salama',
  'Ukosefu wa mafunzo',
  'Kasoro ya vifaa',
  'Hali ya hewa/mazingira',
  'Usimamizi hafifu',
];
const List<String> kInjuryClasses = [
  'Hakuna',
  'Huduma ya kwanza',
  'Matibabu hospitalini',
  'Siku za kupoteza kazi',
  'Ulemavu wa kudumu',
  'Kifo',
];
const List<String> kLostTimeClasses = [
  'Siku za kupoteza kazi',
  'Ulemavu wa kudumu',
  'Kifo',
];
const List<String> kEvidenceKinds = [
  'Risiti',
  'Scale ticket',
  'Batch seal',
  'Uhamishaji',
  'Gold lot',
  'Mauzo',
  'Malipo',
  'Ukaguzi',
  'Usalama',
  'Kitambulisho',
  'Eneo la tukio',
  'Majeruhi',
  'Kifaa kilichohusika',
  'Picha'
];

extension V8Db on DatabaseHelper {
  // ------------------------------------------------------------------ Uadilifu
  /// Ripoti ya rekodi zisizo na mzazi (orphans) na hali ya foreign keys.
  Future<Map<String, int>> integrityReport() async {
    final db = await database;
    final out = <String, int>{};
    for (final e in kOrphanChecks.entries) {
      out[e.key] = Sqflite.firstIntValue(await db.rawQuery(e.value)) ?? 0;
    }
    final fk = await db.rawQuery('PRAGMA foreign_keys');
    out['foreign_keys_on'] = intv(fk.first.values.first);
    final violations = await db.rawQuery('PRAGMA foreign_key_check');
    out['foreign_key_violations'] = violations.length;
    return out;
  }

  // ------------------------------------------------------------------ Tax rates
  /// Kiwango kilichothibitishwa kinachotumika kwa tarehe fulani; null ikiwa hakuna.
  Future<double?> effectiveRatePercent(
      String company, String type, String date) async {
    final db = await database;
    final rows = await db.query(
      'tax_rates',
      columns: ['percent'],
      where:
          "company_id = ? AND rate_type = ? AND status = 'verified' AND deleted_at IS NULL "
          'AND effective_from <= ? AND (effective_to IS NULL OR effective_to >= ?)',
      whereArgs: [company, type, date, date],
      orderBy: 'effective_from DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : dbl(rows.first['percent']);
  }

  Future<List<Map<String, dynamic>>> getTaxRates() async {
    final db = await database;
    return db.query('tax_rates',
        where: 'company_id = ? AND deleted_at IS NULL',
        whereArgs: [AppCtx.company],
        orderBy: 'rate_type ASC, effective_from DESC');
  }

  /// Kiwango kinaingia kama `draft`; kinatumika baada ya kuthibitishwa na mtu mwenye mamlaka.
  Future<void> addTaxRate({
    required String type,
    required double percent,
    required String effectiveFrom,
    String? effectiveTo,
    required String sourceReference,
    String? sourceUrl,
  }) async {
    if (percent < 0 || percent > 100) {
      throw AppError('Asilimia lazima iwe kati ya 0 na 100.');
    }
    if (sourceReference.trim().isEmpty) {
      throw AppError(
          'Weka rejea ya chanzo rasmi (mfano: namba ya kanuni/tangazo la serikali).');
    }
    if (effectiveTo != null &&
        effectiveTo.isNotEmpty &&
        effectiveTo.compareTo(effectiveFrom) < 0) {
      throw AppError('Tarehe ya mwisho haiwezi kuwa kabla ya ya kuanza.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final m = meta();
      await txn.insert('tax_rates', {
        ...m,
        'company_id': AppCtx.company,
        'rate_type': type,
        'mineral': 'Dhahabu',
        'percent': percent,
        'effective_from': effectiveFrom,
        'effective_to':
            (effectiveTo == null || effectiveTo.isEmpty) ? null : effectiveTo,
        'source_reference': sourceReference.trim(),
        'source_url': (sourceUrl == null || sourceUrl.trim().isEmpty)
            ? null
            : sourceUrl.trim(),
        'status': 'draft',
      });
      await writeAudit(txn,
          entity: 'tax_rate',
          entityUuid: m['uuid'] as String,
          action: 'Kimeongezwa (draft)',
          detail:
              '$type ${fmtNum(percent)}% kuanzia $effectiveFrom. Chanzo: ${sourceReference.trim()}');
    });
  }

  Future<void> verifyTaxRate(String uuid) async {
    final db = await database;
    await db.transaction((txn) async {
      final n = await txn.update(
        'tax_rates',
        {
          'status': 'verified',
          'verified_by': AppCtx.user,
          'verified_at': nowIso(),
          'sync_status': 'Pending'
        },
        where: "uuid = ? AND status = 'draft'",
        whereArgs: [uuid],
      );
      if (n == 0) throw AppError('Kiwango hakipo au tayari kimethibitishwa.');
      await writeAudit(txn,
          entity: 'tax_rate', entityUuid: uuid, action: 'Kimethibitishwa');
    });
    await AppCtx.load();
  }

  Future<void> retireTaxRate(String uuid) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
          'tax_rates', {'status': 'retired', 'sync_status': 'Pending'},
          where: 'uuid = ?', whereArgs: [uuid]);
      await writeAudit(txn,
          entity: 'tax_rate', entityUuid: uuid, action: 'Kimestaafishwa');
    });
    await AppCtx.load();
  }

  // ------------------------------------------------------------------ Safety
  Future<List<Map<String, dynamic>>> getSafetyIncidents(
      {bool allMines = false}) async {
    final db = await database;
    return db.query('safety_incidents',
        where: '${scopeWhere(allMines)} AND voided = 0',
        whereArgs: scopeArgs(allMines),
        orderBy: 'occurred_at DESC, id DESC');
  }

  /// Inarudisha UUID ya tukio ili app iombe picha mara baada ya kuhifadhi.
  Future<String> addSafetyIncident({
    required String type,
    required String severity,
    required String occurredAt,
    String? location,
    required String description,
    int injured = 0,
    String? actionTaken,
    String? officer,
    String? followUpDate,
    String? category,
    String? rootCause,
    String? injuryClass,
    String? injuredName,
    String? bodyPart,
    int lostWorkDays = 0,
    String? witnesses,
    String? equipment,
    bool? ppeWorn,
    bool workStopped = false,
    bool reportedToAuthority = false,
    String? authorityReference,
  }) async {
    String? clean(String? v) {
      final t = (v ?? '').trim();
      return t.isEmpty ? null : t;
    }

    if (description.trim().isEmpty) throw AppError('Eleza kilichotokea.');
    if (injured < 0) throw AppError('Idadi ya majeruhi si sahihi.');
    if (lostWorkDays < 0) throw AppError('Siku za kupoteza kazi si sahihi.');
    final cls = injuryClass ?? 'Hakuna';
    if (clean(category) == null) {
      throw AppError('Chagua kundi la tukio.');
    }
    if (injured > 0 && cls == 'Hakuna') {
      throw AppError('Kuna majeruhi: chagua kiwango cha jeraha.');
    }
    if (injured == 0 && cls != 'Hakuna') {
      throw AppError('Majeruhi ni 0 lakini kiwango cha jeraha si "Hakuna".');
    }
    if ((severity == 'Kifo') != (cls == 'Kifo')) {
      throw AppError('Ukubwa "Kifo" na kiwango cha jeraha "Kifo" lazima '
          'viendane.');
    }
    if (cls == 'Siku za kupoteza kazi' && lostWorkDays < 1) {
      throw AppError('Weka siku za kupoteza kazi (angalau 1).');
    }
    if (lostWorkDays > 0 && !kLostTimeClasses.contains(cls)) {
      throw AppError('Siku zimewekwa lakini kiwango cha jeraha hakiendani.');
    }
    if (reportedToAuthority && clean(authorityReference) == null) {
      throw AppError('Weka namba ya rejea ya ripoti kwa mamlaka.');
    }
    final db = await database;
    final m = meta();
    await db.transaction((txn) async {
      await txn.insert('safety_incidents', {
        ...m,
        'company_id': AppCtx.company,
        'mine_id': AppCtx.mine,
        'incident_type': type,
        'severity': severity,
        'occurred_at': occurredAt,
        'location': clean(location),
        'description': description.trim(),
        'injured_count': injured,
        'action_taken': clean(actionTaken),
        'responsible_officer': clean(officer),
        'follow_up_status': 'Wazi',
        'follow_up_date': clean(followUpDate),
        'reported_by': AppCtx.user,
        'voided': 0,
        'incident_category': clean(category),
        'root_cause': clean(rootCause),
        'injury_class': cls,
        'injured_name': clean(injuredName),
        'body_part': clean(bodyPart),
        'lost_work_days': lostWorkDays,
        'witnesses': clean(witnesses),
        'equipment_involved': clean(equipment),
        'ppe_worn': ppeWorn == null ? null : (ppeWorn ? 1 : 0),
        'work_stopped': workStopped ? 1 : 0,
        'reported_to_authority': reportedToAuthority ? 1 : 0,
        'authority_reference': clean(authorityReference),
      });
      await writeAudit(txn,
          entity: 'safety',
          entityUuid: m['uuid'] as String,
          action: 'Imerekodiwa',
          detail: '$type ($severity) • ${clean(category)} • $cls: '
              '${description.trim()}');
    });
    return m['uuid'] as String;
  }

  /// Kufunga tukio kuna masharti: chanzo kijulikane, hatua ya kurekebisha
  /// iwepo; tukio Kubwa/Kifo linahitaji ripoti kwa mamlaka na angalau picha 1.
  Future<void> updateSafetyFollowUp(
    String uuid,
    String status,
    String? note, {
    String? rootCause,
    String? correctiveAction,
    String? correctiveDue,
    bool? reportedToAuthority,
    String? authorityReference,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'safety_incidents',
        where: 'uuid = ? AND voided = 0',
        whereArgs: [uuid],
        limit: 1,
      );
      if (rows.isEmpty) throw AppError('Rekodi haijapatikana.');
      final old = rows.first;
      String pick(String? v, Object? previous) {
        final t = (v ?? '').trim();
        return t.isNotEmpty ? t : (previous ?? '').toString().trim();
      }

      final cause = pick(rootCause, old['root_cause']);
      final action = pick(correctiveAction, old['corrective_action']);
      final due = pick(correctiveDue, old['corrective_due']);
      final ref = pick(authorityReference, old['authority_reference']);
      final reported =
          reportedToAuthority ?? intv(old['reported_to_authority']) == 1;
      if (reported && ref.isEmpty) {
        throw AppError('Weka namba ya rejea ya ripoti kwa mamlaka.');
      }
      final severe = old['severity'] == 'Kubwa' || old['severity'] == 'Kifo';
      final closing = status == 'Imefungwa';
      if (closing) {
        if (cause.isEmpty || cause == 'Haijulikani bado') {
          throw AppError('Weka chanzo cha tukio (root cause) kabla ya kufunga.');
        }
        if (action.isEmpty) {
          throw AppError('Weka hatua ya kurekebisha kabla ya kufunga.');
        }
        if (severe) {
          if (!reported) {
            throw AppError('Tukio Kubwa/Kifo: weka kuwa limeripotiwa kwa '
                'mamlaka husika kabla ya kufunga.');
          }
          final photos = Sqflite.firstIntValue(await txn.rawQuery(
                'SELECT COUNT(*) FROM attachments '
                'WHERE record_uuid = ? AND deleted_at IS NULL',
                [uuid],
              )) ??
              0;
          if (photos == 0) {
            throw AppError('Tukio Kubwa/Kifo linahitaji angalau picha moja '
                'ya ushahidi kabla ya kufunga.');
          }
        }
      }
      await txn.update(
        'safety_incidents',
        {
          'follow_up_status': status,
          'root_cause': cause.isEmpty ? null : cause,
          'corrective_action': action.isEmpty ? null : action,
          'corrective_due': due.isEmpty ? null : due,
          'reported_to_authority': reported ? 1 : 0,
          'authority_reference': ref.isEmpty ? null : ref,
          'closed_by': closing ? AppCtx.user : null,
          'closed_at': closing ? DateTime.now().toUtc().toIso8601String() : null,
          'sync_status': 'Pending',
        },
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      await writeAudit(txn,
          entity: 'safety',
          entityUuid: uuid,
          action: 'Follow-up: $status',
          detail: note);
    });
  }

  Future<void> voidSafetyIncident(String uuid, String reason) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('safety_incidents',
          {'voided': 1, 'void_reason': reason, 'sync_status': 'Pending'},
          where: 'uuid = ?', whereArgs: [uuid]);
      await writeAudit(txn,
          entity: 'safety',
          entityUuid: uuid,
          action: 'Imefutwa',
          detail: reason);
    });
  }

  // ------------------------------------------------------------------ Reports
  /// Mass balance ya kila Batch: initial = remaining + processed + split_out.
  Future<List<Map<String, dynamic>>> massBalanceReport(
      {bool allMines = false}) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT *, (initial_kg - remaining_kg - processed_kg - split_out_kg) AS variance_kg, '
      '(processed_kg - tailings_kg - gold_g / 1000.0) AS process_loss_kg '
      'FROM v_mass_balance WHERE ${scopeWhere(allMines)} ORDER BY batch_id',
      scopeArgs(allMines),
    );
    return rows;
  }

  Future<List<Map<String, dynamic>>> batchCostReport(
      {bool allMines = false}) async {
    final db = await database;
    return db.rawQuery(
      'SELECT * FROM v_batch_costs WHERE ${scopeWhere(allMines)} ORDER BY total_cost DESC',
      scopeArgs(allMines),
    );
  }

  // ------------------------------------------------------------------ Attachments
  /// Inasajili metadata ya faili lililohifadhiwa kwenye simu (si blob ndani ya SQLite).
  Future<String> addAttachment({
    required String recordEntity,
    required String recordUuid,
    required String kind,
    required String filePath,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final db = await database;
    final m = meta();
    final digest = crypto.sha256.convert(bytes).toString();
    await db.transaction((txn) async {
      await txn.insert('attachments', {
        ...m,
        'company_id': AppCtx.company,
        'mine_id': AppCtx.mine,
        'record_entity': recordEntity,
        'record_uuid': recordUuid,
        'kind': kind,
        'file_path': filePath,
        'mime_type': mimeType,
        'file_size': bytes.length,
        'checksum_sha256': digest,
        'upload_status': 'pending',
        'created_by': AppCtx.user,
      });
      await writeAudit(txn,
          entity: 'attachment',
          entityUuid: m['uuid'] as String,
          action: 'Ushahidi umeongezwa',
          detail: '$kind • $recordEntity');
    });
    return m['uuid'] as String;
  }

  Future<List<Map<String, dynamic>>> getAttachments(
      {String? recordUuid}) async {
    final db = await database;
    return db.query('attachments',
        where: recordUuid == null
            ? 'company_id = ? AND deleted_at IS NULL'
            : 'company_id = ? AND record_uuid = ? AND deleted_at IS NULL',
        whereArgs: recordUuid == null
            ? [AppCtx.company]
            : [AppCtx.company, recordUuid],
        orderBy: 'created_at DESC');
  }

  // ------------------------------------------------------------------ Outbox stats
  Future<Map<String, int>> outboxStats() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT sync_status AS s, COUNT(*) AS n FROM sync_outbox GROUP BY sync_status');
    return {for (final r in rows) r['s'] as String: intv(r['n'])};
  }

  // ------------------------------------------------------------------ Approval ya matumizi
  Future<void> approveTransaction(String uuid) async {
    if (!AppCtx.canApprove) {
      throw AppError('Jukumu lako haliruhusu kuidhinisha.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final n = await txn.update(
        'finance_transactions',
        {
          'approval_status': 'Imeidhinishwa',
          'approved_by': AppCtx.user,
          'approved_at': nowIso(),
          'sync_status': 'Pending'
        },
        where: "uuid = ? AND approval_status = 'Inasubiri' AND voided = 0",
        whereArgs: [uuid],
      );
      if (n == 0) {
        throw AppError('Muamala hauko katika hali ya kusubiri idhini.');
      }
      await writeAudit(txn,
          entity: 'finance', entityUuid: uuid, action: 'Imeidhinishwa');
    });
  }

  /// Kukataa = kubatilisha (void) ili historia ibaki; hakuna kufuta.
  Future<void> rejectTransaction(String uuid, String reason) async {
    if (!AppCtx.canApprove) throw AppError('Jukumu lako haliruhusu kukataa.');
    final db = await database;
    await db.update(
      'finance_transactions',
      {
        'approval_status': 'Imekataliwa',
        'approved_by': AppCtx.user,
        'approved_at': nowIso(),
        'sync_status': 'Pending'
      },
      where: "uuid = ? AND approval_status = 'Inasubiri' AND voided = 0",
      whereArgs: [uuid],
    );
    await voidTransaction(uuid, 'Imekataliwa: $reason');
  }

  // ------------------------------------------------------------------ Batch / Sale traceability
  /// Production -> Batch -> Movement/Split -> Processing -> Gold lot -> Sale -> FIFO -> Evidence.
  Future<Map<String, List<Map<String, Object?>>>> batchTrace(
      String batchUuid) async {
    final db = await database;
    Future<List<Map<String, Object?>>> q(String name, String arg) =>
        db.rawQuery(kTraceQueries[name]!, [arg]);
    final out = <String, List<Map<String, Object?>>>{};
    out['batch'] = await q('batch', batchUuid);
    final ancestors = <Map<String, Object?>>[];
    Map<String, Object?>? cur =
        out['batch']!.isEmpty ? null : out['batch']!.first;
    var guard = 0;
    while (cur != null && cur['parent_batch_uuid'] != null && guard++ < 20) {
      final p = await q('batch', cur['parent_batch_uuid'] as String);
      if (p.isEmpty) break;
      ancestors.add(p.first);
      cur = p.first;
    }
    out['ancestors'] = ancestors;
    final rootUuid =
        ancestors.isEmpty ? batchUuid : ancestors.last['uuid'] as String;
    out['production'] = await q('production', rootUuid);
    for (final n in [
      'children',
      'merged_sources',
      'movements',
      'processing',
      'lots',
      'sales',
    ]) {
      out[n] = await q(n, batchUuid);
    }
    final ids = <String>{
      batchUuid,
      for (final r in out['production']!) r['uuid'] as String,
      for (final r in out['lots']!) r['uuid'] as String,
      for (final r in out['sales']!) r['sale_uuid'] as String,
    };
    final ev = <Map<String, Object?>>[];
    for (final id in ids) {
      ev.addAll(await q('evidence', id));
    }
    out['evidence'] = ev;
    return out;
  }

  /// Chanzo cha dhahabu iliyouzwa: Batch/lot zilizotoa gramu kupitia FIFO.
  Future<List<Map<String, Object?>>> saleSources(String saleUuid) async {
    final db = await database;
    return db.rawQuery(kTraceQueries['sale_sources']!, [saleUuid]);
  }

  // ------------------------------------------------------------------ Madeni yanayokaribia
  Future<List<Map<String, Object?>>> debtsDue({int days = 7}) async {
    final db = await database;
    final until = DateTime.now()
        .add(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    return db.rawQuery(kDebtsDueSql, [AppCtx.company, until]);
  }

  Future<List<Map<String, Object?>>> expenseBatchOptions() async {
    final db = await database;
    return db.query('ore_batches',
        columns: ['uuid', 'batch_id'],
        where: "company_id = ? AND mine_id = ? AND status != 'Imefutwa'",
        whereArgs: [AppCtx.company, AppCtx.mine],
        orderBy: 'id DESC',
        limit: 200);
  }
}
