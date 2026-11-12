import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'app_context.dart';
import 'db_encryption.dart';
import 'migration_v8_sql.dart';
import 'migration_v9_sql.dart';
import 'migration_v10_sql.dart';
import 'migration_v11_sql.dart';
import 'utils.dart';

/// Toleo la database v11: v10 + ajali/usalama ya kiufundi (safu additive).
const int kDbVersion = 11;

/// Majedwali yote yanayoingia kwenye Backup / Restore.
const List<String> kBackupTables = [
  'app_settings',
  'companies',
  'mines',
  'production_records',
  'ore_batches',
  'batch_movements',
  'processing_records',
  'workers',
  'attendance',
  'payroll_payments',
  'finance_transactions',
  'debts',
  'debt_payments',
  'inventory_items',
  'inventory_movements',
  'sales',
  'audit_log',
  'gold_inventory',
  'gold_sale_allocations',
  'attachments',
  'tax_rates',
  'safety_incidents',
  'local_users',
];

/// Majedwali yenye `sync_status` (yatakayotumwa kwenye backend).
const List<String> kSyncTables = [
  'companies',
  'mines',
  'production_records',
  'ore_batches',
  'batch_movements',
  'processing_records',
  'workers',
  'attendance',
  'payroll_payments',
  'finance_transactions',
  'debts',
  'debt_payments',
  'inventory_items',
  'inventory_movements',
  'sales',
  'audit_log',
  'gold_inventory',
  'gold_sale_allocations',
  'attachments',
  'tax_rates',
  'safety_incidents',
];

// ---------------------------------------------------------------------------
// Vifaa vya pamoja
// ---------------------------------------------------------------------------
Map<String, dynamic> meta() => {
      'uuid': newUuid(),
      'created_at': nowIso(),
      'updated_at': nowIso(),
      'device_id': AppCtx.deviceId.isEmpty ? null : AppCtx.deviceId,
      'version': 1,
      'deleted_at': null,
      'sync_status': 'Pending',
    };

class Clause {
  final String sql;
  final List<Object?> args;
  const Clause(this.sql, this.args);
}

Clause dateClause(String col, String? from, String? to) {
  final sql = StringBuffer();
  final args = <Object?>[];
  if (from != null) {
    sql.write(' AND $col >= ?');
    args.add(from);
  }
  if (to != null) {
    sql.write(' AND $col < ?');
    args.add(nextDay(to));
  }
  return Clause(sql.toString(), args);
}

String scopeWhere(bool allMines, [String alias = '']) {
  final p = alias.isEmpty ? '' : '$alias.';
  return allMines
      ? '${p}company_id = ?'
      : '${p}company_id = ? AND ${p}mine_id = ?';
}

List<Object?> scopeArgs(bool allMines) =>
    allMines ? [AppCtx.company] : [AppCtx.company, AppCtx.mine];

Future<void> writeAudit(
  DatabaseExecutor ex, {
  required String entity,
  String? entityUuid,
  required String action,
  String? detail,
  String? company,
}) async {
  await ex.insert('audit_log', {
    ...meta(),
    'company_id': company ?? AppCtx.company,
    'mine_id':
        (company == null || company == AppCtx.company) ? AppCtx.mine : null,
    'entity': entity,
    'entity_uuid': entityUuid,
    'action': action,
    'detail': detail,
    'user_name': AppCtx.user,
    'actor_uuid': AppCtx.userUuid.isEmpty ? null : AppCtx.userUuid,
  });
}

/// Shahidi (mtu wa pili) anahitajika kwa mipangilio ya sasa.
void checkWitness(String? witness) {
  final w = (witness ?? '').trim();
  if (AppCtx.requireWitness && w.isEmpty) {
    throw AppError('Weka jina la shahidi (mtu wa pili).');
  }
  if (w.isNotEmpty && w.toLowerCase() == AppCtx.user.trim().toLowerCase()) {
    throw AppError('Shahidi lazima awe mtu tofauti na aliyeingiza rekodi.');
  }
}

Future<void> insertFinanceTxn(
  DatabaseExecutor ex, {
  String? batchUuid,
  String approvalStatus = 'Imeidhinishwa',
  required String type,
  required String category,
  required double amount,
  required String date,
  String? description,
  String method = 'Pesa taslimu',
  String? reference,
  String source = 'Mkono',
  String? sourceUuid,
}) async {
  await ex.insert('finance_transactions', {
    ...meta(),
    'company_id': AppCtx.company,
    'mine_id': AppCtx.mine,
    'type': type,
    'category': category,
    'amount': amount,
    'trans_date': date,
    'description': description,
    'method': method,
    'reference': reference,
    'source': source,
    'source_uuid': sourceUuid,
    'created_by': AppCtx.user,
    'voided': 0,
    'batch_uuid': batchUuid,
    'approval_status': approvalStatus,
  });
}

Future<void> voidLinkedFinance(
  DatabaseExecutor ex,
  String source,
  String sourceUuid,
  String reason,
) async {
  await ex.update(
    'finance_transactions',
    {
      'voided': 1,
      'void_reason': 'Chanzo kimefutwa: $reason',
      'sync_status': 'Pending',
    },
    where: 'source = ? AND source_uuid = ? AND voided = 0',
    whereArgs: [source, sourceUuid],
  );
}

Future<double> goldBalanceOn(DatabaseExecutor ex, bool allMines) async {
  final w = scopeWhere(allMines);
  final a = scopeArgs(allMines);
  final rec = await ex.rawQuery(
    'SELECT IFNULL(SUM(gold_recovered_g),0) AS t FROM processing_records '
    'WHERE $w AND voided = 0',
    a,
  );
  final sold = await ex.rawQuery(
    'SELECT IFNULL(SUM(gold_weight_g),0) AS t FROM sales '
    'WHERE $w AND voided = 0',
    a,
  );
  return dbl(rec.first['t']) - dbl(sold.first['t']);
}

// ---------------------------------------------------------------------------
// DatabaseHelper
// ---------------------------------------------------------------------------
class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static Database? _database;
  static DatabaseFactory? testFactory;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final factory = testFactory;
    if (factory != null) {
      final path = join(await factory.getDatabasesPath(), 'madini_local.db');
      await _backupBeforeUpgrade(path, factory: factory);
      return factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: kDbVersion,
          onConfigure: _onConfigure,
          onCreate: _createDB,
          onUpgrade: _upgradeDB,
        ),
      );
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'madini_local.db');
    final key = await DbEncryption.prepare(path);

    await _backupBeforeUpgrade(path, password: key);

    return openDatabase(
      path,
      password: key,
      version: kDbVersion,
      onConfigure: _onConfigure,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // Lazima iwashwe kwa kila connection; SQLite huizima kwa chaguo-msingi.
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Mkakati wa recovery: kabla ya upgrade, nakili faili la database la toleo
  /// la zamani kando yake (`madini_local.db.pre-vN.bak`). Ikiwa migration
  /// itashindwa sqflite hurudisha transaction, na nakala hii inabaki kama kinga.
  Future<void> _backupBeforeUpgrade(
    String path, {
    String? password,
    DatabaseFactory? factory,
  }) async {
    try {
      final f = File(path);
      if (!await f.exists()) return;
      final probe = factory != null
          ? await factory.openDatabase(
              path,
              options: OpenDatabaseOptions(readOnly: true),
            )
          : await openReadOnlyDatabase(path, password: password);
      final v = await probe.getVersion();
      await probe.close();
      if (v > 0 && v < kDbVersion) {
        final bak = File('$path.pre-v$kDbVersion.bak');
        if (!await bak.exists()) await f.copy(bak.path);
      }
    } catch (_) {
      // Migration transaction bado hulinda schema; open ya kawaida itaonyesha hitilafu.
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await _createProductionTable(db);
    await _createBatchTables(db);
    await _createProcessingTable(db);
    await _migrateToV5(db);
    await _migrateToV7(db);
    await _migrateToV8(db);
    await _migrateToV9(db);
    await _migrateToV10(db);
    await _migrateToV11(db);
  }

  Future<void> _createProductionTable(Database db) async {
    await db.execute('''
      CREATE TABLE production_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        mine_id TEXT NOT NULL,
        shaft_area TEXT NOT NULL,
        batch_id TEXT NOT NULL,
        shift_date TEXT NOT NULL,
        shift_type TEXT NOT NULL,
        bags_count INTEGER NOT NULL,
        weight_kg REAL NOT NULL,
        estimated_grade REAL,
        recorded_by TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'Pending',
        created_at TEXT NOT NULL,
        UNIQUE(company_id, batch_id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_production_sync
      ON production_records(sync_status)
    ''');

    await db.execute('''
      CREATE INDEX idx_production_mine
      ON production_records(company_id, mine_id)
    ''');
  }

  Future<void> _createBatchTables(Database db) async {
    await db.execute('''
      CREATE TABLE ore_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        mine_id TEXT NOT NULL,
        batch_id TEXT NOT NULL,
        source_location TEXT NOT NULL,
        current_location TEXT NOT NULL,
        weight_kg REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'Imechimbwa',
        created_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'Pending',
        UNIQUE(company_id, batch_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE batch_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        batch_id TEXT NOT NULL,
        from_location TEXT NOT NULL,
        to_location TEXT NOT NULL,
        weight_kg REAL NOT NULL,
        movement_date TEXT NOT NULL,
        moved_by TEXT NOT NULL,
        notes TEXT,
        sync_status TEXT NOT NULL DEFAULT 'Pending'
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_batch_company
      ON ore_batches(company_id, mine_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_movement_batch
      ON batch_movements(company_id, batch_id)
    ''');
  }

  Future<void> _createProcessingTable(Database db) async {
    await db.execute('''
      CREATE TABLE processing_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        mine_id TEXT NOT NULL,
        batch_id TEXT NOT NULL,
        ore_processed_kg REAL NOT NULL,
        gold_recovered_g REAL NOT NULL,
        tailings_kg REAL NOT NULL,
        processing_cost REAL NOT NULL DEFAULT 0,
        processing_date TEXT NOT NULL,
        processed_by TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'Pending'
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_processing_batch
      ON processing_records(company_id, batch_id)
    ''');
  }

  Future<void> _upgradeDB(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE production_records_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id TEXT NOT NULL,
          mine_id TEXT NOT NULL,
          shaft_area TEXT NOT NULL,
          batch_id TEXT NOT NULL,
          shift_date TEXT NOT NULL,
          shift_type TEXT NOT NULL,
          bags_count INTEGER NOT NULL,
          weight_kg REAL NOT NULL,
          estimated_grade REAL,
          recorded_by TEXT NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'Pending',
          created_at TEXT NOT NULL,
          UNIQUE(company_id, batch_id)
        )
      ''');
      await db.execute(
        'INSERT INTO production_records_new SELECT * FROM production_records',
      );
      await db.execute('DROP TABLE production_records');
      await db.execute(
        'ALTER TABLE production_records_new RENAME TO production_records',
      );
      await db.execute(
        'CREATE INDEX idx_production_sync ON production_records(sync_status)',
      );
      await db.execute(
        'CREATE INDEX idx_production_mine '
        'ON production_records(company_id, mine_id)',
      );
    }

    if (oldVersion < 3) {
      await _createBatchTables(db);
    }

    if (oldVersion < 4) {
      await _createProcessingTable(db);
    }

    if (oldVersion < 5) {
      await _migrateToV5(db);
    }
    if (oldVersion < 7) {
      await _migrateToV7(db);
    }
    if (oldVersion < 8) {
      await _migrateToV8(db);
    }
    if (oldVersion < 9) {
      await _migrateToV9(db);
    }
    if (oldVersion < 10) {
      await _migrateToV10(db);
    }
    if (oldVersion < 11) {
      await _migrateToV11(db);
    }
  }

  /// Schema v8. Inaendeshwa ndani ya transaction ya sqflite (onCreate/onUpgrade),
  /// kwa hiyo ikishindwa hakuna badiliko linalobaki. SQL kamili: kV8Statements.
  Future<void> _migrateToV8(Database db) async {
    for (final s in kV8Statements) {
      await db.execute(s);
    }
  }

  /// Schema v9: huongeza metadata ya algorithm ya PIN bila kubadili hash za zamani.
  Future<void> _migrateToV9(Database db) async {
    for (final s in kV9Statements) {
      await db.execute(s);
    }
  }

  /// Schema v10: ledger ya uzito wa Batch inajumuisha transfers za merge.
  Future<void> _migrateToV10(Database db) async {
    for (final s in kV10Statements) {
      await db.execute(s);
    }
  }

  /// Schema v11: safu za ajali/usalama ya kiufundi (additive).
  Future<void> _migrateToV11(Database db) async {
    for (final s in kV11Statements) {
      await db.execute(s);
    }
  }

  /// Schema v7: huongeza metadata ya sync na ufuatiliaji wa dhahabu FIFO.
  /// Migration ni additive; haibadilishi au kufuta rekodi za v5.
  Future<void> _migrateToV7(Database db) async {
    // onCreate/onUpgrade za sqflite tayari ziko ndani ya transaction.
    final txn = db;
    await txn.execute('''CREATE TABLE IF NOT EXISTS app_metadata (
        key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    var deviceRows = await txn.query('app_metadata',
        where: 'key = ?', whereArgs: ['device_id'], limit: 1);
    if (deviceRows.isEmpty) {
      await txn
          .insert('app_metadata', {'key': 'device_id', 'value': newUuid()});
      deviceRows = await txn.query('app_metadata',
          where: 'key = ?', whereArgs: ['device_id'], limit: 1);
    }
    final deviceId = deviceRows.first['value'] as String;

    const syncTables = [
      'companies',
      'mines',
      'production_records',
      'ore_batches',
      'batch_movements',
      'processing_records',
      'workers',
      'attendance',
      'payroll_payments',
      'finance_transactions',
      'debts',
      'debt_payments',
      'inventory_items',
      'inventory_movements',
      'sales',
      'audit_log',
      'gold_inventory',
      'gold_sale_allocations'
    ];
    final tableRows =
        await txn.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final existingTables = tableRows.map((r) => r['name'] as String).toSet();
    for (final table in syncTables) {
      if (!existingTables.contains(table)) continue;
      final info = await txn.rawQuery('PRAGMA table_info($table)');
      final columns = info.map((r) => r['name'] as String).toSet();
      final additions = <String, String>{
        'updated_at': 'TEXT',
        'device_id': 'TEXT',
        'version': 'INTEGER NOT NULL DEFAULT 1',
        'deleted_at': 'TEXT',
      };
      for (final entry in additions.entries) {
        if (!columns.contains(entry.key)) {
          await txn.execute(
              'ALTER TABLE $table ADD COLUMN ${entry.key} ${entry.value}');
        }
      }
      // Backfill metadata kwa rekodi za zamani bila kubadilisha UUID zao.
      final rows = await txn.query(table);
      for (final row in rows) {
        final id = row['id'];
        if (id == null) continue;
        final updates = <String, Object?>{};
        if (row['updated_at'] == null || row['updated_at'] == '') {
          updates['updated_at'] = row['created_at'] ??
              row['sale_date'] ??
              row['processing_date'] ??
              row['shift_date'] ??
              nowIso();
        }
        if (row['device_id'] == null || row['device_id'] == '') {
          updates['device_id'] = deviceId;
        }
        if (row['version'] == null) updates['version'] = 1;
        if (row['deleted_at'] == null &&
            row.containsKey('voided') &&
            intv(row['voided']) == 1) {
          updates['deleted_at'] = row['updated_at'] ?? nowIso();
        }
        if (updates.isNotEmpty) {
          await txn.update(table, updates, where: 'id = ?', whereArgs: [id]);
        }
      }
    }

    // Metadata za Batch: hifadhi uzito wa awali na uhusiano wa chanzo kwa UUID.
    final batchInfo = await txn.rawQuery('PRAGMA table_info(ore_batches)');
    final batchCols = batchInfo.map((r) => r['name'] as String).toSet();
    const batchAdds = {
      'weight_initial_kg': 'REAL NOT NULL DEFAULT 0',
      'parent_batch_uuid': 'TEXT',
      'source_production_uuid': 'TEXT',
    };
    for (final e in batchAdds.entries) {
      if (!batchCols.contains(e.key)) {
        await txn
            .execute('ALTER TABLE ore_batches ADD COLUMN ${e.key} ${e.value}');
      }
    }
    final movementInfo =
        await txn.rawQuery('PRAGMA table_info(batch_movements)');
    final movementCols = movementInfo.map((r) => r['name'] as String).toSet();
    if (!movementCols.contains('child_batch_id')) {
      await txn.execute(
          'ALTER TABLE batch_movements ADD COLUMN child_batch_id TEXT');
    }

    await txn.execute('''UPDATE ore_batches SET
        weight_initial_kg = CASE WHEN weight_initial_kg = 0 THEN IFNULL(initial_weight_kg, weight_kg) ELSE weight_initial_kg END
        WHERE weight_initial_kg = 0''');
    final batches = await txn.query('ore_batches');
    for (final b in batches) {
      final company = b['company_id'];
      final bid = b['batch_id'];
      final parentId = b['parent_batch_id'];
      if (parentId != null &&
          (b['parent_batch_uuid'] == null || b['parent_batch_uuid'] == '')) {
        final parents = await txn.query('ore_batches',
            columns: ['uuid'],
            where: 'company_id = ? AND batch_id = ?',
            whereArgs: [company, parentId],
            limit: 1);
        if (parents.isNotEmpty) {
          await txn.update(
              'ore_batches', {'parent_batch_uuid': parents.first['uuid']},
              where: 'id = ?', whereArgs: [b['id']]);
        }
      }
      if (b['source_production_uuid'] == null ||
          b['source_production_uuid'] == '') {
        final source = await txn.query('production_records',
            columns: ['uuid'],
            where: 'company_id = ? AND batch_id = ?',
            whereArgs: [company, bid],
            limit: 1);
        if (source.isNotEmpty) {
          await txn.update(
              'ore_batches', {'source_production_uuid': source.first['uuid']},
              where: 'id = ?', whereArgs: [b['id']]);
        }
      }
    }

    // Inventory ya dhahabu na allocations za mauzo (FIFO).
    await txn.execute('''CREATE TABLE IF NOT EXISTS gold_inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        company_id TEXT NOT NULL,
        mine_id TEXT NOT NULL,
        processing_uuid TEXT NOT NULL UNIQUE,
        batch_id TEXT NOT NULL,
        grams_initial REAL NOT NULL,
        grams_available REAL NOT NULL,
        purity_percent REAL,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        device_id TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'Pending'
      )''');
    await txn.execute('''CREATE TABLE IF NOT EXISTS gold_sale_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        sale_uuid TEXT NOT NULL,
        lot_uuid TEXT NOT NULL,
        grams REAL NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        device_id TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'Pending'
      )''');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_gold_lot_fifo ON gold_inventory(company_id, mine_id, created_at, id)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_gold_alloc_sale ON gold_sale_allocations(sale_uuid)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_gold_alloc_lot ON gold_sale_allocations(lot_uuid)');
    existingTables.add('gold_inventory');
    existingTables.add('gold_sale_allocations');

    // Backfill lot moja kwa kila uchakataji wa zamani, kisha tenga mauzo ya zamani FIFO.
    final lotCount = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM gold_inventory')) ??
        0;
    if (lotCount == 0) {
      final processing = await txn.query('processing_records',
          where: 'voided = 0 AND gold_recovered_g > 0',
          orderBy: 'processing_date ASC, id ASC');
      for (final p in processing) {
        final grams = dbl(p['gold_recovered_g']);
        final lotUuid = newUuid();
        await txn.insert('gold_inventory', {
          'uuid': lotUuid,
          'company_id': p['company_id'],
          'mine_id': p['mine_id'],
          'processing_uuid': p['uuid'],
          'batch_id': p['batch_id'],
          'grams_initial': grams,
          'grams_available': grams,
          'purity_percent': p['purity_percent'],
          'created_at': p['created_at'] ?? p['processing_date'],
          'updated_at': nowIso(),
          'device_id': deviceId,
          'version': 1,
          'sync_status': 'Pending'
        });
      }
      final sales = await txn.query('sales',
          where: 'voided = 0 AND gold_weight_g > 0',
          orderBy: 'sale_date ASC, id ASC');
      for (final sale in sales) {
        var remaining = dbl(sale['gold_weight_g']);
        final lots = await txn.query('gold_inventory',
            where:
                'company_id = ? AND mine_id = ? AND grams_available > 0 AND deleted_at IS NULL',
            whereArgs: [sale['company_id'], sale['mine_id']],
            orderBy: 'created_at ASC, id ASC');
        for (final lot in lots) {
          if (remaining <= 0.000001) break;
          final available = dbl(lot['grams_available']);
          final take = available < remaining ? available : remaining;
          if (take <= 0) continue;
          await txn.update(
              'gold_inventory',
              {
                'grams_available': available - take,
                'updated_at': nowIso(),
                'version': (intv(lot['version']) + 1),
                'sync_status': 'Pending'
              },
              where: 'id = ?',
              whereArgs: [lot['id']]);
          await txn.insert('gold_sale_allocations', {
            'uuid': newUuid(),
            'sale_uuid': sale['uuid'],
            'lot_uuid': lot['uuid'],
            'grams': take,
            'created_at': sale['sale_date'],
            'updated_at': nowIso(),
            'device_id': deviceId,
            'version': 1,
            'deleted_at': null,
            'sync_status': 'Pending'
          });
          remaining -= take;
        }
        if (remaining > 0.000001) {
          await txn.insert('audit_log', {
            ...meta(),
            'device_id': deviceId,
            'company_id': sale['company_id'],
            'entity': 'sale',
            'entity_uuid': sale['uuid'],
            'action': 'MIGRATION_WARNING',
            'detail':
                'Mauzo ya zamani yalizidi gold lots zilizoweza kuthibitishwa kwa ${fmtNum(remaining)} g; hakiki taarifa za kihistoria.',
            'user_name': 'Migration v7'
          });
        }
      }
    }

    // Trigger huweka updated_at/version/device_id hata pale UI inaposasisha rekodi.
    for (final table in syncTables) {
      if (!existingTables.contains(table)) continue;
      final trigger = 'trg_${table}_v7_meta';
      await txn.execute('DROP TRIGGER IF EXISTS $trigger');
      final triggerInfo = await txn.rawQuery('PRAGMA table_info($table)');
      final hasVoided = triggerInfo.any((r) => r['name'] == 'voided');
      final deletedExpr = hasVoided
          ? "CASE WHEN NEW.voided = 1 THEN COALESCE(NEW.deleted_at, strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) ELSE NEW.deleted_at END"
          : 'NEW.deleted_at';
      await txn.execute('''CREATE TRIGGER $trigger AFTER UPDATE ON $table
          FOR EACH ROW BEGIN
            UPDATE $table SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
              device_id = COALESCE(NULLIF(NEW.device_id, ''), '$deviceId'),
              version = MAX(COALESCE(NEW.version, 1), COALESCE(OLD.version, 1) + 1),
              deleted_at = $deletedExpr
            WHERE id = NEW.id;
          END''');
    }
  }

  Future<String> getDeviceId() async {
    final db = await database;
    final rows = await db.query('app_metadata',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['device_id'],
        limit: 1);
    return rows.isEmpty ? '' : rows.first['value'] as String;
  }

  /// Inaboresha muundo wa v4 kuwa v5 bila kupoteza data yoyote ya zamani.
  Future<void> _migrateToV5(Database db) async {
    // 1. UUID kwa kila rekodi ya zamani.
    const oldTables = [
      'production_records',
      'ore_batches',
      'batch_movements',
      'processing_records',
    ];
    for (final t in oldTables) {
      await db.execute('ALTER TABLE $t ADD COLUMN uuid TEXT');
    }

    // 2. Safu mpya kwenye majedwali ya zamani.
    const alters = [
      'ALTER TABLE production_records ADD COLUMN witness TEXT',
      'ALTER TABLE production_records ADD COLUMN voided INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE production_records ADD COLUMN void_reason TEXT',
      'ALTER TABLE ore_batches ADD COLUMN parent_batch_id TEXT',
      'ALTER TABLE ore_batches ADD COLUMN initial_weight_kg REAL',
      'ALTER TABLE batch_movements ADD COLUMN witness TEXT',
      'ALTER TABLE processing_records ADD COLUMN witness TEXT',
      'ALTER TABLE processing_records ADD COLUMN method TEXT',
      'ALTER TABLE processing_records ADD COLUMN purity_percent REAL',
      'ALTER TABLE processing_records ADD COLUMN mercury_g REAL',
      'ALTER TABLE processing_records ADD COLUMN notes TEXT',
      'ALTER TABLE processing_records ADD COLUMN created_at TEXT',
      'ALTER TABLE processing_records ADD COLUMN voided INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE processing_records ADD COLUMN void_reason TEXT',
    ];
    for (final s in alters) {
      await db.execute(s);
    }

    // 3. Rekebisha Batch za zamani ambazo uzito ulifutika baada ya uhamisho.
    await db.execute('''
      UPDATE ore_batches
      SET weight_kg = (
        SELECT MAX(m.weight_kg) FROM batch_movements m
        WHERE m.company_id = ore_batches.company_id
          AND m.batch_id = ore_batches.batch_id
      )
      WHERE weight_kg = 0
        AND NOT EXISTS (
          SELECT 1 FROM processing_records p
          WHERE p.company_id = ore_batches.company_id
            AND p.batch_id = ore_batches.batch_id
        )
        AND EXISTS (
          SELECT 1 FROM batch_movements m
          WHERE m.company_id = ore_batches.company_id
            AND m.batch_id = ore_batches.batch_id
        )
    ''');

    await db.execute('''
      UPDATE ore_batches
      SET initial_weight_kg = weight_kg + IFNULL((
        SELECT SUM(p.ore_processed_kg) FROM processing_records p
        WHERE p.company_id = ore_batches.company_id
          AND p.batch_id = ore_batches.batch_id
      ), 0)
    ''');

    await db.execute(
      'UPDATE processing_records SET created_at = processing_date '
      'WHERE created_at IS NULL',
    );

    // 4. Jaza UUID kwa rekodi zilizokuwepo.
    for (final t in oldTables) {
      final rows = await db.query(t, columns: ['id']);
      for (final r in rows) {
        await db.update(
          t,
          {'uuid': newUuid()},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
      await db.execute('CREATE UNIQUE INDEX idx_${t}_uuid ON $t(uuid)');
    }

    // 5. Majedwali mapya.
    const common = '''
        uuid TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        device_id TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'Pending'
    ''';

    final creates = <String>[
      '''CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT
      )''',
      '''CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT,
        entity TEXT NOT NULL,
        entity_uuid TEXT,
        action TEXT NOT NULL,
        detail TEXT,
        user_name TEXT,
        $common
      )''',
      '''CREATE TABLE companies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        $common
      )''',
      '''CREATE TABLE mines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        name TEXT NOT NULL,
        location TEXT,
        $common,
        UNIQUE(company_id, name)
      )''',
      '''CREATE TABLE workers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        mine_id TEXT NOT NULL,
        full_name TEXT NOT NULL,
        phone TEXT,
        role TEXT NOT NULL,
        pay_type TEXT NOT NULL,
        pay_rate REAL NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        $common
      )''',
      '''CREATE TABLE attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        mine_id TEXT NOT NULL,
        worker_uuid TEXT NOT NULL,
        att_date TEXT NOT NULL,
        status TEXT NOT NULL,
        recorded_by TEXT,
        $common,
        UNIQUE(worker_uuid, att_date)
      )''',
      '''CREATE TABLE payroll_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        mine_id TEXT NOT NULL,
        worker_uuid TEXT NOT NULL,
        period_from TEXT NOT NULL,
        period_to TEXT NOT NULL,
        days_present INTEGER NOT NULL DEFAULT 0,
        gross REAL NOT NULL,
        deductions REAL NOT NULL DEFAULT 0,
        net REAL NOT NULL,
        paid_date TEXT NOT NULL,
        method TEXT,
        notes TEXT,
        paid_by TEXT,
        voided INTEGER NOT NULL DEFAULT 0,
        void_reason TEXT,
        $common
      )''',
      '''CREATE TABLE finance_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        mine_id TEXT NOT NULL,
        type TEXT NOT NULL,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        trans_date TEXT NOT NULL,
        description TEXT,
        method TEXT,
        reference TEXT,
        source TEXT NOT NULL DEFAULT 'Mkono',
        source_uuid TEXT,
        created_by TEXT,
        voided INTEGER NOT NULL DEFAULT 0,
        void_reason TEXT,
        $common
      )''',
      '''CREATE TABLE debts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        mine_id TEXT NOT NULL,
        direction TEXT NOT NULL,
        party TEXT NOT NULL,
        amount REAL NOT NULL,
        due_date TEXT,
        description TEXT,
        created_by TEXT,
        voided INTEGER NOT NULL DEFAULT 0,
        void_reason TEXT,
        $common
      )''',
      '''CREATE TABLE debt_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        debt_uuid TEXT NOT NULL,
        amount REAL NOT NULL,
        pay_date TEXT NOT NULL,
        method TEXT,
        notes TEXT,
        created_by TEXT,
        $common
      )''',
      '''CREATE TABLE inventory_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        mine_id TEXT NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        unit TEXT NOT NULL,
        min_level REAL NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        $common,
        UNIQUE(company_id, mine_id, name)
      )''',
      '''CREATE TABLE inventory_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        mine_id TEXT NOT NULL,
        item_uuid TEXT NOT NULL,
        move_type TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_cost REAL,
        move_date TEXT NOT NULL,
        notes TEXT,
        created_by TEXT,
        voided INTEGER NOT NULL DEFAULT 0,
        void_reason TEXT,
        $common
      )''',
      '''CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        mine_id TEXT NOT NULL,
        sale_date TEXT NOT NULL,
        buyer TEXT NOT NULL,
        buyer_license TEXT,
        gold_weight_g REAL NOT NULL,
        purity_percent REAL NOT NULL,
        price_per_g REAL NOT NULL,
        gross_amount REAL NOT NULL,
        royalty_percent REAL NOT NULL DEFAULT 0,
        royalty_amount REAL NOT NULL DEFAULT 0,
        inspection_percent REAL NOT NULL DEFAULT 0,
        inspection_amount REAL NOT NULL DEFAULT 0,
        other_fees REAL NOT NULL DEFAULT 0,
        net_amount REAL NOT NULL,
        payment_method TEXT,
        reference TEXT,
        witness TEXT,
        notes TEXT,
        created_by TEXT,
        voided INTEGER NOT NULL DEFAULT 0,
        void_reason TEXT,
        $common
      )''',
    ];
    for (final s in creates) {
      await db.execute(s);
    }

    const indexes = [
      'CREATE INDEX idx_workers_scope ON workers(company_id, mine_id)',
      'CREATE INDEX idx_attendance_date ON attendance(att_date)',
      'CREATE INDEX idx_fin_scope ON finance_transactions(company_id, mine_id, trans_date)',
      'CREATE INDEX idx_fin_source ON finance_transactions(source, source_uuid)',
      'CREATE INDEX idx_debt_pay ON debt_payments(debt_uuid)',
      'CREATE INDEX idx_inv_mov ON inventory_movements(item_uuid)',
      'CREATE INDEX idx_sales_scope ON sales(company_id, mine_id, sale_date)',
      'CREATE INDEX idx_audit_time ON audit_log(created_at)',
    ];
    for (final s in indexes) {
      await db.execute(s);
    }

    // 6. Tengeneza kampuni na migodi kutoka kwenye rekodi za zamani.
    final pairs = await db.rawQuery('''
      SELECT DISTINCT company_id, mine_id FROM production_records
      UNION SELECT DISTINCT company_id, mine_id FROM ore_batches
      UNION SELECT DISTINCT company_id, mine_id FROM processing_records
    ''');
    for (final p in pairs) {
      final c = (p['company_id'] as String? ?? '').trim();
      final m = (p['mine_id'] as String? ?? '').trim();
      if (c.isEmpty) continue;
      await db.insert(
        'companies',
        {...meta(), 'name': c},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (m.isNotEmpty) {
        await db.insert(
          'mines',
          {...meta(), 'company_id': c, 'name': m},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Mipangilio
  // -------------------------------------------------------------------------
  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['setting_value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSetting(String key) async {
    final db = await database;
    await db.delete('app_settings', where: 'setting_key = ?', whereArgs: [key]);
  }

  // -------------------------------------------------------------------------
  // Kampuni na migodi
  // -------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCompanies() async {
    final db = await database;
    return db.query('companies', orderBy: 'name COLLATE NOCASE');
  }

  Future<List<Map<String, dynamic>>> getMines(String company) async {
    final db = await database;
    return db.query(
      'mines',
      where: 'company_id = ?',
      whereArgs: [company],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<void> addCompany({
    required String name,
    required String mineName,
    String? location,
  }) async {
    final n = name.trim();
    final m = mineName.trim();
    if (n.isEmpty || m.isEmpty) {
      throw AppError('Jina la kampuni na mgodi vinahitajika.');
    }

    final db = await database;
    await db.transaction((txn) async {
      final dup = await txn.rawQuery(
        'SELECT 1 FROM companies WHERE LOWER(name) = LOWER(?)',
        [n],
      );
      if (dup.isNotEmpty) throw AppError('Kampuni hii tayari ipo.');

      final cm = meta();
      await txn.insert('companies', {...cm, 'name': n});
      await txn.insert('mines', {
        ...meta(),
        'company_id': n,
        'name': m,
        'location': location,
      });
      await writeAudit(
        txn,
        entity: 'company',
        entityUuid: cm['uuid'] as String,
        action: 'Imeundwa',
        detail: '$n / $m',
        company: n,
      );
    });
  }

  Future<void> addMine({
    required String company,
    required String name,
    String? location,
  }) async {
    final n = name.trim();
    if (n.isEmpty) throw AppError('Jina la mgodi linahitajika.');

    final db = await database;
    await db.transaction((txn) async {
      final dup = await txn.rawQuery(
        'SELECT 1 FROM mines WHERE company_id = ? AND LOWER(name) = LOWER(?)',
        [company, n],
      );
      if (dup.isNotEmpty) {
        throw AppError('Mgodi huu tayari upo kwenye kampuni hii.');
      }

      final mm = meta();
      await txn.insert('mines', {
        ...mm,
        'company_id': company,
        'name': n,
        'location': location,
      });
      await writeAudit(
        txn,
        entity: 'mine',
        entityUuid: mm['uuid'] as String,
        action: 'Umeundwa',
        detail: n,
        company: company,
      );
    });
  }

  // -------------------------------------------------------------------------
  // Uzalishaji
  // -------------------------------------------------------------------------
  Future<String> _batchDeviceTag() async {
    final deviceId = (await getDeviceId())
        .replaceAll(RegExp(r'[^a-fA-F0-9]'), '')
        .toUpperCase();
    if (deviceId.length != 32) {
      throw AppError(
        'Utambulisho wa kifaa haujakamilika. Fungua upya usanidi wa kifaa '
        'kabla ya kutengeneza Batch.',
      );
    }
    return deviceId.substring(deviceId.length - 12);
  }

  Future<bool> _batchIdExists(DatabaseExecutor executor, String batchId) async {
    final batches = await executor.query(
      'ore_batches',
      columns: ['id'],
      where: 'company_id = ? AND batch_id = ?',
      whereArgs: [AppCtx.company, batchId],
      limit: 1,
    );
    if (batches.isNotEmpty) return true;
    final production = await executor.query(
      'production_records',
      columns: ['id'],
      where: 'company_id = ? AND batch_id = ?',
      whereArgs: [AppCtx.company, batchId],
      limit: 1,
    );
    return production.isNotEmpty;
  }

  Future<String> nextBatchId() async {
    final db = await database;
    final deviceTag = await _batchDeviceTag();
    final now = DateTime.now();
    final prefix = 'B'
        '${(now.year % 100).toString().padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '-$deviceTag';

    var n = (Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM ore_batches '
              'WHERE company_id = ? AND batch_id LIKE ?',
              [AppCtx.company, '$prefix-%'],
            )) ??
            0) +
        1;

    while (true) {
      final id = '$prefix-${n.toString().padLeft(4, '0')}';
      if (!await _batchIdExists(db, id)) return id;
      n++;
    }
  }

  /// Inarekodi uzalishaji NA kutengeneza Batch yake kwa pamoja (transaction).
  Future<void> recordProduction({
    required String shaft,
    required String batchId,
    required String shiftDate,
    required String shiftType,
    required int bags,
    required double weightKg,
    double? grade,
    String? witness,
    String? witnessUserUuid,
  }) async {
    AppCtx.requireWrite();
    if (bags <= 0 || weightKg <= 0) {
      throw AppError('Magunia na uzito lazima viwe zaidi ya sifuri.');
    }
    checkWitness(witness);

    final db = await database;
    await db.transaction((txn) async {
      if (await _batchIdExists(txn, batchId)) {
        throw AppError('Batch ID hii tayari imetumika kwenye kampuni hii.');
      }

      final pm = meta();
      await txn.insert('production_records', {
        ...pm,
        'company_id': AppCtx.company,
        'mine_id': AppCtx.mine,
        'shaft_area': shaft,
        'batch_id': batchId,
        'shift_date': shiftDate,
        'shift_type': shiftType,
        'bags_count': bags,
        'weight_kg': weightKg,
        'estimated_grade': grade,
        'recorded_by': AppCtx.user,
        'witness': (witness ?? '').trim().isEmpty ? null : witness!.trim(),
        'witness_user_uuid': witnessUserUuid,
        'witness_verified': witnessUserUuid == null ? 0 : 1,
        'voided': 0,
      });

      await txn.insert('ore_batches', {
        ...meta(),
        'company_id': AppCtx.company,
        'mine_id': AppCtx.mine,
        'batch_id': batchId,
        'source_location': shaft,
        'current_location': shaft,
        'weight_kg': weightKg,
        'initial_weight_kg': weightKg,
        'weight_initial_kg': weightKg,
        'source_production_uuid': pm['uuid'],
        'status': 'Imechimbwa',
      });

      await writeAudit(
        txn,
        entity: 'production',
        entityUuid: pm['uuid'] as String,
        action: 'Imerekodiwa',
        detail: 'Batch $batchId, ${fmtNum(weightKg)} kg',
      );
    });
  }

  Future<List<Map<String, dynamic>>> getProductionRecords({
    String? from,
    String? to,
    bool allMines = false,
    int? limit,
  }) async {
    final db = await database;
    final dc = dateClause('shift_date', from, to);
    return db.rawQuery(
      'SELECT * FROM production_records WHERE ${scopeWhere(allMines)}'
      '${dc.sql} ORDER BY shift_date DESC, id DESC'
      '${limit == null ? '' : ' LIMIT $limit'}',
      [...scopeArgs(allMines), ...dc.args],
    );
  }

  Future<void> voidProduction(String uuid, String reason) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'production_records',
        where: 'uuid = ?',
        whereArgs: [uuid],
        limit: 1,
      );
      if (rows.isEmpty) throw AppError('Rekodi haijapatikana.');
      final r = rows.first;
      if (intv(r['voided']) == 1) throw AppError('Rekodi hii tayari imefutwa.');

      final cid = r['company_id'] as String;
      final bid = r['batch_id'] as String;

      final mv = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM batch_movements '
              'WHERE company_id = ? AND batch_id = ?',
              [cid, bid])) ??
          0;
      final pr = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM processing_records '
              'WHERE company_id = ? AND batch_id = ? AND voided = 0',
              [cid, bid])) ??
          0;
      final ch = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM ore_batches '
              'WHERE company_id = ? AND parent_batch_id = ?',
              [cid, bid])) ??
          0;
      if (mv + pr + ch > 0) {
        throw AppError(
          'Batch hii tayari imehamishwa au kuchakatwa, kwa hiyo haiwezi kufutwa.',
        );
      }

      await txn.update(
        'production_records',
        {'voided': 1, 'void_reason': reason, 'sync_status': 'Pending'},
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      await txn.update(
        'ore_batches',
        {'status': 'Imefutwa', 'weight_kg': 0.0, 'sync_status': 'Pending'},
        where: 'company_id = ? AND batch_id = ?',
        whereArgs: [cid, bid],
      );
      // Hifadhi historia: Batch ID ya asili inahamia `original_batch_id`, UUID
      // hazibadiliki, na ID inaweza kutumika tena bila kuvunja UNIQUE.
      final archivedId = '$bid~V${uuid.substring(0, 8)}';
      for (final sql in kArchiveBatchStatements) {
        await txn.rawUpdate(sql, [archivedId, cid, bid]);
      }
      await writeAudit(
        txn,
        entity: 'production',
        entityUuid: uuid,
        action: 'Imefutwa',
        detail: 'Batch $bid. Sababu: $reason',
        company: cid,
      );
    });
  }

  // Njia za zamani zinazobaki kwa ajili ya sync ya baadaye.
  Future<List<Map<String, dynamic>>> getUnsyncedRecords() async {
    final db = await database;
    return db.query(
      'production_records',
      where: 'sync_status = ?',
      whereArgs: ['Pending'],
      orderBy: 'id ASC',
    );
  }

  Future<int> markAsSynced(int id) async {
    final db = await database;
    return db.update(
      'production_records',
      {'sync_status': 'Synced'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Hutoa batch ya rekodi zinazosubiri kwa adapter ya sync ya backend ya baadaye.
  Future<Map<String, List<Map<String, dynamic>>>> getPendingSyncBundle({
    int limitPerTable = 500,
  }) async {
    if (limitPerTable < 1 || limitPerTable > 5000) {
      throw ArgumentError('Limit ya sync lazima iwe kati ya 1 na 5000.');
    }
    final db = await database;
    final bundle = <String, List<Map<String, dynamic>>>{};
    for (final table in kSyncTables) {
      bundle[table] = await db.query(
        table,
        where: 'sync_status = ?',
        whereArgs: ['Pending'],
        orderBy: 'id ASC',
        limit: limitPerTable,
      );
    }
    return bundle;
  }

  // -------------------------------------------------------------------------
  // Batch na uhamisho
  // -------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getAllBatches({
    bool allMines = false,
    bool onlyAvailable = false,
  }) async {
    final db = await database;
    return db.rawQuery(
      'SELECT * FROM ore_batches WHERE ${scopeWhere(allMines)}'
      "${onlyAvailable ? " AND weight_kg > 0 AND status != 'Imefutwa'" : ''}"
      ' ORDER BY id DESC',
      scopeArgs(allMines),
    );
  }

  Future<Map<String, dynamic>?> getBatch(String batchId) async {
    final db = await database;
    final rows = await db.query(
      'ore_batches',
      where: 'company_id = ? AND batch_id = ?',
      whereArgs: [AppCtx.company, batchId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Kusajili Batch kwa mkono (mfano ore iliyonunuliwa au kuhamishwa kutoka nje).
  Future<void> registerBatch({
    required String batchId,
    required String sourceLocation,
    required double weightKg,
  }) async {
    if (weightKg <= 0) throw AppError('Uzito lazima uwe zaidi ya sifuri.');

    final db = await database;
    await db.transaction((txn) async {
      final exists = await txn.query(
        'ore_batches',
        where: 'company_id = ? AND batch_id = ?',
        whereArgs: [AppCtx.company, batchId],
        limit: 1,
      );
      if (exists.isNotEmpty) {
        throw AppError('Batch ID hii tayari imetumika kwenye kampuni hii.');
      }

      final bm = meta();
      await txn.insert('ore_batches', {
        ...bm,
        'company_id': AppCtx.company,
        'mine_id': AppCtx.mine,
        'batch_id': batchId,
        'source_location': sourceLocation,
        'current_location': sourceLocation,
        'weight_kg': weightKg,
        'initial_weight_kg': weightKg,
        'weight_initial_kg': weightKg,
        'status': 'Imechimbwa',
      });
      await writeAudit(
        txn,
        entity: 'batch',
        entityUuid: bm['uuid'] as String,
        action: 'Imesajiliwa',
        detail: 'Batch $batchId, ${fmtNum(weightKg)} kg',
      );
    });
  }

  /// Inahamisha Batch nzima, au sehemu yake (ikigawanywa, Batch mpya
  /// ya mtoto inaundwa). Inarudisha ID ya Batch iliyohamishwa.
  Future<String> moveBatch({
    required String batchId,
    required String toLocation,
    required double weightKg,
    String? witness,
    String? notes,
  }) async {
    AppCtx.requireWrite();
    if (weightKg <= 0) {
      throw AppError('Uzito lazima uwe mkubwa kuliko sifuri.');
    }
    if (toLocation.trim().isEmpty) throw AppError('Weka eneo linalopelekwa.');
    checkWitness(witness);

    final db = await database;
    final deviceTag = await _batchDeviceTag();
    return db.transaction<String>((txn) async {
      final rows = await txn.query(
        'ore_batches',
        where: 'company_id = ? AND batch_id = ?',
        whereArgs: [AppCtx.company, batchId],
        limit: 1,
      );
      if (rows.isEmpty) throw AppError('Batch haijapatikana.');

      final batch = rows.first;
      if (batch['status'] == 'Imefutwa') {
        throw AppError('Batch hii imefutwa.');
      }

      final available = dbl(batch['weight_kg']);
      if (weightKg > available + 0.000001) {
        throw AppError(
          'Uzito wa uhamisho (${fmtNum(weightKg)} kg) unazidi uzito uliopo '
          '(${fmtNum(available)} kg).',
        );
      }

      final fromLocation = batch['current_location'] as String;
      final w = (witness ?? '').trim().isEmpty ? null : witness!.trim();
      final isFull = (available - weightKg).abs() < 0.000001;
      final status = batch['status'] as String;
      final newStatus = (status == 'Imechimbwa' || status == 'Imehamishwa')
          ? 'Imehamishwa'
          : status;

      String resultId = batchId;

      if (isFull) {
        await txn.insert('batch_movements', {
          ...meta(),
          'company_id': AppCtx.company,
          'batch_id': batchId,
          'from_location': fromLocation,
          'to_location': toLocation.trim(),
          'weight_kg': weightKg,
          'movement_date': nowIso(),
          'moved_by': AppCtx.user,
          'witness': w,
          'notes': notes,
        });
        await txn.update(
          'ore_batches',
          {
            'current_location': toLocation.trim(),
            'status': newStatus,
            'sync_status': 'Pending',
          },
          where: 'company_id = ? AND batch_id = ?',
          whereArgs: [AppCtx.company, batchId],
        );
      } else {
        var n = (Sqflite.firstIntValue(await txn.rawQuery(
                  'SELECT COUNT(*) FROM ore_batches '
                  'WHERE company_id = ? AND parent_batch_id = ?',
                  [AppCtx.company, batchId],
                )) ??
                0) +
            1;
        var childId = '$batchId-S$deviceTag-$n';
        while (await _batchIdExists(txn, childId)) {
          n++;
          childId = '$batchId-S$deviceTag-$n';
        }

        await txn.update(
          'ore_batches',
          {'weight_kg': available - weightKg, 'sync_status': 'Pending'},
          where: 'company_id = ? AND batch_id = ?',
          whereArgs: [AppCtx.company, batchId],
        );

        await txn.insert('ore_batches', {
          ...meta(),
          'company_id': AppCtx.company,
          'mine_id': batch['mine_id'],
          'batch_id': childId,
          'source_location': batch['source_location'],
          'current_location': toLocation.trim(),
          'weight_kg': weightKg,
          'initial_weight_kg': weightKg,
          'weight_initial_kg': weightKg,
          'status': 'Imehamishwa',
          'parent_batch_id': batchId,
          'parent_batch_uuid': batch['uuid'],
          'source_production_uuid': batch['source_production_uuid'],
        });

        await txn.insert('batch_movements', {
          ...meta(),
          'company_id': AppCtx.company,
          'batch_id': batchId,
          'child_batch_id': childId,
          'from_location': fromLocation,
          'to_location': toLocation.trim(),
          'weight_kg': weightKg,
          'movement_date': nowIso(),
          'moved_by': AppCtx.user,
          'witness': w,
          'notes': 'Imegawanywa: Batch mpya $childId. ${notes ?? ''}'.trim(),
        });
        await txn.insert('batch_movements', {
          ...meta(),
          'company_id': AppCtx.company,
          'batch_id': childId,
          'from_location': fromLocation,
          'to_location': toLocation.trim(),
          'weight_kg': weightKg,
          'movement_date': nowIso(),
          'moved_by': AppCtx.user,
          'witness': w,
          'notes': 'Imetokana na $batchId',
        });
        resultId = childId;
      }

      await writeAudit(
        txn,
        entity: 'batch',
        entityUuid: batch['uuid'] as String?,
        action: 'Imehamishwa',
        detail: '$batchId → ${toLocation.trim()}, ${fmtNum(weightKg)} kg'
            '${isFull ? '' : ' (Batch mpya $resultId)'}',
      );
      return resultId;
    });
  }

  /// Huunganisha mabaki ya Batch mbili au zaidi za kampuni/mgodi uleule.
  /// Kila chanzo, movement, Batch mpya na audit huandikwa kwa transaction moja.
  Future<String> mergeBatches({
    required List<String> batchIds,
    required String targetLocation,
    String? witness,
    String? notes,
  }) async {
    AppCtx.requireWrite();
    final ids = batchIds.map((id) => id.trim()).toList();
    final location = targetLocation.trim();
    if (ids.length < 2 ||
        ids.any((id) => id.isEmpty) ||
        ids.toSet().length != ids.length) {
      throw AppError('Chagua Batch mbili au zaidi tofauti.');
    }
    if (location.isEmpty) throw AppError('Weka eneo la Batch mpya.');
    checkWitness(witness);

    final db = await database;
    final deviceTag = await _batchDeviceTag();
    return db.transaction<String>((txn) async {
      final sources = <Map<String, dynamic>>[];
      for (final id in ids) {
        final rows = await txn.query(
          'ore_batches',
          where: 'company_id = ? AND mine_id = ? AND batch_id = ?',
          whereArgs: [AppCtx.company, AppCtx.mine, id],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw AppError('Batch $id haijapatikana kwenye mgodi huu.');
        }
        final source = rows.single;
        if (source['status'] == 'Imefutwa' ||
            source['status'] == 'Imeunganishwa') {
          throw AppError(
              'Batch $id haiwezi kuunganishwa katika hali yake ya sasa.');
        }
        if (dbl(source['weight_kg']) <= 0) {
          throw AppError('Batch $id haina ore iliyobaki.');
        }
        sources.add(source);
      }

      final totalWeight = sources.fold<double>(
        0,
        (total, source) => total + dbl(source['weight_kg']),
      );
      final parent = sources.first;
      final parentBatchId = parent['batch_id'] as String;
      final parentUuid = parent['uuid'] as String;
      var targetBatchId = '';
      var targetUuid = '';
      do {
        targetUuid = newUuid();
        targetBatchId =
            'M-$deviceTag-${targetUuid.substring(0, 8).toUpperCase()}';
      } while (await _batchIdExists(txn, targetBatchId));

      await txn.insert('ore_batches', {
        ...meta(),
        'uuid': targetUuid,
        'company_id': AppCtx.company,
        'mine_id': AppCtx.mine,
        'batch_id': targetBatchId,
        'source_location': parent['source_location'],
        'current_location': location,
        'weight_kg': totalWeight,
        'initial_weight_kg': totalWeight,
        'weight_initial_kg': totalWeight,
        'status': 'Imehamishwa',
        'parent_batch_id': parentBatchId,
        'parent_batch_uuid': parentUuid,
        'source_production_uuid': parent['source_production_uuid'],
      });

      final movedAt = nowIso();
      final witnessName = (witness ?? '').trim();
      for (final source in sources) {
        final sourceId = source['batch_id'] as String;
        final sourceUuid = source['uuid'] as String;
        final sourceWeight = dbl(source['weight_kg']);
        final changed = await txn.update(
          'ore_batches',
          {
            'weight_kg': 0.0,
            'status': 'Imeunganishwa',
            'sync_status': 'Pending',
          },
          where: 'uuid = ? AND company_id = ? AND mine_id = ? '
              'AND batch_id = ? AND weight_kg = ? AND status = ?',
          whereArgs: [
            sourceUuid,
            AppCtx.company,
            AppCtx.mine,
            sourceId,
            source['weight_kg'],
            source['status'],
          ],
        );
        if (changed != 1) {
          throw AppError('Batch $sourceId imebadilika; jaribu tena.');
        }

        final detail = (notes ?? '').trim();
        await txn.insert('batch_movements', {
          ...meta(),
          'company_id': AppCtx.company,
          'batch_id': sourceId,
          'child_batch_id': targetBatchId,
          'from_location': source['current_location'],
          'to_location': location,
          'weight_kg': sourceWeight,
          'movement_date': movedAt,
          'moved_by': AppCtx.user,
          'witness': witnessName.isEmpty ? null : witnessName,
          'notes':
              'Imeunganishwa kuwa Batch $targetBatchId${detail.isEmpty ? '' : '. $detail'}',
        });
        await txn.insert('batch_movements', {
          ...meta(),
          'company_id': AppCtx.company,
          'batch_id': targetBatchId,
          'from_location': source['current_location'],
          'to_location': location,
          'weight_kg': sourceWeight,
          'movement_date': movedAt,
          'moved_by': AppCtx.user,
          'witness': witnessName.isEmpty ? null : witnessName,
          'notes':
              'Chanzo: Batch $sourceId${detail.isEmpty ? '' : '. $detail'}',
        });
      }

      await writeAudit(
        txn,
        entity: 'batch_merge',
        entityUuid: targetUuid,
        action: 'Batch zimeunganishwa',
        detail:
            '${sources.map((s) => '${s['batch_id']} (${fmtNum(dbl(s['weight_kg']))} kg)').join(', ')}'
            ' → $targetBatchId (${fmtNum(totalWeight)} kg).'
            '${(notes ?? '').trim().isEmpty ? '' : ' ${notes!.trim()}'}',
      );
      return targetBatchId;
    });
  }

  Future<List<Map<String, dynamic>>> getBatchHistory(String batchId) async {
    final db = await database;
    return db.query(
      'batch_movements',
      where: 'company_id = ? AND batch_id = ?',
      whereArgs: [AppCtx.company, batchId],
      orderBy: 'id DESC',
    );
  }

  // -------------------------------------------------------------------------
  // Uchakataji na dhahabu iliyopatikana
  // -------------------------------------------------------------------------
  Future<double?> estimatedGradeForBatch(String batchId) async {
    final db = await database;
    var current = batchId;
    for (var i = 0; i < 12; i++) {
      final p = await db.query(
        'production_records',
        columns: ['estimated_grade'],
        where: 'company_id = ? AND batch_id = ? AND voided = 0',
        whereArgs: [AppCtx.company, current],
        limit: 1,
      );
      if (p.isNotEmpty) return (p.first['estimated_grade'] as num?)?.toDouble();

      final b = await db.query(
        'ore_batches',
        columns: ['parent_batch_id'],
        where: 'company_id = ? AND batch_id = ?',
        whereArgs: [AppCtx.company, current],
        limit: 1,
      );
      if (b.isEmpty || b.first['parent_batch_id'] == null) return null;
      current = b.first['parent_batch_id'] as String;
    }
    return null;
  }

  Future<String> processBatch({
    required String batchId,
    required double oreProcessedKg,
    required double goldRecoveredG,
    required double tailingsKg,
    required double processingCost,
    required String processingDate,
    String? method,
    double? purityPercent,
    double? mercuryG,
    String? witness,
    String? notes,
  }) async {
    AppCtx.requireWrite();
    if (oreProcessedKg <= 0 ||
        goldRecoveredG < 0 ||
        tailingsKg < 0 ||
        processingCost < 0) {
      throw AppError('Taarifa za uchakataji si sahihi.');
    }
    if (tailingsKg > oreProcessedKg + 0.000001) {
      throw AppError('Mabaki (tailings) hayawezi kuzidi ore iliyochakatwa.');
    }
    if (purityPercent != null && (purityPercent <= 0 || purityPercent > 100)) {
      throw AppError('Purity lazima iwe kati ya 0 na 100.');
    }
    checkWitness(witness);

    final db = await database;
    return db.transaction<String>((txn) async {
      final batches = await txn.query(
        'ore_batches',
        where: 'company_id = ? AND batch_id = ?',
        whereArgs: [AppCtx.company, batchId],
        limit: 1,
      );
      if (batches.isEmpty) throw AppError('Batch haijapatikana.');

      final batch = batches.first;
      if (batch['status'] == 'Imefutwa') throw AppError('Batch hii imefutwa.');

      final remainingWeight = dbl(batch['weight_kg']);
      if (oreProcessedKg > remainingWeight + 0.000001) {
        throw AppError(
          'Ore (${fmtNum(oreProcessedKg)} kg) inazidi uzito uliobaki '
          '(${fmtNum(remainingWeight)} kg).',
        );
      }

      final remaining = remainingWeight - oreProcessedKg;
      final done = remaining < 0.000001;

      final pm = meta();
      await txn.insert('processing_records', {
        ...pm,
        'company_id': AppCtx.company,
        'mine_id': batch['mine_id'],
        'batch_id': batchId,
        'ore_processed_kg': oreProcessedKg,
        'gold_recovered_g': goldRecoveredG,
        'tailings_kg': tailingsKg,
        'processing_cost': processingCost,
        'processing_date': processingDate,
        'processed_by': AppCtx.user,
        'witness': (witness ?? '').trim().isEmpty ? null : witness!.trim(),
        'method': method,
        'purity_percent': purityPercent,
        'mercury_g': mercuryG,
        'notes': notes,
        'voided': 0,
      });

      if (goldRecoveredG > 0) {
        await txn.insert('gold_inventory', {
          'uuid': newUuid(),
          'company_id': AppCtx.company,
          'mine_id': batch['mine_id'],
          'processing_uuid': pm['uuid'],
          'batch_id': batchId,
          'grams_initial': goldRecoveredG,
          'grams_available': goldRecoveredG,
          'purity_percent': purityPercent,
          'created_at': processingDate,
          'updated_at': nowIso(),
          'device_id': AppCtx.deviceId,
          'version': 1,
          'deleted_at': null,
          'sync_status': 'Pending',
        });
      }

      await txn.update(
        'ore_batches',
        {
          'weight_kg': done ? 0.0 : remaining,
          'status': done ? 'Imechakatwa' : 'Inaendelea kuchakatwa',
          'sync_status': 'Pending',
        },
        where: 'company_id = ? AND batch_id = ?',
        whereArgs: [AppCtx.company, batchId],
      );

      if (processingCost > 0) {
        await insertFinanceTxn(
          txn,
          type: 'Matumizi',
          category: 'Uchakataji',
          amount: processingCost,
          date: processingDate,
          description: 'Uchakataji wa Batch $batchId',
          source: 'Uchakataji',
          sourceUuid: pm['uuid'] as String,
        );
      }

      await writeAudit(
        txn,
        entity: 'processing',
        entityUuid: pm['uuid'] as String,
        action: 'Imerekodiwa',
        detail: 'Batch $batchId: ore ${fmtNum(oreProcessedKg)} kg, '
            'dhahabu ${fmtNum(goldRecoveredG)} g',
      );
      return pm['uuid'] as String;
    });
  }

  Future<List<Map<String, dynamic>>> getProcessingRecords({
    String? batchId,
    String? from,
    String? to,
    bool allMines = false,
  }) async {
    final db = await database;
    final dc = dateClause('processing_date', from, to);
    return db.rawQuery(
      'SELECT * FROM processing_records WHERE ${scopeWhere(allMines)}'
      '${batchId == null ? '' : ' AND batch_id = ?'}'
      '${dc.sql} ORDER BY processing_date DESC, id DESC',
      [...scopeArgs(allMines), if (batchId != null) batchId, ...dc.args],
    );
  }

  Future<void> voidProcessing(String uuid, String reason) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'processing_records',
        where: 'uuid = ?',
        whereArgs: [uuid],
        limit: 1,
      );
      if (rows.isEmpty) throw AppError('Rekodi haijapatikana.');
      final r = rows.first;
      if (intv(r['voided']) == 1) throw AppError('Rekodi hii tayari imefutwa.');

      final cid = r['company_id'] as String;
      final bid = r['batch_id'] as String;
      final ore = dbl(r['ore_processed_kg']);

      final lots = await txn.query('gold_inventory',
          where: 'processing_uuid = ? AND deleted_at IS NULL',
          whereArgs: [uuid]);
      for (final lot in lots) {
        final sold = await txn.rawQuery(
            '''SELECT IFNULL(SUM(a.grams),0) AS grams
          FROM gold_sale_allocations a JOIN sales s ON s.uuid = a.sale_uuid
          WHERE a.lot_uuid = ? AND s.voided = 0 AND a.deleted_at IS NULL''',
            [lot['uuid']]);
        if (dbl(sold.first['grams']) > 0.000001) {
          throw AppError(
              'Dhahabu ya uchakataji huu tayari imeuzwa. Ghairi mauzo husika kwanza.');
        }
      }

      await txn.update(
        'processing_records',
        {'voided': 1, 'void_reason': reason, 'sync_status': 'Pending'},
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      await voidLinkedFinance(txn, 'Uchakataji', uuid, reason);
      await txn.update(
          'gold_inventory',
          {
            'grams_available': 0.0,
            'deleted_at': nowIso(),
            'updated_at': nowIso(),
            'sync_status': 'Pending'
          },
          where: 'processing_uuid = ?',
          whereArgs: [uuid]);

      final others = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM processing_records '
              'WHERE company_id = ? AND batch_id = ? AND voided = 0',
              [cid, bid])) ??
          0;
      final moved = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM batch_movements '
              'WHERE company_id = ? AND batch_id = ?',
              [cid, bid])) ??
          0;

      final batch = await txn.query(
        'ore_batches',
        where: 'company_id = ? AND batch_id = ?',
        whereArgs: [cid, bid],
        limit: 1,
      );
      if (batch.isNotEmpty) {
        await txn.update(
          'ore_batches',
          {
            'weight_kg': dbl(batch.first['weight_kg']) + ore,
            'status': others > 0
                ? 'Inaendelea kuchakatwa'
                : (moved > 0 ? 'Imehamishwa' : 'Imechimbwa'),
            'sync_status': 'Pending',
          },
          where: 'company_id = ? AND batch_id = ?',
          whereArgs: [cid, bid],
        );
      }

      await writeAudit(
        txn,
        entity: 'processing',
        entityUuid: uuid,
        action: 'Imefutwa',
        detail: 'Batch $bid. Sababu: $reason',
        company: cid,
      );
    });
  }

  Future<double> goldBalance({bool allMines = false}) async {
    final db = await database;
    return goldBalanceOn(db, allMines);
  }

  /// Utafutaji wa ndani unaoheshimu kampuni/mgodi uliochaguliwa.
  Future<List<Map<String, dynamic>>> searchAllRecords(String query,
      {int offset = 0, int limit = 50}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final db = await database;
    final like = '%$q%';
    final c = AppCtx.company;
    final m = AppCtx.mine;
    final results = <Map<String, dynamic>>[];
    Future<void> add(String sql, List<Object?> args) async {
      results.addAll(await db.rawQuery(sql, args));
    }

    await add('''SELECT 'Uzalishaji' AS module, batch_id AS title,
      shaft_area || ' • ' || recorded_by AS details, shift_date AS record_date
      FROM production_records WHERE company_id = ? AND mine_id = ? AND voided = 0
      AND (batch_id LIKE ? OR shaft_area LIKE ? OR recorded_by LIKE ?)''',
        [c, m, like, like, like]);
    await add('''SELECT 'Batch' AS module, batch_id AS title,
      current_location || ' • ' || status AS details, created_at AS record_date,
      'batch' AS ref_type, uuid AS ref_uuid
      FROM ore_batches WHERE company_id = ? AND mine_id = ? AND status != 'Imefutwa'
      AND (batch_id LIKE ? OR source_location LIKE ? OR current_location LIKE ? OR uuid LIKE ? OR IFNULL(original_batch_id,'') LIKE ?)''',
        [c, m, like, like, like, like, like]);
    await add('''SELECT 'Gold lot' AS module, g.batch_id AS title,
      CAST(g.grams_available AS TEXT) || ' g zimebaki • lot ' || substr(g.uuid,1,8) AS details, g.created_at AS record_date,
      'batch' AS ref_type, b.uuid AS ref_uuid
      FROM gold_inventory g JOIN ore_batches b ON b.company_id = g.company_id AND b.batch_id = g.batch_id
      WHERE g.company_id = ? AND g.mine_id = ? AND (g.batch_id LIKE ? OR g.uuid LIKE ?)''',
        [c, m, like, like]);
    await add('''SELECT 'Deni' AS module, party AS title,
      direction || ' • ' || CAST(amount AS TEXT) AS details, IFNULL(due_date, created_at) AS record_date
      FROM debts WHERE company_id = ? AND mine_id = ? AND voided = 0
      AND (party LIKE ? OR description LIKE ?)''', [c, m, like, like]);
    await add('''SELECT 'Uhamisho wa Batch' AS module, bm.batch_id AS title,
      bm.from_location || ' → ' || bm.to_location || ' • ' || bm.moved_by AS details, bm.movement_date AS record_date
      FROM batch_movements bm JOIN ore_batches b
        ON b.company_id = bm.company_id
        AND b.batch_id = bm.batch_id
      WHERE bm.company_id = ? AND b.mine_id = ?
      AND (bm.batch_id LIKE ? OR bm.child_batch_id LIKE ? OR bm.from_location LIKE ? OR bm.to_location LIKE ? OR bm.moved_by LIKE ?)''',
        [c, m, like, like, like, like, like]);
    await add('''SELECT 'Usindikaji' AS module, batch_id AS title,
      processed_by || ' • ' || CAST(gold_recovered_g AS TEXT) || ' g' AS details, processing_date AS record_date
      FROM processing_records WHERE company_id = ? AND mine_id = ? AND voided = 0
      AND (batch_id LIKE ? OR processed_by LIKE ? OR notes LIKE ?)''',
        [c, m, like, like, like]);
    await add('''SELECT 'Mfanyakazi' AS module, full_name AS title,
      role || ' • ' || IFNULL(phone,'') AS details, created_at AS record_date
      FROM workers WHERE company_id = ? AND mine_id = ? AND active = 1
      AND (full_name LIKE ? OR phone LIKE ? OR role LIKE ?)''',
        [c, m, like, like, like]);
    await add('''SELECT 'Mauzo' AS module, buyer AS title,
      CAST(gold_weight_g AS TEXT) || ' g • ' || IFNULL(reference,'') AS details, sale_date AS record_date,
      'sale' AS ref_type, uuid AS ref_uuid
      FROM sales WHERE company_id = ? AND mine_id = ? AND voided = 0
      AND (buyer LIKE ? OR buyer_license LIKE ? OR reference LIKE ? OR uuid LIKE ? OR sale_date LIKE ?)''',
        [c, m, like, like, like, like, like]);
    await add('''SELECT 'Fedha' AS module, category AS title,
      type || ' • ' || IFNULL(description,'') || ' • ' || CAST(amount AS TEXT) AS details, trans_date AS record_date
      FROM finance_transactions WHERE company_id = ? AND mine_id = ? AND voided = 0
      AND (category LIKE ? OR description LIKE ? OR reference LIKE ? OR trans_date LIKE ?)''',
        [c, m, like, like, like, like]);
    await add('''SELECT 'Stoo' AS module, name AS title,
      category || ' • ' || unit AS details, created_at AS record_date
      FROM inventory_items WHERE company_id = ? AND mine_id = ? AND active = 1
      AND (name LIKE ? OR category LIKE ?)''', [c, m, like, like]);
    results.sort((a, b) =>
        '${b['record_date'] ?? ''}'.compareTo('${a['record_date'] ?? ''}'));
    return results.skip(offset).take(limit).toList();
  }

  // -------------------------------------------------------------------------
  // Muhtasari wa Dashboard
  // -------------------------------------------------------------------------
  Future<Map<String, dynamic>> dashboardStats() async {
    final db = await database;
    final c = AppCtx.company;
    final m = AppCtx.mine;
    final today = todayStr();
    final monthStart = '${today.substring(0, 7)}-01';

    final prod = await db.rawQuery(
      'SELECT IFNULL(SUM(weight_kg),0) AS w FROM production_records '
      'WHERE company_id = ? AND mine_id = ? AND voided = 0 AND shift_date = ?',
      [c, m, today],
    );
    final stock = await db.rawQuery(
      'SELECT IFNULL(SUM(weight_kg),0) AS w, COUNT(*) AS n FROM ore_batches '
      "WHERE company_id = ? AND mine_id = ? AND weight_kg > 0 AND status != 'Imefutwa'",
      [c, m],
    );
    final fin = await db.rawQuery(
      'SELECT type, IFNULL(SUM(amount),0) AS t FROM finance_transactions '
      'WHERE company_id = ? AND mine_id = ? AND voided = 0 AND trans_date >= ? '
      'GROUP BY type',
      [c, m, monthStart],
    );

    double income = 0;
    double expense = 0;
    for (final r in fin) {
      if (r['type'] == 'Mapato') income = dbl(r['t']);
      if (r['type'] == 'Matumizi') expense = dbl(r['t']);
    }

    final low = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM ('
      'SELECT i.uuid, i.min_level, '
      "IFNULL(SUM(CASE WHEN m.move_type = 'Ingia' THEN m.quantity "
      "WHEN m.move_type = 'Toka' THEN -m.quantity ELSE 0 END), 0) AS stock "
      'FROM inventory_items i LEFT JOIN inventory_movements m '
      'ON m.item_uuid = i.uuid AND m.voided = 0 '
      'WHERE i.company_id = ? AND i.mine_id = ? AND i.active = 1 '
      'GROUP BY i.uuid) WHERE min_level > 0 AND stock <= min_level',
      [c, m],
    );

    var pending = 0;
    for (final t in kSyncTables) {
      pending += Sqflite.firstIntValue(await db.rawQuery(
              "SELECT COUNT(*) FROM $t WHERE sync_status = 'Pending'")) ??
          0;
    }

    return {
      'today_kg': dbl(prod.first['w']),
      'stock_kg': dbl(stock.first['w']),
      'stock_batches': intv(stock.first['n']),
      'gold_balance_g': await goldBalanceOn(db, false),
      'income': income,
      'expense': expense,
      'low_stock': intv(low.first['n']),
      'pending': pending,
    };
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
