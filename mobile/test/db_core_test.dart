import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:madini_tracker/app_context.dart';
import 'package:madini_tracker/database_helper.dart';
import 'package:madini_tracker/db_modules.dart';
import 'package:madini_tracker/db_reports.dart';
import 'package:madini_tracker/db_v8.dart';
import 'package:madini_tracker/migration_v11_sql.dart';
import 'package:madini_tracker/sync_service.dart';
import 'package:madini_tracker/utils.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.testFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.close();
    tmp = await Directory.systemTemp.createTemp('madini_test');
    await databaseFactory.setDatabasesPath(tmp.path);
    await db.addCompany(name: 'Kampuni A', mineName: 'Mgodi 1');
    AppCtx.company = 'Kampuni A';
    AppCtx.mine = 'Mgodi 1';
    AppCtx.user = 'amina';
    AppCtx.requireWitness = false;
    AppCtx.deviceId = await db.getDeviceId();
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<void> prod(String id, {double kg = 100}) => db.recordProduction(
      shaft: 'S1',
      batchId: id,
      shiftDate: '2026-01-10',
      shiftType: 'Mchana',
      bags: 5,
      weightKg: kg);

  test('foreign keys zimewashwa na schema ni v11', () async {
    final d = await db.database;
    expect(await d.getVersion(), 11);
    final r = await db.integrityReport();
    expect(r['foreign_keys_on'], 1);
    expect(r['foreign_key_violations'], 0);
  });

  test('upgrade huhifadhi nakala ya database kabla ya migration', () async {
    final d = await db.database;
    for (final statement in kV11Statements.reversed) {
      final column =
          RegExp(r'ADD COLUMN (\w+)').firstMatch(statement)!.group(1)!;
      await d.execute('ALTER TABLE safety_incidents DROP COLUMN $column');
    }
    await d.setVersion(10);
    await db.close();

    final upgraded = await db.database;
    expect(await upgraded.getVersion(), 11);
    final backup = File('${tmp.path}/madini_local.db.pre-v11.bak');
    expect(await backup.exists(), isTrue);
    final probe = await openReadOnlyDatabase(backup.path);
    try {
      expect(await probe.getVersion(), 10);
      expect(await probe.query('companies'), isNotEmpty);
    } finally {
      await probe.close();
    }
  });

  test('Batch ID mpya hutofautisha vifaa kwa utambulisho thabiti', () async {
    final firstDeviceId = await db.getDeviceId();
    final firstId = await db.nextBatchId();
    final tag = firstDeviceId.replaceAll('-', '').substring(20).toUpperCase();
    expect(firstId, matches(RegExp(r'^B\d{6}-[0-9A-F]{12}-\d{4}$')));
    expect(firstId, contains(tag));
    await prod(firstId);

    const secondDeviceId = '12345678-1234-4234-8234-123456789abc';
    final d = await db.database;
    await d.update(
      'app_metadata',
      {'value': secondDeviceId},
      where: 'key = ?',
      whereArgs: ['device_id'],
    );
    AppCtx.deviceId = secondDeviceId;
    final secondId = await db.nextBatchId();
    expect(secondId, isNot(firstId));
    expect(secondId, contains('123456789ABC'));
    await prod(secondId);

    final records = await d.query(
      'production_records',
      where: 'batch_id IN (?, ?)',
      whereArgs: [firstId, secondId],
    );
    expect(records.map((row) => row['uuid']).toSet(), hasLength(2));
    expect(records.map((row) => row['device_id']).toSet(),
        {firstDeviceId, secondDeviceId});
  });

  test('Batch iliyogawanywa hupata ID ya mtoto yenye tag ya kifaa', () async {
    await prod('B-SPLIT', kg: 100);
    final deviceId = await db.getDeviceId();
    final tag = deviceId.replaceAll('-', '').substring(20).toUpperCase();
    final childId = await db.moveBatch(
      batchId: 'B-SPLIT',
      toLocation: 'Stoo',
      weightKg: 35,
    );
    expect(childId, 'B-SPLIT-S$tag-1');
    expect((await db.getBatch('B-SPLIT'))!['weight_kg'], 65.0);
    expect((await db.getBatch(childId))!['weight_kg'], 35.0);
  });

  test(
      'restore huweka data ya v9, huhifadhi PIN za sasa na inaondoa outbox ya zamani',
      () async {
    await prod('B-BACKUP');
    await db.setSetting('pin_hash', 'credential-remains-local');
    final decoded = jsonDecode(await db.exportBackupJson()) as Map;
    decoded['db_version'] = 9;
    final backupTables = decoded['tables'] as Map;
    expect(
      (backupTables['app_settings'] as List)
          .every((row) => !(row['setting_key'] as String).startsWith('pin_')),
      isTrue,
    );

    await prod('B-AFTER-BACKUP');
    expect((await db.getProductionRecords()).length, 2);
    await db.restoreBackupJson(jsonEncode(decoded));

    final restored = await db.getProductionRecords();
    expect(restored.map((row) => row['batch_id']), ['B-BACKUP']);
    expect(await db.getSetting('pin_hash'), 'credential-remains-local');
    final audit = await db.getAuditLog();
    expect(audit.first['action'], 'Backup imerejeshwa');
  });

  test(
      'restore yenye row isiyokubalika hurudisha transaction bila kupoteza data',
      () async {
    await prod('B-PRESERVE');
    final decoded = jsonDecode(await db.exportBackupJson()) as Map;
    ((decoded['tables'] as Map)['production_records'] as List).add({});
    await prod('B-ALSO-PRESERVE');

    await expectLater(
      db.restoreBackupJson(jsonEncode(decoded)),
      throwsA(isA<Object>()),
    );
    final rows = await db.getProductionRecords();
    expect(rows.map((row) => row['batch_id']).toSet(),
        {'B-PRESERVE', 'B-ALSO-PRESERVE'});
  });

  test(
      'Batch ID duplicate inakataliwa, na inaweza kutumika tena baada ya void bila kupoteza historia',
      () async {
    await prod('B-01');
    expect(() => prod('B-01'), throwsA(isA<Object>()));
    final first = (await db.getProductionRecords()).first;
    await db.voidProduction(first['uuid'] as String, 'kosa');
    await prod('B-01', kg: 50);
    final d = await db.database;
    final old = await d.query('production_records',
        where: 'uuid = ?', whereArgs: [first['uuid']]);
    expect(old.single['original_batch_id'], 'B-01');
    expect(old.single['voided'], 1);
    expect(
        (await d.query('production_records', where: "batch_id = 'B-01'"))
            .length,
        1);
  });

  test('Batch ID iliyopo kwenye uzalishaji pekee haikubaliki tena', () async {
    await prod('B-ORPHAN');
    final d = await db.database;
    await d.delete(
      'ore_batches',
      where: 'company_id = ? AND batch_id = ?',
      whereArgs: [AppCtx.company, 'B-ORPHAN'],
    );

    await expectLater(prod('B-ORPHAN'), throwsA(isA<AppError>()));
    expect(
      await d.query(
        'production_records',
        where: 'company_id = ? AND batch_id = ?',
        whereArgs: [AppCtx.company, 'B-ORPHAN'],
      ),
      hasLength(1),
    );
  });

  test(
      'merge huunganisha uzito ndani ya transaction na huacha traceability ya vyanzo',
      () async {
    await prod('B-M1', kg: 40);
    await prod('B-M2', kg: 60);
    final mergedId = await db.mergeBatches(
      batchIds: const ['B-M1', 'B-M2'],
      targetLocation: 'Crusher',
      notes: 'Mchanganyiko wa jaribio',
    );
    final deviceTag = (await db.getDeviceId())
        .replaceAll('-', '')
        .substring(20)
        .toUpperCase();
    expect(mergedId, startsWith('M-$deviceTag-'));
    final d = await db.database;
    final sources = await d.query(
      'ore_batches',
      where: "batch_id IN ('B-M1','B-M2')",
      orderBy: 'batch_id',
    );
    expect(sources.map((b) => b['weight_kg']), [0.0, 0.0]);
    expect(sources.map((b) => b['status']), ['Imeunganishwa', 'Imeunganishwa']);

    final target = (await d.query(
      'ore_batches',
      where: 'batch_id = ?',
      whereArgs: [mergedId],
    ))
        .single;
    expect(target['weight_kg'], 100.0);
    expect(target['initial_weight_kg'], 100.0);
    final links = await d.query(
      'batch_movements',
      where: 'child_batch_id = ?',
      whereArgs: [mergedId],
    );
    expect(links.length, 2);

    final report = await db.massBalanceReport(allMines: true);
    expect(
      report.every((row) => ((row['variance_kg'] as num).abs() < 0.000001)),
      isTrue,
    );
    final trace = await db.batchTrace(target['uuid'] as String);
    expect(trace['merged_sources']!.map((b) => b['batch_id']).toSet(),
        {'B-M1', 'B-M2'});
    final audit = (await d.query(
      'audit_log',
      where: "entity = 'batch_merge'",
    ))
        .single;
    expect(audit['entity_uuid'], target['uuid']);
    expect(audit['mine_id'], 'Mgodi 1');
    expect(audit['detail'], contains('B-M1'));
    expect(audit['detail'], contains('B-M2'));
  });

  test(
      'merge ikishindwa katikati hurudisha uzito, Batch na outbox hali ya awali',
      () async {
    await prod('B-R1', kg: 40);
    await prod('B-R2', kg: 60);
    final d = await db.database;
    await d.execute("""
      CREATE TRIGGER reject_merge_movement BEFORE INSERT ON batch_movements
      WHEN NEW.notes LIKE 'Imeunganishwa kuwa Batch %'
      BEGIN SELECT RAISE(ABORT, 'merge movement rejected'); END
    """);
    final outboxBefore = (await d.query('sync_outbox')).length;

    await expectLater(
      db.mergeBatches(
        batchIds: const ['B-R1', 'B-R2'],
        targetLocation: 'Crusher',
      ),
      throwsA(isA<Object>()),
    );
    expect((await db.getBatch('B-R1'))!['weight_kg'], 40.0);
    expect((await db.getBatch('B-R2'))!['weight_kg'], 60.0);
    expect((await d.query('ore_batches')).length, 2);
    expect((await d.query('sync_outbox')).length, outboxBefore);
    expect(
        await d.query('audit_log', where: "entity = 'batch_merge'"), isEmpty);
  });

  test(
      'outbox: rekodi ya biashara inatengeneza event ndani ya transaction moja',
      () async {
    await prod('B-02');
    final d = await db.database;
    final ev = await d.query('sync_outbox',
        where: "entity = 'production_records' AND sync_status = 'pending'");
    expect(ev.length, 1);
  });

  test('rollback ya transaction haiachi event ya outbox', () async {
    final d = await db.database;
    final before = (await d.query('sync_outbox')).length;
    try {
      await d.transaction((txn) async {
        await txn.insert('workers', {
          ...meta(),
          'company_id': 'Kampuni A',
          'mine_id': 'Mgodi 1',
          'full_name': 'X',
          'role': 'Y',
          'pay_type': 'Siku',
        });
        throw Exception('kosa');
      });
    } catch (_) {}
    expect((await d.query('sync_outbox')).length, before);
  });

  test('FIFO: mauzo yanatumia lot ya zamani kwanza; void inarudisha gramu',
      () async {
    await prod('B-03');
    await db.processBatch(
        batchId: 'B-03',
        oreProcessedKg: 10,
        goldRecoveredG: 20,
        tailingsKg: 9.9,
        processingCost: 0,
        processingDate: '2026-01-11');
    await prod('B-04');
    await db.processBatch(
        batchId: 'B-04',
        oreProcessedKg: 10,
        goldRecoveredG: 20,
        tailingsKg: 9.9,
        processingCost: 0,
        processingDate: '2026-01-12');
    await db.recordSale(
        saleDate: '2026-01-13',
        buyer: 'X',
        weightG: 30,
        purityPct: 90,
        pricePerG: 1000,
        method: 'Pesa taslimu');
    final d = await db.database;
    var lots = await d.query('gold_inventory', orderBy: 'created_at ASC');
    expect(lots[0]['grams_available'], 0.0);
    expect(lots[1]['grams_available'], 10.0);
    final sale = (await db.getSales()).first;
    await db.voidSale(sale['uuid'] as String, 'test');
    lots = await d.query('gold_inventory', orderBy: 'created_at ASC');
    expect(lots[0]['grams_available'], 20.0);
    expect(lots[1]['grams_available'], 20.0);
  });

  test('mauzo yanayozidi dhahabu iliyopo yanakataliwa', () async {
    await prod('B-05');
    await db.processBatch(
        batchId: 'B-05',
        oreProcessedKg: 10,
        goldRecoveredG: 5,
        tailingsKg: 9.9,
        processingCost: 0,
        processingDate: '2026-01-11');
    expect(
        () => db.recordSale(
            saleDate: '2026-01-13',
            buyer: 'X',
            weightG: 6,
            purityPct: 90,
            pricePerG: 1000,
            method: 'Pesa taslimu'),
        throwsA(isA<Object>()));
  });

  test(
      'tax_rates: kiwango draft hakitumiki, verified kinatumika kwa tarehe sahihi',
      () async {
    await db.addTaxRate(
        type: 'Mrabaha',
        percent: 1.5,
        effectiveFrom: '2026-01-01',
        sourceReference: 'REF-TEST');
    expect(await db.effectiveRatePercent('Kampuni A', 'Mrabaha', '2026-02-01'),
        isNull);
    final u = (await db.getTaxRates()).single['uuid'] as String;
    await db.verifyTaxRate(u);
    expect(await db.effectiveRatePercent('Kampuni A', 'Mrabaha', '2026-02-01'),
        1.5);
    expect(await db.effectiveRatePercent('Kampuni A', 'Mrabaha', '2025-12-31'),
        isNull);
  });

  test('backoff ya sync ni exponential na ina kikomo', () {
    expect(SyncService.backoffSeconds(0), 30);
    expect(SyncService.backoffSeconds(1), 60);
    expect(SyncService.backoffSeconds(30), 6 * 3600);
  });

  group('sync', () {
    setUp(() async {
      await db.saveUrlForTest();
      SyncService.tokenProvider = () async => 'tok';
    });

    test(
        'seva ikijibu applied -> rekodi inakuwa Synced; ikikatika mtandao -> inabaki Pending',
        () async {
      await prod('B-06');
      final failing =
          MockClient((_) async => throw const SocketException('offline'));
      var s = await SyncService.syncNow(client: failing);
      expect(s.failed, greaterThan(0));
      final d = await db.database;
      expect((await d.query('production_records')).single['sync_status'],
          'Pending');

      await d.update(
          'sync_outbox', {'sync_status': 'pending', 'next_retry_at': null});
      final ok = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final results = [
          for (final e in body['events'] as List)
            {'idempotency_key': e['idempotency_key'], 'status': 'applied'}
        ];
        return http.Response(jsonEncode({'results': results}), 200);
      });
      s = await SyncService.syncNow(client: ok);
      expect(s.applied, greaterThan(0));
      expect((await d.query('production_records')).single['sync_status'],
          'Synced');
    });

    test('event bila ack haihesabiwi kuwa imefanikiwa', () async {
      await prod('B-07');
      final empty = MockClient(
          (_) async => http.Response(jsonEncode({'results': []}), 200));
      final s = await SyncService.syncNow(client: empty);
      expect(s.applied, 0);
      final d = await db.database;
      expect((await d.query('production_records')).single['sync_status'],
          'Pending');
    });
  });
}

extension on DatabaseHelper {
  Future<void> saveUrlForTest() =>
      setSetting('sync_url', 'https://example.test');
}
