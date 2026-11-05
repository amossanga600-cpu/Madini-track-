import 'package:sqflite/sqflite.dart';
import 'app_context.dart';
import 'database_helper.dart';
import 'utils.dart';

// ===========================================================================
// WAFANYAKAZI, MAHUDHURIO NA MALIPO
// ===========================================================================
extension HrDb on DatabaseHelper {
  Future<List<Map<String, dynamic>>> getWorkers({bool activeOnly = false}) async {
    final db = await database;
    return db.query(
      'workers',
      where: 'company_id = ? AND mine_id = ?${activeOnly ? ' AND active = 1' : ''}',
      whereArgs: [AppCtx.company, AppCtx.mine],
      orderBy: 'active DESC, full_name COLLATE NOCASE',
    );
  }

  Future<void> addWorker({
    required String fullName,
    String? phone,
    required String role,
    required String payType,
    required double payRate,
  }) async {
    final name = fullName.trim();
    if (name.isEmpty) throw AppError('Jina la mfanyakazi linahitajika.');
    if (payRate < 0) throw AppError('Kiwango cha malipo si sahihi.');

    final db = await database;
    await db.transaction((txn) async {
      final dup = await txn.rawQuery(
        'SELECT 1 FROM workers WHERE company_id = ? AND mine_id = ? '
        'AND LOWER(full_name) = LOWER(?) AND active = 1',
        [AppCtx.company, AppCtx.mine, name],
      );
      if (dup.isNotEmpty) {
        throw AppError('Mfanyakazi mwenye jina hili tayari yupo.');
      }
      final wm = meta();
      await txn.insert('workers', {
        ...wm,
        'company_id': AppCtx.company,
        'mine_id': AppCtx.mine,
        'full_name': name,
        'phone': phone,
        'role': role,
        'pay_type': payType,
        'pay_rate': payRate,
        'active': 1,
      });
      await writeAudit(txn,
          entity: 'worker',
          entityUuid: wm['uuid'] as String,
          action: 'Ameongezwa',
          detail: name);
    });
  }

  Future<void> updateWorker(
    String uuid, {
    required String role,
    required String payType,
    required double payRate,
    String? phone,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'workers',
        {
          'role': role,
          'pay_type': payType,
          'pay_rate': payRate,
          'phone': phone,
          'sync_status': 'Pending',
        },
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      await writeAudit(txn,
          entity: 'worker',
          entityUuid: uuid,
          action: 'Amebadilishwa',
          detail: '$role, $payType, ${fmtNum(payRate, decimals: 0)}');
    });
  }

  Future<void> setWorkerActive(String uuid, bool active) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'workers',
        {'active': active ? 1 : 0, 'sync_status': 'Pending'},
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      await writeAudit(txn,
          entity: 'worker',
          entityUuid: uuid,
          action: active ? 'Amerudishwa kazini' : 'Ameondolewa kazini');
    });
  }

  Future<Map<String, String>> getAttendanceForDate(String date) async {
    final db = await database;
    final rows = await db.query(
      'attendance',
      where: 'company_id = ? AND mine_id = ? AND att_date = ?',
      whereArgs: [AppCtx.company, AppCtx.mine, date],
    );
    return {
      for (final r in rows) r['worker_uuid'] as String: r['status'] as String
    };
  }

  Future<void> setAttendance(
    String workerUuid,
    String date,
    String status,
  ) async {
    final db = await database;
    final existing = await db.query(
      'attendance',
      where: 'worker_uuid = ? AND att_date = ?',
      whereArgs: [workerUuid, date],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('attendance', {
        ...meta(),
        'company_id': AppCtx.company,
        'mine_id': AppCtx.mine,
        'worker_uuid': workerUuid,
        'att_date': date,
        'status': status,
        'recorded_by': AppCtx.user,
      });
    } else {
      await db.update(
        'attendance',
        {'status': status, 'recorded_by': AppCtx.user, 'sync_status': 'Pending'},
        where: 'worker_uuid = ? AND att_date = ?',
        whereArgs: [workerUuid, date],
      );
    }
  }

  Future<int> daysPresent(String workerUuid, String from, String to) async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM attendance WHERE worker_uuid = ? '
          "AND status = 'Amehudhuria' AND att_date >= ? AND att_date <= ?",
          [workerUuid, from, to],
        )) ??
        0;
  }

  Future<void> payWorker({
    required String workerUuid,
    required String periodFrom,
    required String periodTo,
    required int daysPresentCount,
    required double gross,
    required double deductions,
    required String paidDate,
    required String method,
    String? notes,
  }) async {
    if (gross <= 0) throw AppError('Kiasi cha malipo lazima kiwe zaidi ya sifuri.');
    if (deductions < 0 || deductions > gross) {
      throw AppError('Makato si sahihi.');
    }
    if (periodFrom.compareTo(periodTo) > 0) {
      throw AppError('Tarehe ya mwanzo inazidi ya mwisho.');
    }

    final db = await database;
    await db.transaction((txn) async {
      final w = await txn.query('workers',
          where: 'uuid = ?', whereArgs: [workerUuid], limit: 1);
      if (w.isEmpty) throw AppError('Mfanyakazi hajapatikana.');
      final worker = w.first;

      if (worker['pay_type'] != 'Mgawo') {
        final overlap = await txn.rawQuery(
          'SELECT 1 FROM payroll_payments WHERE worker_uuid = ? AND voided = 0 '
          'AND period_from <= ? AND period_to >= ?',
          [workerUuid, periodTo, periodFrom],
        );
        if (overlap.isNotEmpty) {
          throw AppError(
            'Mfanyakazi huyu tayari amelipwa kwa kipindi kinachogongana na hiki.',
          );
        }
      }

      final net = gross - deductions;
      final pm = meta();
      await txn.insert('payroll_payments', {
        ...pm,
        'company_id': AppCtx.company,
        'mine_id': AppCtx.mine,
        'worker_uuid': workerUuid,
        'period_from': periodFrom,
        'period_to': periodTo,
        'days_present': daysPresentCount,
        'gross': gross,
        'deductions': deductions,
        'net': net,
        'paid_date': paidDate,
        'method': method,
        'notes': notes,
        'paid_by': AppCtx.user,
        'voided': 0,
      });

      await insertFinanceTxn(
        txn,
        type: 'Matumizi',
        category: 'Mishahara',
        amount: net,
        date: paidDate,
        description: 'Malipo: ${worker['full_name']} ($periodFrom - $periodTo)',
        method: method,
        source: 'Mishahara',
        sourceUuid: pm['uuid'] as String,
      );

      await writeAudit(txn,
          entity: 'payroll',
          entityUuid: pm['uuid'] as String,
          action: 'Imelipwa',
          detail: '${worker['full_name']}: ${fmtNum(net, decimals: 0)}');
    });
  }

  Future<List<Map<String, dynamic>>> getPayments({
    String? from,
    String? to,
    bool allMines = false,
  }) async {
    final db = await database;
    final dc = dateClause('p.paid_date', from, to);
    return db.rawQuery(
      'SELECT p.*, w.full_name FROM payroll_payments p '
      'LEFT JOIN workers w ON w.uuid = p.worker_uuid '
      'WHERE ${scopeWhere(allMines, 'p')}${dc.sql} '
      'ORDER BY p.paid_date DESC, p.id DESC',
      [...scopeArgs(allMines), ...dc.args],
    );
  }

  Future<void> voidPayment(String uuid, String reason) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('payroll_payments',
          where: 'uuid = ?', whereArgs: [uuid], limit: 1);
      if (rows.isEmpty) throw AppError('Malipo hayajapatikana.');
      if (intv(rows.first['voided']) == 1) {
        throw AppError('Malipo haya tayari yamefutwa.');
      }
      await txn.update(
        'payroll_payments',
        {'voided': 1, 'void_reason': reason, 'sync_status': 'Pending'},
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      await voidLinkedFinance(txn, 'Mishahara', uuid, reason);
      await writeAudit(txn,
          entity: 'payroll',
          entityUuid: uuid,
          action: 'Yamefutwa',
          detail: reason);
    });
  }
}

// ===========================================================================
// FEDHA NA MADENI
// ===========================================================================
extension FinanceDb on DatabaseHelper {
  Future<void> addTransaction({
    required String type,
    required String category,
    required double amount,
    required String date,
    String? description,
    required String method,
    String? reference,
  }) async {
    if (amount <= 0) throw AppError('Kiasi lazima kiwe zaidi ya sifuri.');
    final db = await database;
    await db.transaction((txn) async {
      await insertFinanceTxn(
        txn,
        type: type,
        category: category,
        amount: amount,
        date: date,
        description: description,
        method: method,
        reference: reference,
      );
      await writeAudit(txn,
          entity: 'finance',
          action: 'Imerekodiwa',
          detail: '$type $category ${fmtNum(amount, decimals: 0)}');
    });
  }

  Future<List<Map<String, dynamic>>> getTransactions({
    String? from,
    String? to,
    bool allMines = false,
  }) async {
    final db = await database;
    final dc = dateClause('trans_date', from, to);
    return db.rawQuery(
      'SELECT * FROM finance_transactions WHERE ${scopeWhere(allMines)}'
      '${dc.sql} ORDER BY trans_date DESC, id DESC',
      [...scopeArgs(allMines), ...dc.args],
    );
  }

  Future<void> voidTransaction(String uuid, String reason) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('finance_transactions',
          where: 'uuid = ?', whereArgs: [uuid], limit: 1);
      if (rows.isEmpty) throw AppError('Muamala haujapatikana.');
      final r = rows.first;
      if (intv(r['voided']) == 1) throw AppError('Muamala huu tayari umefutwa.');
      if (r['source'] != 'Mkono') {
        throw AppError(
          'Muamala huu umetokana na ${r['source']}. '
          'Futa rekodi ya chanzo chake badala yake.',
        );
      }
      await txn.update(
        'finance_transactions',
        {'voided': 1, 'void_reason': reason, 'sync_status': 'Pending'},
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      await writeAudit(txn,
          entity: 'finance',
          entityUuid: uuid,
          action: 'Umefutwa',
          detail: reason);
    });
  }

  // ----- Madeni -----
  Future<void> addDebt({
    required String direction,
    required String party,
    required double amount,
    String? dueDate,
    String? description,
  }) async {
    if (party.trim().isEmpty) throw AppError('Jina la mhusika linahitajika.');
    if (amount <= 0) throw AppError('Kiasi lazima kiwe zaidi ya sifuri.');
    final db = await database;
    await db.transaction((txn) async {
      final dm = meta();
      await txn.insert('debts', {
        ...dm,
        'company_id': AppCtx.company,
        'mine_id': AppCtx.mine,
        'direction': direction,
        'party': party.trim(),
        'amount': amount,
        'due_date': dueDate,
        'description': description,
        'created_by': AppCtx.user,
        'voided': 0,
      });
      await writeAudit(txn,
          entity: 'debt',
          entityUuid: dm['uuid'] as String,
          action: 'Imerekodiwa',
          detail: '$direction ${party.trim()} ${fmtNum(amount, decimals: 0)}');
    });
  }

  Future<List<Map<String, dynamic>>> getDebts() async {
    final db = await database;
    return db.rawQuery(
      'SELECT d.*, IFNULL((SELECT SUM(p.amount) FROM debt_payments p '
      'WHERE p.debt_uuid = d.uuid), 0) AS paid FROM debts d '
      'WHERE d.company_id = ? AND d.mine_id = ? AND d.voided = 0 '
      'ORDER BY d.id DESC',
      [AppCtx.company, AppCtx.mine],
    );
  }

  Future<void> addDebtPayment({
    required String debtUuid,
    required double amount,
    required String date,
    required String method,
    String? notes,
  }) async {
    if (amount <= 0) throw AppError('Kiasi lazima kiwe zaidi ya sifuri.');
    final db = await database;
    await db.transaction((txn) async {
      final d = await txn.query('debts',
          where: 'uuid = ? AND voided = 0', whereArgs: [debtUuid], limit: 1);
      if (d.isEmpty) throw AppError('Deni halijapatikana.');
      final debt = d.first;

      final paid = dbl((await txn.rawQuery(
              'SELECT IFNULL(SUM(amount),0) AS t FROM debt_payments WHERE debt_uuid = ?',
              [debtUuid]))
          .first['t']);
      final balance = dbl(debt['amount']) - paid;
      if (amount > balance + 0.005) {
        throw AppError('Kiasi kinazidi salio la deni (${fmtMoney(balance)}).');
      }

      final pm = meta();
      await txn.insert('debt_payments', {
        ...pm,
        'company_id': AppCtx.company,
        'debt_uuid': debtUuid,
        'amount': amount,
        'pay_date': date,
        'method': method,
        'notes': notes,
        'created_by': AppCtx.user,
      });

      final weOwe = debt['direction'] == 'Tunadaiwa';
      await insertFinanceTxn(
        txn,
        type: weOwe ? 'Matumizi' : 'Mapato',
        category: weOwe ? 'Malipo ya Deni' : 'Mapato Mengine',
        amount: amount,
        date: date,
        description: weOwe
            ? 'Malipo ya deni: ${debt['party']}'
            : 'Deni limelipwa na: ${debt['party']}',
        method: method,
        source: 'Madeni',
        sourceUuid: pm['uuid'] as String,
      );

      await writeAudit(txn,
          entity: 'debt',
          entityUuid: debtUuid,
          action: 'Malipo yamerekodiwa',
          detail: '${debt['party']}: ${fmtNum(amount, decimals: 0)}');
    });
  }

  Future<void> voidDebt(String uuid, String reason) async {
    final db = await database;
    await db.transaction((txn) async {
      final paid = dbl((await txn.rawQuery(
              'SELECT IFNULL(SUM(amount),0) AS t FROM debt_payments WHERE debt_uuid = ?',
              [uuid]))
          .first['t']);
      if (paid > 0) {
        throw AppError('Deni hili lina malipo tayari, haliwezi kufutwa.');
      }
      await txn.update(
        'debts',
        {'voided': 1, 'void_reason': reason, 'sync_status': 'Pending'},
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      await writeAudit(txn,
          entity: 'debt', entityUuid: uuid, action: 'Limefutwa', detail: reason);
    });
  }
}

// ===========================================================================
// INVENTORY
// ===========================================================================
extension InventoryDb on DatabaseHelper {
  Future<List<Map<String, dynamic>>> getItems() async {
    final db = await database;
    return db.rawQuery(
      'SELECT i.*, IFNULL(SUM(CASE WHEN m.move_type = \'Ingia\' THEN m.quantity '
      'WHEN m.move_type = \'Toka\' THEN -m.quantity ELSE 0 END), 0) AS stock '
      'FROM inventory_items i LEFT JOIN inventory_movements m '
      'ON m.item_uuid = i.uuid AND m.voided = 0 '
      'WHERE i.company_id = ? AND i.mine_id = ? AND i.active = 1 '
      'GROUP BY i.uuid ORDER BY i.name COLLATE NOCASE',
      [AppCtx.company, AppCtx.mine],
    );
  }

  Future<void> addItem({
    required String name,
    required String category,
    required String unit,
    required double minLevel,
  }) async {
    final n = name.trim();
    if (n.isEmpty) throw AppError('Jina la kifaa linahitajika.');
    final db = await database;
    await db.transaction((txn) async {
      final dup = await txn.rawQuery(
        'SELECT 1 FROM inventory_items WHERE company_id = ? AND mine_id = ? '
        'AND LOWER(name) = LOWER(?)',
        [AppCtx.company, AppCtx.mine, n],
      );
      if (dup.isNotEmpty) throw AppError('Kifaa hiki tayari kipo.');
      final im = meta();
      await txn.insert('inventory_items', {
        ...im,
        'company_id': AppCtx.company,
        'mine_id': AppCtx.mine,
        'name': n,
        'category': category,
        'unit': unit.trim(),
        'min_level': minLevel,
        'active': 1,
      });
      await writeAudit(txn,
          entity: 'inventory',
          entityUuid: im['uuid'] as String,
          action: 'Kifaa kimeongezwa',
          detail: n);
    });
  }

  Future<double> _stockOf(DatabaseExecutor ex, String itemUuid) async {
    final r = await ex.rawQuery(
      'SELECT IFNULL(SUM(CASE WHEN move_type = \'Ingia\' THEN quantity '
      'WHEN move_type = \'Toka\' THEN -quantity ELSE 0 END), 0) AS s '
      'FROM inventory_movements WHERE item_uuid = ? AND voided = 0',
      [itemUuid],
    );
    return dbl(r.first['s']);
  }

  Future<void> addStockMovement({
    required String itemUuid,
    required String moveType,
    required double quantity,
    double? unitCost,
    required String date,
    bool recordExpense = false,
    String? notes,
  }) async {
    if (quantity <= 0) throw AppError('Kiasi lazima kiwe zaidi ya sifuri.');
    final db = await database;
    await db.transaction((txn) async {
      final it = await txn.query('inventory_items',
          where: 'uuid = ?', whereArgs: [itemUuid], limit: 1);
      if (it.isEmpty) throw AppError('Kifaa hakijapatikana.');
      final item = it.first;

      if (moveType == 'Toka') {
        final stock = await _stockOf(txn, itemUuid);
        if (quantity > stock + 0.000001) {
          throw AppError(
            'Stock iliyopo ni ${fmtNum(stock)} ${item['unit']} tu.',
          );
        }
      }

      final mm = meta();
      await txn.insert('inventory_movements', {
        ...mm,
        'company_id': AppCtx.company,
        'mine_id': AppCtx.mine,
        'item_uuid': itemUuid,
        'move_type': moveType,
        'quantity': quantity,
        'unit_cost': unitCost,
        'move_date': date,
        'notes': notes,
        'created_by': AppCtx.user,
        'voided': 0,
      });

      if (moveType == 'Ingia' && recordExpense && (unitCost ?? 0) > 0) {
        final cat = item['category'] as String;
        await insertFinanceTxn(
          txn,
          type: 'Matumizi',
          category: kExpenseCategories.contains(cat) ? cat : 'Vifaa na Zana',
          amount: quantity * unitCost!,
          date: date,
          description: 'Ununuzi: ${item['name']} (${fmtNum(quantity)} ${item['unit']})',
          source: 'Stock',
          sourceUuid: mm['uuid'] as String,
        );
      }

      await writeAudit(txn,
          entity: 'inventory',
          entityUuid: mm['uuid'] as String,
          action: moveType == 'Ingia' ? 'Stock imeingia' : 'Stock imetoka',
          detail: '${item['name']}: ${fmtNum(quantity)} ${item['unit']}');
    });
  }

  Future<List<Map<String, dynamic>>> getStockMovements(String itemUuid) async {
    final db = await database;
    return db.query(
      'inventory_movements',
      where: 'item_uuid = ?',
      whereArgs: [itemUuid],
      orderBy: 'move_date DESC, id DESC',
    );
  }

  Future<void> voidStockMovement(String uuid, String reason) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('inventory_movements',
          where: 'uuid = ?', whereArgs: [uuid], limit: 1);
      if (rows.isEmpty) throw AppError('Rekodi haijapatikana.');
      final r = rows.first;
      if (intv(r['voided']) == 1) throw AppError('Rekodi hii tayari imefutwa.');

      if (r['move_type'] == 'Ingia') {
        final stock = await _stockOf(txn, r['item_uuid'] as String);
        if (stock - dbl(r['quantity']) < -0.000001) {
          throw AppError(
            'Huwezi kufuta: stock kidogo ingebaki chini ya sifuri (tayari imetumika).',
          );
        }
      }

      await txn.update(
        'inventory_movements',
        {'voided': 1, 'void_reason': reason, 'sync_status': 'Pending'},
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      await voidLinkedFinance(txn, 'Stock', uuid, reason);
      await writeAudit(txn,
          entity: 'inventory',
          entityUuid: uuid,
          action: 'Rekodi imefutwa',
          detail: reason);
    });
  }
}

// ===========================================================================
// MAUZO YA DHAHABU
// ===========================================================================
extension SalesDb on DatabaseHelper {
  Future<void> recordSale({
    required String saleDate,
    required String buyer,
    String? buyerLicense,
    required double weightG,
    required double purityPct,
    required double pricePerG,
    double otherFees = 0,
    required String method,
    String? reference,
    String? witness,
    String? notes,
  }) async {
    if (buyer.trim().isEmpty) throw AppError('Jina la mnunuzi linahitajika.');
    if (weightG <= 0) throw AppError('Uzito lazima uwe zaidi ya sifuri.');
    if (purityPct <= 0 || purityPct > 100) {
      throw AppError('Purity lazima iwe kati ya 0 na 100.');
    }
    if (pricePerG <= 0) throw AppError('Bei kwa gramu lazima iwe zaidi ya sifuri.');
    if (otherFees < 0) throw AppError('Ada nyingine si sahihi.');
    checkWitness(witness);

    final calc = calcSale(
      weightG: weightG,
      purityPct: purityPct,
      pricePerG: pricePerG,
      royaltyPct: AppCtx.royaltyPercent,
      inspectionPct: AppCtx.inspectionPercent,
      otherFees: otherFees,
    );
    if (calc.net < 0) throw AppError('Ada zinazidi mapato ya mauzo.');

    final db = await database;
    await db.transaction((txn) async {
      final bal = await goldBalanceOn(txn, false);
      if (weightG > bal + 0.000001) {
        throw AppError(
          'Dhahabu iliyopo kwenye mfumo ni ${fmtNum(bal)} g tu. '
          'Mauzo yanayozidi dhahabu iliyothibitishwa hayaruhusiwi.',
        );
      }

      final sm = meta();
      await txn.insert('sales', {
        ...sm,
        'company_id': AppCtx.company,
        'mine_id': AppCtx.mine,
        'sale_date': saleDate,
        'buyer': buyer.trim(),
        'buyer_license': buyerLicense,
        'gold_weight_g': weightG,
        'purity_percent': purityPct,
        'price_per_g': pricePerG,
        'gross_amount': calc.gross,
        'royalty_percent': AppCtx.royaltyPercent,
        'royalty_amount': calc.royalty,
        'inspection_percent': AppCtx.inspectionPercent,
        'inspection_amount': calc.inspection,
        'other_fees': otherFees,
        'net_amount': calc.net,
        'payment_method': method,
        'reference': reference,
        'witness': (witness ?? '').trim().isEmpty ? null : witness!.trim(),
        'notes': notes,
        'created_by': AppCtx.user,
        'voided': 0,
      });

      final suuid = sm['uuid'] as String;
      var gramsToAllocate = weightG;
      final lots = await txn.query(
        'gold_inventory',
        where: 'company_id = ? AND mine_id = ? AND grams_available > 0 AND deleted_at IS NULL',
        whereArgs: [AppCtx.company, AppCtx.mine],
        orderBy: 'created_at ASC, id ASC',
      );
      for (final lot in lots) {
        if (gramsToAllocate <= 0.000001) break;
        final available = dbl(lot['grams_available']);
        final take = available < gramsToAllocate ? available : gramsToAllocate;
        if (take <= 0) continue;
        await txn.update('gold_inventory', {
          'grams_available': available - take,
          'updated_at': nowIso(),
          'version': intv(lot['version']) + 1,
          'sync_status': 'Pending',
        }, where: 'id = ?', whereArgs: [lot['id']]);
        await txn.insert('gold_sale_allocations', {
          'uuid': newUuid(), 'sale_uuid': suuid, 'lot_uuid': lot['uuid'],
          'grams': take, 'created_at': nowIso(), 'updated_at': nowIso(), 'device_id': AppCtx.deviceId,
          'version': 1, 'deleted_at': null, 'sync_status': 'Pending',
        });
        gramsToAllocate -= take;
      }
      if (gramsToAllocate > 0.000001) {
        throw AppError('Imeshindikana kugawa dhahabu kwa FIFO; muamala umebatilishwa.');
      }
      await insertFinanceTxn(
        txn,
        type: 'Mapato',
        category: 'Mauzo ya Dhahabu',
        amount: calc.gross,
        date: saleDate,
        description: 'Mauzo: ${buyer.trim()} (${fmtNum(weightG)} g)',
        method: method,
        reference: reference,
        source: 'Mauzo',
        sourceUuid: suuid,
      );

      final fees = calc.royalty + calc.inspection + otherFees;
      if (fees > 0) {
        await insertFinanceTxn(
          txn,
          type: 'Matumizi',
          category: 'Mrabaha na Ada',
          amount: fees,
          date: saleDate,
          description: 'Mrabaha na ada za mauzo: ${buyer.trim()}',
          method: method,
          source: 'Mauzo',
          sourceUuid: suuid,
        );
      }

      await writeAudit(txn,
          entity: 'sale',
          entityUuid: suuid,
          action: 'Imerekodiwa',
          detail: '${buyer.trim()}: ${fmtNum(weightG)} g, '
              '${fmtNum(calc.gross, decimals: 0)}');
    });
  }

  Future<List<Map<String, dynamic>>> getSales({
    String? from,
    String? to,
    bool allMines = false,
  }) async {
    final db = await database;
    final dc = dateClause('sale_date', from, to);
    return db.rawQuery(
      'SELECT * FROM sales WHERE ${scopeWhere(allMines)}${dc.sql} '
      'ORDER BY sale_date DESC, id DESC',
      [...scopeArgs(allMines), ...dc.args],
    );
  }

  Future<void> voidSale(String uuid, String reason) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('sales',
          where: 'uuid = ?', whereArgs: [uuid], limit: 1);
      if (rows.isEmpty) throw AppError('Mauzo hayajapatikana.');
      if (intv(rows.first['voided']) == 1) {
        throw AppError('Mauzo haya tayari yamefutwa.');
      }
      final allocations = await txn.query('gold_sale_allocations', where: 'sale_uuid = ? AND deleted_at IS NULL', whereArgs: [uuid]);
      for (final allocation in allocations) {
        final lots = await txn.query('gold_inventory', where: 'uuid = ?', whereArgs: [allocation['lot_uuid']], limit: 1);
        if (lots.isNotEmpty) {
          final lot = lots.first;
          await txn.update('gold_inventory', {
            'grams_available': dbl(lot['grams_available']) + dbl(allocation['grams']),
            'updated_at': nowIso(), 'version': intv(lot['version']) + 1, 'sync_status': 'Pending'
          }, where: 'id = ?', whereArgs: [lot['id']]);
        }
        await txn.update('gold_sale_allocations', {'deleted_at': nowIso(), 'sync_status': 'Pending'}, where: 'id = ?', whereArgs: [allocation['id']]);
      }
      await txn.update(
        'sales',
        {'voided': 1, 'void_reason': reason, 'sync_status': 'Pending'},
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      await voidLinkedFinance(txn, 'Mauzo', uuid, reason);
      await writeAudit(txn,
          entity: 'sale', entityUuid: uuid, action: 'Yamefutwa', detail: reason);
    });
  }
}
