import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDB('madini_local.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE production_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id TEXT NOT NULL,
        mine_id TEXT NOT NULL,
        shaft_area TEXT NOT NULL,
        batch_id TEXT NOT NULL UNIQUE,
        shift_date TEXT NOT NULL,
        shift_type TEXT NOT NULL,
        bags_count INTEGER NOT NULL,
        weight_kg REAL NOT NULL,
        estimated_grade REAL,
        recorded_by TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'Pending',
        created_at TEXT NOT NULL
      )
    ''');
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

  Future<void> close() async {
    final db = _database;

    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
