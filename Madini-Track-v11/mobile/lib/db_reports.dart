import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'app_context.dart';
import 'database_helper.dart';
import 'db_modules.dart';
import 'utils.dart';

extension ReportsDb on DatabaseHelper {
  /// Mizania ya kila Batch: iliyochimbwa = iliyobaki + iliyochakatwa + iliyogawanywa.
  Future<List<Map<String, dynamic>>> batchBalances(
      {bool allMines = false}) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT b.batch_id, b.status, b.current_location, b.initial_weight_kg, '
      'b.weight_kg, '
      'IFNULL((SELECT SUM(p.ore_processed_kg) FROM processing_records p '
      'WHERE p.company_id = b.company_id AND p.batch_id = b.batch_id '
      'AND p.voided = 0), 0) AS processed, '
      'IFNULL((SELECT SUM(c.initial_weight_kg) FROM ore_batches c '
      'WHERE c.company_id = b.company_id AND c.parent_batch_id = b.batch_id), 0) '
      'AS split_out '
      "FROM ore_batches b WHERE ${scopeWhere(allMines, 'b')} "
      "AND b.status != 'Imefutwa' ORDER BY b.id DESC",
      scopeArgs(allMines),
    );

    return rows.map((r) {
      final initial = dbl(r['initial_weight_kg']);
      final accounted =
          dbl(r['weight_kg']) + dbl(r['processed']) + dbl(r['split_out']);
      final diff = initial - accounted;
      return {...r, 'diff': diff, 'mismatch': diff.abs() > 0.01};
    }).toList();
  }

  Future<Map<String, dynamic>> buildReport({
    String? from,
    String? to,
    bool allMines = false,
  }) async {
    final db = await database;
    final w = scopeWhere(allMines);
    final a = scopeArgs(allMines);

    final pc = dateClause('shift_date', from, to);
    final prod = (await db.rawQuery(
      'SELECT COUNT(*) AS n, IFNULL(SUM(bags_count),0) AS bags, '
      'IFNULL(SUM(weight_kg),0) AS kg FROM production_records '
      'WHERE $w AND voided = 0${pc.sql}',
      [...a, ...pc.args],
    ))
        .first;

    final qc = dateClause('processing_date', from, to);
    final proc = (await db.rawQuery(
      'SELECT COUNT(*) AS n, IFNULL(SUM(ore_processed_kg),0) AS ore, '
      'IFNULL(SUM(gold_recovered_g),0) AS gold, '
      'IFNULL(SUM(tailings_kg),0) AS tailings, '
      'IFNULL(SUM(processing_cost),0) AS cost, '
      'IFNULL(SUM(mercury_g),0) AS mercury FROM processing_records '
      'WHERE $w AND voided = 0${qc.sql}',
      [...a, ...qc.args],
    ))
        .first;

    final sc = dateClause('sale_date', from, to);
    final sales = (await db.rawQuery(
      'SELECT COUNT(*) AS n, IFNULL(SUM(gold_weight_g),0) AS g, '
      'IFNULL(SUM(gross_amount),0) AS gross, '
      'IFNULL(SUM(royalty_amount + inspection_amount + other_fees),0) AS fees, '
      'IFNULL(SUM(net_amount),0) AS net FROM sales '
      'WHERE $w AND voided = 0${sc.sql}',
      [...a, ...sc.args],
    ))
        .first;

    final fc = dateClause('trans_date', from, to);
    final finRows = await db.rawQuery(
      'SELECT type, category, IFNULL(SUM(amount),0) AS t '
      'FROM finance_transactions WHERE $w AND voided = 0${fc.sql} '
      'GROUP BY type, category ORDER BY t DESC',
      [...a, ...fc.args],
    );
    double income = 0;
    double expense = 0;
    for (final r in finRows) {
      if (r['type'] == 'Mapato') income += dbl(r['t']);
      if (r['type'] == 'Matumizi') expense += dbl(r['t']);
    }

    final yc = dateClause('paid_date', from, to);
    final pay = (await db.rawQuery(
      'SELECT COUNT(*) AS n, IFNULL(SUM(net),0) AS net FROM payroll_payments '
      'WHERE $w AND voided = 0${yc.sql}',
      [...a, ...yc.args],
    ))
        .first;

    final items = await getItems();
    final low = items
        .where((i) =>
            dbl(i['min_level']) > 0 && dbl(i['stock']) <= dbl(i['min_level']))
        .toList();

    return {
      'prod': prod,
      'proc': proc,
      'sales': sales,
      'finance_rows': finRows,
      'income': income,
      'expense': expense,
      'payroll': pay,
      'low_stock': low,
      'gold_balance': await goldBalanceOn(db, allMines),
      'batches': await batchBalances(allMines: allMines),
    };
  }

  String reportToText(
    Map<String, dynamic> r, {
    required String periodLabel,
    required String scopeLabel,
  }) {
    final prod = r['prod'] as Map;
    final proc = r['proc'] as Map;
    final sales = r['sales'] as Map;
    final pay = r['payroll'] as Map;
    final oreKg = dbl(proc['ore']);
    final gold = dbl(proc['gold']);
    final b = StringBuffer();

    b.writeln('RIPOTI - MADINI TRACK');
    b.writeln('${AppCtx.company} | $scopeLabel');
    b.writeln('Kipindi: $periodLabel');
    b.writeln('Imetolewa: ${shortDate(nowIso())} na ${AppCtx.user}');
    b.writeln('');
    b.writeln('UZALISHAJI');
    b.writeln('Rekodi: ${intv(prod['n'])}, Magunia: ${intv(prod['bags'])}, '
        'Uzito: ${fmtKg(dbl(prod['kg']))}');
    b.writeln('');
    b.writeln('UCHAKATAJI');
    b.writeln('Ore: ${fmtKg(oreKg)}, Dhahabu: ${fmtG(gold)}, '
        'Mabaki: ${fmtKg(dbl(proc['tailings']))}');
    b.writeln('Grade halisi: ${fmtNum(gradeGpt(gold, oreKg))} g/t, '
        'Gharama: ${fmtMoney(dbl(proc['cost']))}');
    b.writeln('');
    b.writeln('MAUZO');
    b.writeln('Mauzo: ${intv(sales['n'])}, Dhahabu: ${fmtG(dbl(sales['g']))}');
    b.writeln('Jumla: ${fmtMoney(dbl(sales['gross']))}, '
        'Ada/Mrabaha: ${fmtMoney(dbl(sales['fees']))}, '
        'Net: ${fmtMoney(dbl(sales['net']))}');
    b.writeln('');
    b.writeln('FEDHA');
    b.writeln('Mapato: ${fmtMoney(dbl(r['income']))}');
    b.writeln('Matumizi: ${fmtMoney(dbl(r['expense']))}');
    b.writeln('Salio: ${fmtMoney(dbl(r['income']) - dbl(r['expense']))}');
    for (final row in (r['finance_rows'] as List)) {
      b.writeln('  - ${row['type']} / ${row['category']}: '
          '${fmtMoney(dbl(row['t']))}');
    }
    b.writeln('');
    b.writeln(
        'MISHAHARA: ${intv(pay['n'])} malipo, ${fmtMoney(dbl(pay['net']))}');
    b.writeln('');
    b.writeln('DHAHABU ILIYOPO (haijauzwa): ${fmtG(dbl(r['gold_balance']))}');

    final low = r['low_stock'] as List;
    if (low.isNotEmpty) {
      b.writeln('');
      b.writeln('VIFAA VINAVYOKARIBIA KUISHA');
      for (final i in low) {
        b.writeln('  - ${i['name']}: ${fmtNum(dbl(i['stock']))} ${i['unit']}');
      }
    }

    final mism =
        (r['batches'] as List).where((x) => x['mismatch'] == true).toList();
    if (mism.isNotEmpty) {
      b.writeln('');
      b.writeln('TAHADHARI: BATCH ZENYE TOFAUTI YA UZITO');
      for (final x in mism) {
        b.writeln('  - ${x['batch_id']}: tofauti ${fmtNum(dbl(x['diff']))} kg');
      }
    }
    return b.toString();
  }

  // -------------------------------------------------------------------------
  // CSV
  // -------------------------------------------------------------------------
  Future<String> exportCsv(String kind,
      {String? from, String? to, bool allMines = false}) async {
    switch (kind) {
      case 'Uzalishaji':
        final rows =
            await getProductionRecords(from: from, to: to, allMines: allMines);
        return toCsv(rows, [
          'shift_date',
          'mine_id',
          'shaft_area',
          'batch_id',
          'shift_type',
          'bags_count',
          'weight_kg',
          'estimated_grade',
          'recorded_by',
          'witness',
          'voided',
          'void_reason',
          'uuid',
        ]);
      case 'Uchakataji':
        final rows =
            await getProcessingRecords(from: from, to: to, allMines: allMines);
        return toCsv(rows, [
          'processing_date',
          'mine_id',
          'batch_id',
          'ore_processed_kg',
          'gold_recovered_g',
          'tailings_kg',
          'purity_percent',
          'method',
          'mercury_g',
          'processing_cost',
          'processed_by',
          'witness',
          'voided',
          'void_reason',
          'uuid',
        ]);
      case 'Fedha':
        final rows =
            await getTransactions(from: from, to: to, allMines: allMines);
        return toCsv(rows, [
          'trans_date',
          'mine_id',
          'type',
          'category',
          'amount',
          'method',
          'reference',
          'description',
          'source',
          'created_by',
          'voided',
          'void_reason',
          'uuid',
        ]);
      case 'Mauzo':
        final rows = await getSales(from: from, to: to, allMines: allMines);
        return toCsv(rows, [
          'sale_date',
          'mine_id',
          'buyer',
          'buyer_license',
          'gold_weight_g',
          'purity_percent',
          'price_per_g',
          'gross_amount',
          'royalty_amount',
          'inspection_amount',
          'other_fees',
          'net_amount',
          'payment_method',
          'reference',
          'witness',
          'created_by',
          'voided',
          'uuid',
        ]);
      case 'Mishahara':
        final rows = await getPayments(from: from, to: to, allMines: allMines);
        return toCsv(rows, [
          'paid_date',
          'full_name',
          'period_from',
          'period_to',
          'days_present',
          'gross',
          'deductions',
          'net',
          'method',
          'paid_by',
          'voided',
          'uuid',
        ]);
      case 'Batch':
        final rows = await batchBalances(allMines: allMines);
        return toCsv(rows, [
          'batch_id',
          'status',
          'current_location',
          'initial_weight_kg',
          'processed',
          'split_out',
          'weight_kg',
          'diff',
        ]);
    }
    return '';
  }

  // -------------------------------------------------------------------------
  // Audit log na takwimu za database
  // -------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getAuditLog({int limit = 200}) async {
    final db = await database;
    return db.query(
      'audit_log',
      where: 'company_id = ?',
      whereArgs: [AppCtx.company],
      orderBy: 'id DESC',
      limit: limit,
    );
  }

  Future<Map<String, int>> tableCounts() async {
    final db = await database;
    final out = <String, int>{};
    for (final t in kSyncTables) {
      out[t] =
          Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t')) ??
              0;
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Backup na Restore (JSON)
  // -------------------------------------------------------------------------
  Future<String> exportBackupJson() async {
    final db = await database;
    final tables = <String, dynamic>{};
    for (final t in kBackupTables) {
      if (t == 'app_settings') {
        tables[t] = await db.query(
          t,
          where: "setting_key NOT LIKE 'pin_%'",
        );
      } else {
        tables[t] = await db.query(t);
      }
    }
    return jsonEncode({
      'app': 'madini_track',
      'db_version': kDbVersion,
      'exported_at': nowIso(),
      'exported_by': AppCtx.user,
      'tables': tables,
    });
  }

  /// Inabadilisha data YOTE ya simu na data ya backup. Inathibitisha muundo
  /// kwanza, kisha inafuta na kuingiza ndani ya transaction moja.
  Future<void> restoreBackupJson(String text) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw AppError('Maandishi si backup sahihi ya Madini Track.');
    }
    if (decoded is! Map || decoded['app'] != 'madini_track') {
      throw AppError('Maandishi si backup ya Madini Track.');
    }
    // Schema ni additive tangu v7; safu mpya hutumia defaults za database.
    final backupVersion = decoded['db_version'];
    if (backupVersion is! int ||
        backupVersion < 7 ||
        backupVersion > kDbVersion) {
      throw AppError(
        'Backup hii ni ya toleo tofauti la database ($backupVersion).',
      );
    }
    final tables = decoded['tables'];
    if (tables is! Map) throw AppError('Backup haina majedwali.');
    for (final t in kBackupTables) {
      if (tables[t] != null && tables[t] is! List) {
        throw AppError('Jedwali $t kwenye backup si sahihi.');
      }
    }

    final db = await database;
    await db.transaction((txn) async {
      for (final t in kBackupTables) {
        if (t == 'app_settings') {
          await txn.delete(t, where: "setting_key NOT LIKE 'pin_%'");
        } else {
          await txn.delete(t);
        }
      }
      // Events za zamani za outbox hazihusiani tena na data iliyorejeshwa.
      await txn.delete('sync_outbox');
      for (final t in kBackupTables) {
        final rows = (tables[t] as List?) ?? const [];
        for (final row in rows) {
          await txn.insert(
            t,
            Map<String, Object?>.from(row as Map),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await writeAudit(txn,
          entity: 'system',
          action: 'Backup imerejeshwa',
          detail: 'Kutoka ${decoded['exported_at']}');
    });
    await AppCtx.load();
  }
}
