import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:madini_tracker/app_context.dart';
import 'package:madini_tracker/database_helper.dart';
import 'package:madini_tracker/db_modules.dart';
import 'package:madini_tracker/db_v8.dart';
import 'package:madini_tracker/l10n.dart';
import 'package:madini_tracker/lock_page.dart';
import 'package:madini_tracker/local_auth.dart';
import 'package:madini_tracker/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

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
    tmp = await Directory.systemTemp.createTemp('madini_v10');
    await databaseFactory.setDatabasesPath(tmp.path);
    await db.addCompany(name: 'Kampuni A', mineName: 'Mgodi 1');
    AppCtx.company = 'Kampuni A';
    AppCtx.mine = 'Mgodi 1';
    AppCtx.user = 'amina';
    AppCtx.requireWitness = false;
    AppCtx.userUuid = '';
    AppCtx.role = 'company_owner';
    AppCtx.expenseApproval = false;
    AppCtx.localAuthActive = false;
    AppCtx.deviceId = await db.getDeviceId();
    L10n.lang = 'sw';
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('PBKDF2-HMAC-SHA256 inalingana na vector za RFC 7914/6070', () {
    expect(hex(pbkdf2('password'.codeUnits, 'salt'.codeUnits, 1)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
    expect(hex(pbkdf2('password'.codeUnits, 'salt'.codeUnits, 2)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
  });

  test(
      'PIN za akaunti zinatumia metadata, chumvi mpya, na kuboresha hash ya zamani baada ya uthibitisho',
      () async {
    await LocalAuth.createUser(
        username: 'amina',
        fullName: 'Amina',
        role: 'company_owner',
        pin: '1234');
    final d = await db.database;
    final original = (await d.query('local_users')).single;
    expect(original['pin_algorithm'], LocalAuth.pinAlgorithm);
    expect(original['pin_iterations'], LocalAuth.targetIterations);
    expect((original['pin_salt'] as String).length, 32);

    final legacySalt = original['pin_salt'] as String;
    await d.update(
      'local_users',
      {
        'pin_hash': hashPinPbkdf2('1234', legacySalt, 10000),
        'pin_iterations': 10000,
      },
      where: 'uuid = ?',
      whereArgs: [original['uuid']],
    );

    await LocalAuth.verifyUser('amina', '1234');
    final upgraded = (await d.query('local_users')).single;
    expect(upgraded['pin_algorithm'], LocalAuth.pinAlgorithm);
    expect(upgraded['pin_iterations'], LocalAuth.targetIterations);
    expect(upgraded['pin_salt'], isNot(legacySalt));
    expect(upgraded['pin_hash'], isNot(original['pin_hash']));
  });

  test('PIN ya zamani ya kufunga app huboreshwa baada ya PIN sahihi pekee',
      () async {
    const salt = 'legacy-timestamp-salt';
    AppCtx.userUuid = 'actor-uuid';
    await db.setSetting('pin_salt', salt);
    await db.setSetting('pin_hash', hashPin('4321', salt));

    expect(await verifyPin('0000'), isFalse);
    expect(await db.getSetting('pin_algorithm'), isNull);
    expect(await verifyPin('4321'), isTrue);
    expect(await db.getSetting('pin_algorithm'), LocalAuth.pinAlgorithm);
    expect(
      await db.getSetting('pin_iterations'),
      LocalAuth.targetIterations.toString(),
    );
    expect(await verifyPin('4321'), isTrue);
    final audit = (await (await db.database).query(
      'audit_log',
      where: "entity = 'app_lock_pin'",
      orderBy: 'id DESC',
      limit: 1,
    ))
        .single;
    expect(audit['company_id'], 'Kampuni A');
    expect(audit['mine_id'], 'Mgodi 1');
    expect(audit['actor_uuid'], 'actor-uuid');
    expect(audit['user_name'], 'amina');
    expect(audit['created_at'], isNotNull);
  });

  test('metadata ya PIN isiyokamilika haifungui app bila uthibitisho',
      () async {
    await db.setSetting('pin_salt', 'orphaned-salt');
    await AppCtx.load();
    expect(AppCtx.hasPin, isTrue);
    expect(await verifyPin('1234'), isFalse);
  });

  test(
      'watumiaji wa kifaa: wa kwanza ni Mmiliki, PIN mbaya inafunga akaunti, majukumu yanazuia kuandika',
      () async {
    await LocalAuth.createUser(
        username: 'Boss', fullName: 'Bosi Mkuu', role: 'auditor', pin: '1234');
    final users = await LocalAuth.listUsers();
    expect(users.single['role'],
        'company_owner'); // jukumu lililoombwa halizingatiwi kwa wa kwanza
    await AppCtx.load();
    expect(AppCtx.localAuthActive, isTrue);

    await LocalAuth.login('boss', '1234');
    expect(AppCtx.role, 'company_owner');
    await LocalAuth.createUser(
        username: 'mkaguzi',
        fullName: 'Mkaguzi Juma',
        role: 'auditor',
        pin: '4321');
    final d = await db.database;
    final storedUsers =
        await d.query('local_users', columns: ['uuid', 'pin_salt']);
    expect(storedUsers.map((u) => u['pin_salt']).toSet(), hasLength(2));
    final reviewer =
        storedUsers.firstWhere((u) => u['uuid'] != users.single['uuid']);
    final oldSalt = reviewer['pin_salt'];
    await LocalAuth.resetPin(reviewer['uuid'] as String, '8765');
    final reset = (await d.query('local_users',
            where: 'uuid = ?', whereArgs: [reviewer['uuid']]))
        .single;
    expect(reset['pin_salt'], isNot(oldSalt));
    expect(reset['pin_iterations'], LocalAuth.targetIterations);
    await LocalAuth.verifyUser('mkaguzi', '8765');

    // Majaribio 5 mabaya yanafunga akaunti; baada ya hapo hata PIN sahihi inakataliwa kwa muda.
    for (var i = 0; i < 5; i++) {
      await expectLater(
          LocalAuth.verifyUser('mkaguzi', '0000'), throwsA(isA<Object>()));
    }
    await expectLater(
        LocalAuth.verifyUser('mkaguzi', '4321'), throwsA(isA<Object>()));
  });

  test('mkaguzi/read_only hawezi kuandika uzalishaji', () async {
    AppCtx.localAuthActive = true;
    AppCtx.role = 'auditor';
    await expectLater(
        db.recordProduction(
            shaft: 'S1',
            batchId: 'B-1',
            shiftDate: '2026-01-01',
            shiftType: 'Mchana',
            bags: 1,
            weightKg: 10),
        throwsA(isA<Object>()));
  });

  test('shahidi aliyethibitishwa anahifadhiwa na UUID yake', () async {
    await db.recordProduction(
        shaft: 'S1',
        batchId: 'B-2',
        shiftDate: '2026-01-01',
        shiftType: 'Mchana',
        bags: 1,
        weightKg: 10,
        witness: 'Neema',
        witnessUserUuid: 'user-uuid-1');
    final d = await db.database;
    final r = (await d.query('production_records')).single;
    expect(r['witness_user_uuid'], 'user-uuid-1');
    expect(r['witness_verified'], 1);
  });

  test(
      'approval ya matumizi: kusubiri, kuidhinisha, kukataa (void) bila kufuta historia',
      () async {
    AppCtx.expenseApproval = true;
    AppCtx.localAuthActive = true;
    AppCtx.role = 'storekeeper';
    await db.addTransaction(
        type: 'Matumizi',
        category: 'Mafuta',
        amount: 5000,
        date: '2026-01-02',
        method: 'Pesa taslimu');
    final d = await db.database;
    var t = (await d.query('finance_transactions')).single;
    expect(t['approval_status'], 'Inasubiri');
    await expectLater(db.approveTransaction(t['uuid'] as String),
        throwsA(isA<Object>())); // storekeeper hana mamlaka

    AppCtx.role = 'accountant';
    await db.approveTransaction(t['uuid'] as String);
    t = (await d.query('finance_transactions')).single;
    expect(t['approval_status'], 'Imeidhinishwa');

    AppCtx.role = 'storekeeper';
    await db.addTransaction(
        type: 'Matumizi',
        category: 'Chakula',
        amount: 1000,
        date: '2026-01-02',
        method: 'Pesa taslimu');
    AppCtx.role = 'accountant';
    final pending = (await d.query('finance_transactions',
            where: "approval_status = 'Inasubiri'"))
        .single;
    await db.rejectTransaction(pending['uuid'] as String, 'si ya kazi');
    final rejected = (await d.query('finance_transactions',
            where: 'uuid = ?', whereArgs: [pending['uuid']]))
        .single;
    expect(rejected['approval_status'], 'Imekataliwa');
    expect(rejected['voided'], 1);
  });

  test('gharama ya Batch inaonekana kwenye batchCostReport', () async {
    await db.recordProduction(
        shaft: 'S1',
        batchId: 'B-3',
        shiftDate: '2026-01-01',
        shiftType: 'Mchana',
        bags: 1,
        weightKg: 10);
    final b = (await db.expenseBatchOptions()).single;
    await db.addTransaction(
        type: 'Matumizi',
        category: 'Mafuta',
        amount: 7000,
        date: '2026-01-02',
        method: 'Pesa taslimu',
        batchUuid: b['uuid'] as String);
    final r = await db.batchCostReport();
    expect(r.single['total_cost'], 7000.0);
  });

  test('traceability: Batch hadi mauzo na chanzo cha dhahabu iliyouzwa',
      () async {
    await db.recordProduction(
        shaft: 'S1',
        batchId: 'B-4',
        shiftDate: '2026-01-01',
        shiftType: 'Mchana',
        bags: 1,
        weightKg: 100);
    await db.processBatch(
        batchId: 'B-4',
        oreProcessedKg: 10,
        goldRecoveredG: 20,
        tailingsKg: 9.9,
        processingCost: 0,
        processingDate: '2026-01-02');
    await db.recordSale(
        saleDate: '2026-01-03',
        buyer: 'X',
        weightG: 12,
        purityPct: 90,
        pricePerG: 1000,
        method: 'Pesa taslimu');
    final b = (await db.expenseBatchOptions()).single;
    final trace = await db.batchTrace(b['uuid'] as String);
    expect(trace['production']!.length, 1);
    expect(trace['processing']!.length, 1);
    expect(trace['lots']!.length, 1);
    expect(trace['sales']!.single['grams'], 12.0);
    final sale = (await db.getSales()).first;
    final src = await db.saleSources(sale['uuid'] as String);
    expect(src.single['batch_id'], 'B-4');
  });

  test('madeni yaliyofika due date yanaonekana kwenye debtsDue', () async {
    final d = await db.database;
    await d.insert('debts', {
      ...meta(),
      'company_id': 'Kampuni A',
      'mine_id': 'Mgodi 1',
      'direction': 'Tunadaiwa',
      'party': 'Supplier',
      'amount': 1000.0,
      'due_date': '2000-01-01',
      'voided': 0,
    });
    expect((await db.debtsDue()).single['party'], 'Supplier');
  });

  test('Batch ID inaweza kutumika tena baada ya void kwa mtiririko wa app',
      () async {
    await db.recordProduction(
        shaft: 'S1',
        batchId: 'B-9',
        shiftDate: '2026-01-01',
        shiftType: 'Mchana',
        bags: 1,
        weightKg: 10);
    final p = (await db.getProductionRecords()).first;
    await db.voidProduction(p['uuid'] as String, 'kosa');
    await db.recordProduction(
        shaft: 'S1',
        batchId: 'B-9',
        shiftDate: '2026-01-02',
        shiftType: 'Mchana',
        bags: 2,
        weightKg: 20);
    final d = await db.database;
    expect(
        (await d.query('production_records',
                where: 'original_batch_id = ?', whereArgs: ['B-9']))
            .length,
        1);
    expect(
        (await d.query('production_records', where: "batch_id = 'B-9'")).length,
        1);
  });

  test('tr(): Kiswahili ni chaguo-msingi, Kiingereza kinatafsiri', () {
    expect(tr('Mauzo'), 'Mauzo');
    L10n.lang = 'en';
    expect(tr('Mauzo'), 'Sales');
    expect(tr('neno-lisilo-na-tafsiri'), 'neno-lisilo-na-tafsiri');
  });

  group('pull sync', () {
    setUp(() async {
      await db.setSetting('sync_url', 'https://example.test');
      SyncService.tokenProvider = () async => 'a.b.c';
    });

    Map<String, dynamic> workerRecord(String uuid,
            {int version = 3,
            String device = 'kifaa-kingine',
            String name = 'Neema'}) =>
        {
          'cursor': 1,
          'entity': 'workers',
          'record_uuid': uuid,
          'version': version,
          'device_id': device,
          'data': {
            'id': 999,
            'uuid': uuid,
            'company_id': 'Kampuni A',
            'mine_id': 'Mgodi 1',
            'full_name': name,
            'role': 'Opereta',
            'pay_type': 'Mwezi',
            'created_at': '2026-01-01T00:00:00',
            'version': version,
            'active': 1,
          },
        };

    http.Client server(List<Map<String, dynamic>> records) =>
        MockClient((req) async {
          expect(req.url.path, '/v1/sync/pull');
          return http.Response(
              jsonEncode(
                  {'records': records, 'next_cursor': 7, 'has_more': false}),
              200);
        });

    test(
        'rekodi kutoka kifaa kingine inawekwa, kama Synced, bila event ya outbox',
        () async {
      final s =
          await SyncService.pullNow(client: server([workerRecord('w-pull-1')]));
      expect(s.applied, 1);
      final d = await db.database;
      final w =
          (await d.query('workers', where: 'uuid = ?', whereArgs: ['w-pull-1']))
              .single;
      expect(w['sync_status'], 'Synced');
      expect(w['version'], 3);
      expect(
          (await d.query('sync_outbox',
                  where: 'record_uuid = ?', whereArgs: ['w-pull-1']))
              .length,
          0);
      expect(
          (await d.query('sync_state', where: "key LIKE 'pull_cursor_%'"))
              .single['value'],
          '7');
    });

    test(
        'rekodi ya kifaa hiki chenyewe inaruka; na mabadiliko ya ndani yasiyotumwa hayafutwi',
        () async {
      final own = await SyncService.pullNow(
          client: server([workerRecord('w-own', device: AppCtx.deviceId)]));
      expect(own.applied, 0);

      await SyncService.pullNow(
          client: server([workerRecord('w-pull-2', version: 2)]));
      final d = await db.database;
      await d.update('workers',
          {'full_name': 'Mabadiliko ya ndani', 'sync_status': 'Pending'},
          where: 'uuid = ?', whereArgs: ['w-pull-2']);
      final s = await SyncService.pullNow(
          client:
              server([workerRecord('w-pull-2', version: 9, name: 'Ya seva')]));
      expect(s.applied, 0);
      expect(
          (await d.query('workers', where: 'uuid = ?', whereArgs: ['w-pull-2']))
              .single['full_name'],
          'Mabadiliko ya ndani');
    });

    test(
        'toleo jipya la rekodi Synced linasasishwa bila kuongeza version wala outbox',
        () async {
      await SyncService.pullNow(
          client: server([workerRecord('w-pull-3', version: 2)]));
      final d = await db.database;
      await d.delete('sync_outbox');
      final s = await SyncService.pullNow(
          client: server(
              [workerRecord('w-pull-3', version: 5, name: 'Jina Jipya')]));
      expect(s.applied, 1);
      final w =
          (await d.query('workers', where: 'uuid = ?', whereArgs: ['w-pull-3']))
              .single;
      expect([w['full_name'], w['version']], ['Jina Jipya', 5]);
      expect((await d.query('sync_outbox')).length, 0);
    });
  });
}
