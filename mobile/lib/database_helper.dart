import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'madini_local.db');

    return openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await _createProductionTable(db);
    await _createBatchTables(db);
    await _createProcessingTable(db);
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
      await db.transaction((txn) async {
        await txn.execute('''
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

        await txn.execute('''
          INSERT INTO production_records_new
          SELECT * FROM production_records
        ''');

        await txn.execute('DROP TABLE production_records');

        await txn.execute('''
          ALTER TABLE production_records_new
          RENAME TO production_records
        ''');

        await txn.execute('''
          CREATE INDEX idx_production_sync
          ON production_records(sync_status)
        ''');

        await txn.execute('''
          CREATE INDEX idx_production_mine
          ON production_records(company_id, mine_id)
        ''');
      });
    }

    if (oldVersion < 3) {
      await _createBatchTables(db);
    }

    if (oldVersion < 4) {
      await _createProcessingTable(db);
    }
  }

  Future<int> insertProductionRecord(
    Map<String, dynamic> row,
  ) async {
    final db = await database;
    return db.insert(
      'production_records',
      row,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedRecords() async {
    final db = await database;
    return db.query(
      'production_records',
      where: 'sync_status = ?',
      whereArgs: ['Pending'],
      orderBy: 'id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllRecords() async {
    final db = await database;
    return db.query(
      'production_records',
      orderBy: 'id DESC',
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

  Future<int> insertBatch(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert(
      'ore_batches',
      row,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<Map<String, dynamic>>> getAllBatches({
    required String companyId,
  }) async {
    final db = await database;
    return db.query(
      'ore_batches',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'id DESC',
    );
  }

  Future<Map<String, dynamic>?> getBatch({
    required String companyId,
    required String batchId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'ore_batches',
      where: 'company_id = ? AND batch_id = ?',
      whereArgs: [companyId, batchId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  Future<void> moveBatch({
    required String companyId,
    required String batchId,
    required String toLocation,
    required double weightKg,
    required String movedBy,
    String? notes,
  }) async {
    if (weightKg <= 0) {
      throw ArgumentError('Uzito lazima uwe mkubwa kuliko sifuri.');
    }

    final db = await database;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'ore_batches',
        where: 'company_id = ? AND batch_id = ?',
        whereArgs: [companyId, batchId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw Exception('Batch haijapatikana.');
      }

      final batch = rows.first;
      final availableWeight = (batch['weight_kg'] as num).toDouble();

      if (weightKg > availableWeight) {
        throw Exception('Uzito wa uhamisho unazidi uzito uliopo.');
      }

      if ((weightKg - availableWeight).abs() > 0.000001) {
        throw Exception(
          'Kwa sasa hamisha Batch nzima. '
          'Kugawa Batch katika mizigo midogo kutaongezwa hatua inayofuata.',
        );
      }

      final fromLocation = batch['current_location'] as String;

      await txn.insert('batch_movements', {
        'company_id': companyId,
        'batch_id': batchId,
        'from_location': fromLocation,
        'to_location': toLocation,
        'weight_kg': weightKg,
        'movement_date': DateTime.now().toIso8601String(),
        'moved_by': movedBy,
        'notes': notes,
      });

      await txn.update(
        'ore_batches',
        {
          'current_location': toLocation,
          'weight_kg': availableWeight - weightKg,
          'sync_status': 'Pending',
        },
        where: 'company_id = ? AND batch_id = ?',
        whereArgs: [companyId, batchId],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getBatchHistory({
    required String companyId,
    required String batchId,
  }) async {
    final db = await database;
    return db.query(
      'batch_movements',
      where: 'company_id = ? AND batch_id = ?',
      whereArgs: [companyId, batchId],
      orderBy: 'id DESC',
    );
  }

  Future<int> processBatch({
    required String companyId,
    required String batchId,
    required double oreProcessedKg,
    required double goldRecoveredG,
    required double tailingsKg,
    required double processingCost,
    required String processingDate,
    required String processedBy,
  }) async {
    if (oreProcessedKg <= 0 ||
        goldRecoveredG < 0 ||
        tailingsKg < 0 ||
        processingCost < 0 ||
        processedBy.trim().isEmpty) {
      throw ArgumentError('Taarifa za uchakataji si sahihi.');
    }

    final db = await database;

    return db.transaction((txn) async {
      final batches = await txn.query(
        'ore_batches',
        where: 'company_id = ? AND batch_id = ?',
        whereArgs: [companyId, batchId],
        limit: 1,
      );

      if (batches.isEmpty) {
        throw StateError('Batch haijapatikana.');
      }

      final batch = batches.first;
      final remainingWeight = (batch['weight_kg'] as num).toDouble();

      if (oreProcessedKg > remainingWeight) {
        throw StateError('Kiasi cha ore kinazidi uzito uliobaki kwenye Batch.');
      }

      final remaining = remainingWeight - oreProcessedKg;
      final mineId = batch['mine_id'] as String;

      final recordId = await txn.insert('processing_records', {
        'company_id': companyId,
        'mine_id': mineId,
        'batch_id': batchId,
        'ore_processed_kg': oreProcessedKg,
        'gold_recovered_g': goldRecoveredG,
        'tailings_kg': tailingsKg,
        'processing_cost': processingCost,
        'processing_date': processingDate,
        'processed_by': processedBy.trim(),
        'sync_status': 'Pending',
      });

      await txn.update(
        'ore_batches',
        {
          'weight_kg': remaining < 0.000001 ? 0.0 : remaining,
          'status':
              remaining < 0.000001 ? 'Imechakatwa' : 'Inaendelea kuchakatwa',
          'sync_status': 'Pending',
        },
        where: 'company_id = ? AND batch_id = ?',
        whereArgs: [companyId, batchId],
      );

      return recordId;
    });
  }

  Future<List<Map<String, dynamic>>> getProcessingRecords(
    String companyId, {
    String? batchId,
  }) async {
    final db = await database;

    return db.query(
      'processing_records',
      where: batchId == null
          ? 'company_id = ?'
          : 'company_id = ? AND batch_id = ?',
      whereArgs: batchId == null ? [companyId] : [companyId, batchId],
      orderBy: 'id DESC',
    );
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
