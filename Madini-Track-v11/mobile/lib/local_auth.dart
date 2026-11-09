import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'app_context.dart';
import 'database_helper.dart';
import 'l10n.dart';
import 'utils.dart';

/// Majukumu (roles) ya mfumo; majina ya ndani yanalingana na ya seva (backend/app/core.py).
const Map<String, String> kRoleLabels = {
  'company_owner': 'Mmiliki wa Kampuni',
  'company_admin': 'Msimamizi wa Kampuni',
  'mine_manager': 'Meneja wa Mgodi',
  'production_supervisor': 'Msimamizi wa Uzalishaji',
  'processing_operator': 'Opereta wa Usindikaji',
  'storekeeper': 'Mtunza Stoo',
  'accountant': 'Mhasibu',
  'auditor': 'Mkaguzi',
  'read_only': 'Msomaji Tu',
};

const Set<String> _readOnlyRoles = {'auditor', 'read_only'};
const Set<String> _approverRoles = {
  'company_owner',
  'company_admin',
  'mine_manager',
  'accountant'
};
const Set<String> _adminRoles = {'company_owner', 'company_admin'};
const String _pinHashAlgorithm = 'pbkdf2-hmac-sha256';

String _derivePinHashTask(List<Object?> args) =>
    hashPinPbkdf2(args[0] as String, args[1] as String, args[2] as int);

/// Moduli (kwa title ya ModuleHub) ambazo kila jukumu linaruhusiwa kuziona. null = zote.
const Map<String, Set<String>> _roleModules = {
  'production_supervisor': {
    'Uzalishaji',
    'Ore & Batch Tracking',
    'Usalama Mgodini',
    'Rejista ya Ushahidi',
    'Usawazishaji (Sync)',
  },
  'processing_operator': {
    'Ore & Batch Tracking',
    'Processing & Gold Recovery',
    'Rejista ya Ushahidi',
    'Usawazishaji (Sync)',
  },
  'storekeeper': {'Inventory', 'Rejista ya Ushahidi', 'Usawazishaji (Sync)'},
  'accountant': {
    'Fedha',
    'Mauzo',
    'Wafanyakazi & Payroll',
    'Reports',
    'Viwango vya Kodi na Ada',
    'Rejista ya Ushahidi',
    'Ukaguzi wa Data',
    'Usawazishaji (Sync)',
  },
  'auditor': {'Reports', 'Ukaguzi wa Data', 'Rejista ya Ushahidi'},
  'read_only': {'Reports', 'Ukaguzi wa Data', 'Rejista ya Ushahidi'},
};

bool roleCanOpenModule(String role, String title) {
  final set = _roleModules[role];
  return set == null || set.contains(title) || title == 'Mipangilio';
}

bool roleCanWrite(String role) => !_readOnlyRoles.contains(role);
bool roleCanApprove(String role) => _approverRoles.contains(role);
bool roleIsAdmin(String role) => _adminRoles.contains(role);

/// PBKDF2-HMAC-SHA256 (RFC 8018) kwa package:crypto.
List<int> pbkdf2(List<int> password, List<int> salt, int iterations,
    {int length = 32}) {
  if (iterations < 1 || iterations > 1000000) {
    throw ArgumentError.value(
        iterations, 'iterations', 'Must be between 1 and 1000000.');
  }
  if (length < 1 || length > 1024) {
    throw ArgumentError.value(length, 'length', 'Must be between 1 and 1024.');
  }
  final hmac = Hmac(sha256, password);
  final out = <int>[];
  var block = 1;
  while (out.length < length) {
    var u = hmac.convert([
      ...salt,
      (block >> 24) & 255,
      (block >> 16) & 255,
      (block >> 8) & 255,
      block & 255
    ]).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.addAll(t);
    block++;
  }
  return out.sublist(0, length);
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

bool _constEq(String a, String b) {
  final left = a.codeUnits;
  final right = b.codeUnits;
  var different = left.length ^ right.length;
  final length = max(left.length, right.length);
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    different |= l ^ r;
  }
  return different == 0;
}

String hashPinPbkdf2(String pin, String saltHex, int iterations) {
  if (saltHex.length != 32 ||
      saltHex.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(saltHex)) {
    throw const FormatException(
        'PIN salt must contain 16 bytes of hexadecimal data.');
  }
  final salt = <int>[
    for (var i = 0; i + 1 < saltHex.length; i += 2)
      int.parse(saltHex.substring(i, i + 2), radix: 16)
  ];
  return _hex(pbkdf2(pin.codeUnits, salt, iterations));
}

String _legacyPinHash(String pin, String salt) {
  var h = 0xcbf29ce484222325;
  final input = '$salt:$pin';
  for (var round = 0; round < 5000; round++) {
    for (final u in input.codeUnits) {
      h ^= u;
      h = (h * 0x100000001b3) & 0x7fffffffffffffff;
    }
  }
  return h.toRadixString(16);
}

class LocalAuth {
  static const String pinAlgorithm = _pinHashAlgorithm;
  static const int iterations = int.fromEnvironment(
    'MADINI_PIN_PBKDF2_ITERATIONS',
    defaultValue: 600000,
  );
  static const int minConfiguredIterations = 100000;
  static const int maxIterations = 1000000;
  static const int maxAttempts = 5;

  static Future<Database> get _db async => DatabaseHelper.instance.database;

  static int get targetIterations {
    if (iterations < minConfiguredIterations || iterations > maxIterations) {
      throw AppError(
        'MADINI_PIN_PBKDF2_ITERATIONS lazima iwe kati ya '
        '$minConfiguredIterations na $maxIterations.',
      );
    }
    return iterations;
  }

  static String newSalt() {
    final r = Random.secure();
    return _hex(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  static Future<String> derivePinHash(String pin, String salt, int rounds) =>
      compute(_derivePinHashTask, <Object?>[pin, salt, rounds]);

  static bool constantTimeEquals(String left, String right) =>
      _constEq(left, right);

  static String legacyPinHash(String pin, String salt) =>
      _legacyPinHash(pin, salt);

  static Future<bool> hasUsers() async {
    final db = await _db;
    final n = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM local_users WHERE company_id = ? AND active = 1',
        [AppCtx.company]));
    return (n ?? 0) > 0;
  }

  static Future<List<Map<String, dynamic>>> listUsers() async {
    final db = await _db;
    return db.query('local_users',
        columns: ['uuid', 'username', 'full_name', 'role', 'active'],
        where: 'company_id = ?',
        whereArgs: [AppCtx.company],
        orderBy: 'full_name');
  }

  static void _checkPin(String pin) {
    if (!RegExp(r'^[0-9]{4,8}$').hasMatch(pin)) {
      throw AppError('PIN iwe na tarakimu 4 hadi 8.');
    }
  }

  static void _requirePinAdmin() {
    if (AppCtx.localAuthActive && !roleIsAdmin(AppCtx.role)) {
      throw AppError(
          'Mmiliki au Msimamizi tu ndiye anaweza kubadilisha PIN ya kufunga app.');
    }
  }

  static Future<void> _storeAppPin(
    String pin, {
    required String action,
  }) async {
    final rounds = targetIterations;
    final salt = newSalt();
    final hash = await derivePinHash(pin, salt, rounds);
    final db = await _db;
    await db.transaction((txn) async {
      for (final entry in <String, String>{
        'pin_salt': salt,
        'pin_hash': hash,
        'pin_algorithm': pinAlgorithm,
        'pin_iterations': '$rounds',
      }.entries) {
        await txn.insert(
          'app_settings',
          {'setting_key': entry.key, 'setting_value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await writeAudit(
        txn,
        entity: 'app_lock_pin',
        action: action,
        detail: '$pinAlgorithm, $rounds iterations',
      );
    });
    AppCtx.hasPin = true;
  }

  static Future<void> saveAppPin(String pin) async {
    _requirePinAdmin();
    _checkPin(pin);
    await _storeAppPin(
      pin,
      action: AppCtx.hasPin
          ? 'PIN ya kufunga app imebadilishwa'
          : 'PIN ya kufunga app imewekwa',
    );
  }

  static Future<void> removeAppPin() async {
    _requirePinAdmin();
    final db = await _db;
    await db.transaction((txn) async {
      for (final key in const [
        'pin_salt',
        'pin_hash',
        'pin_algorithm',
        'pin_iterations',
      ]) {
        await txn
            .delete('app_settings', where: 'setting_key = ?', whereArgs: [key]);
      }
      await writeAudit(txn,
          entity: 'app_lock_pin', action: 'PIN ya kufunga app imeondolewa');
    });
    AppCtx.hasPin = false;
  }

  static Future<bool> verifyAppPin(String pin) async {
    _checkPin(pin);
    final salt = await DatabaseHelper.instance.getSetting('pin_salt');
    final hash = await DatabaseHelper.instance.getSetting('pin_hash');
    final algorithm = await DatabaseHelper.instance.getSetting('pin_algorithm');
    final roundsText =
        await DatabaseHelper.instance.getSetting('pin_iterations');
    if (salt == null &&
        hash == null &&
        algorithm == null &&
        roundsText == null) {
      return true;
    }
    if (salt == null || hash == null) return false;

    if (algorithm == null) {
      if (!constantTimeEquals(_legacyPinHash(pin, salt), hash)) return false;
      await _storeAppPin(pin, action: 'PIN ya zamani imeboreshwa');
      return true;
    }
    if (algorithm != pinAlgorithm) {
      throw AppError('Algorithm ya PIN haitambuliki; wasiliana na msimamizi.');
    }
    if (salt.length != 32 || !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(salt)) {
      throw AppError('Chumvi ya PIN si sahihi; PIN haikuweza kuhakikiwa.');
    }
    final rounds = int.tryParse(roundsText ?? '');
    if (rounds == null || rounds < 1000 || rounds > maxIterations) {
      throw AppError('Metadata ya PIN si sahihi; PIN haikuweza kuhakikiwa.');
    }
    final actual = await derivePinHash(pin, salt, rounds);
    if (!constantTimeEquals(actual, hash)) return false;
    if (rounds < targetIterations) {
      await _storeAppPin(pin, action: 'PIN ya zamani imeboreshwa');
    }
    return true;
  }

  /// Mtumiaji wa kwanza wa kampuni anakuwa Mmiliki; baadaye ni Mmiliki/Msimamizi tu.
  static Future<void> createUser({
    required String username,
    required String fullName,
    required String role,
    required String pin,
  }) async {
    final first = !(await hasUsers());
    if (!first && !roleIsAdmin(AppCtx.role)) {
      throw AppError(
          'Mmiliki au Msimamizi tu ndiye anaweza kuongeza mtumiaji.');
    }
    final u = username.trim().toLowerCase();
    if (u.length < 3) {
      throw AppError('Jina la mtumiaji liwe na herufi 3 au zaidi.');
    }
    if (fullName.trim().isEmpty) throw AppError('Weka jina kamili.');
    if (!kRoleLabels.containsKey(role)) throw AppError('Jukumu halijulikani.');
    _checkPin(pin);
    final salt = newSalt();
    final rounds = targetIterations;
    final hash = await derivePinHash(pin, salt, rounds);
    final db = await _db;
    try {
      await db.transaction((txn) async {
        final uuid = newUuid();
        await txn.insert('local_users', {
          'uuid': uuid,
          'company_id': AppCtx.company,
          'username': u,
          'full_name': fullName.trim(),
          'role': first ? 'company_owner' : role,
          'pin_salt': salt,
          'pin_hash': hash,
          'pin_algorithm': pinAlgorithm,
          'pin_iterations': rounds,
          'active': 1,
          'created_at': nowIso(),
        });
        await writeAudit(txn,
            entity: 'user',
            entityUuid: uuid,
            action: 'Mtumiaji ameongezwa',
            detail: '$u (${first ? 'company_owner' : role})');
      });
    } on DatabaseException {
      throw AppError('Jina hilo la mtumiaji tayari lipo.');
    }
  }

  static Future<void> setActive(String uuid, bool active) async {
    if (!roleIsAdmin(AppCtx.role)) throw AppError('Hairuhusiwi.');
    if (uuid == AppCtx.userUuid && !active) {
      throw AppError('Huwezi kujizima mwenyewe.');
    }
    final db = await _db;
    await db.update('local_users', {'active': active ? 1 : 0},
        where: 'uuid = ? AND company_id = ?',
        whereArgs: [uuid, AppCtx.company]);
  }

  static Future<void> resetPin(String uuid, String pin) async {
    if (!roleIsAdmin(AppCtx.role) && uuid != AppCtx.userUuid) {
      throw AppError('Hairuhusiwi.');
    }
    _checkPin(pin);
    final salt = newSalt();
    final rounds = targetIterations;
    final hash = await derivePinHash(pin, salt, rounds);
    final db = await _db;
    await db.transaction((txn) async {
      final changed = await txn.update(
        'local_users',
        {
          'pin_salt': salt,
          'pin_hash': hash,
          'pin_algorithm': pinAlgorithm,
          'pin_iterations': rounds,
          'failed_attempts': 0,
          'locked_until': null,
        },
        where: 'uuid = ? AND company_id = ?',
        whereArgs: [uuid, AppCtx.company],
      );
      if (changed != 1) throw AppError('Mtumiaji hajapatikana.');
      await writeAudit(txn,
          entity: 'user', entityUuid: uuid, action: 'PIN imebadilishwa');
    });
  }

  /// Inathibitisha username/jina kamili + PIN. Inafunga akaunti baada ya majaribio 5 yaliyoshindwa.
  static Future<Map<String, Object?>> verifyUser(
      String nameOrUsername, String pin) async {
    _checkPin(pin);
    final db = await _db;
    final key = nameOrUsername.trim().toLowerCase();
    final rows = await db.query('local_users',
        where:
            'company_id = ? AND active = 1 AND (username = ? OR lower(full_name) = ?)',
        whereArgs: [AppCtx.company, key, key],
        limit: 1);
    if (rows.isEmpty) throw AppError('Mtumiaji huyo hajapatikana.');
    final u = rows.first;
    final locked = u['locked_until'] as String?;
    if (locked != null && locked.compareTo(nowIso()) > 0) {
      throw AppError('Akaunti imefungwa kwa muda. Jaribu tena baadaye.');
    }
    if (u['pin_algorithm'] != pinAlgorithm) {
      throw AppError('Algorithm ya PIN haitambuliki; wasiliana na msimamizi.');
    }
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(u['pin_salt'] as String)) {
      throw AppError('Chumvi ya PIN si sahihi; PIN haikuweza kuhakikiwa.');
    }
    final oldIterations = intv(u['pin_iterations']);
    if (oldIterations < 1000 || oldIterations > maxIterations) {
      throw AppError('Metadata ya PIN si sahihi; PIN haikuweza kuhakikiwa.');
    }
    final salt = u['pin_salt'] as String;
    final oldHash = u['pin_hash'] as String;
    final ok = constantTimeEquals(
      await derivePinHash(pin, salt, oldIterations),
      oldHash,
    );
    if (!ok) {
      final fails = intv(u['failed_attempts']) + 1;
      await db.update(
          'local_users',
          {
            'failed_attempts': fails >= maxAttempts ? 0 : fails,
            'locked_until': fails >= maxAttempts
                ? DateTime.now()
                    .add(const Duration(minutes: 5))
                    .toIso8601String()
                : null,
          },
          where: 'uuid = ? AND company_id = ? AND active = 1',
          whereArgs: [u['uuid'], AppCtx.company]);
      throw AppError(fails >= maxAttempts
          ? 'Majaribio mengi. Akaunti imefungwa dakika 5.'
          : 'PIN si sahihi.');
    }

    final rounds = targetIterations;
    final upgraded = oldIterations < rounds;
    final nextSalt = upgraded ? newSalt() : salt;
    final nextHash =
        upgraded ? await derivePinHash(pin, nextSalt, rounds) : oldHash;
    final changed = await db.update(
      'local_users',
      {
        if (upgraded) ...{
          'pin_salt': nextSalt,
          'pin_hash': nextHash,
          'pin_iterations': rounds,
          'pin_algorithm': pinAlgorithm,
        },
        'failed_attempts': 0,
        'locked_until': null,
      },
      where: 'uuid = ? AND company_id = ? AND active = 1 '
          'AND pin_hash = ? AND pin_salt = ? AND pin_iterations = ? AND pin_algorithm = ?',
      whereArgs: [
        u['uuid'],
        AppCtx.company,
        oldHash,
        salt,
        oldIterations,
        pinAlgorithm,
      ],
    );
    if (changed != 1) {
      throw AppError('PIN imebadilishwa; ingia tena kwa PIN mpya.');
    }
    return u;
  }

  static Future<void> login(String username, String pin) async {
    final u = await verifyUser(username, pin);
    AppCtx.userUuid = u['uuid'] as String;
    AppCtx.role = u['role'] as String;
    AppCtx.sessionName = u['full_name'] as String;
    AppCtx.user = AppCtx.sessionName;
    final db = await _db;
    await db.transaction((txn) => writeAudit(txn,
        entity: 'user', entityUuid: AppCtx.userUuid, action: 'Ameingia'));
  }

  static void logout() {
    AppCtx.userUuid = '';
    AppCtx.role = 'company_owner';
    AppCtx.sessionName = '';
    appReload.value++;
  }

  /// Shahidi lazima awe mtumiaji TOFAUTI aliyethibitishwa kwa PIN yake mwenyewe.
  /// Ikiwa kampuni haina watumiaji wa ndani, inarudisha null (jina la maandishi pekee).
  static Future<String?> confirmWitness(
      BuildContext context, String witnessName) async {
    if (!AppCtx.localAuthActive) return null;
    final pin = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Thibitisha shahidi')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${tr('Shahidi')}: $witnessName'),
          TextField(
              controller: pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PIN ya shahidi')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Ghairi'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Thibitisha'))),
        ],
      ),
    );
    final p = pin.text;
    pin.dispose();
    if (go != true) throw AppError('Uthibitisho wa shahidi umeghairiwa.');
    final u = await verifyUser(witnessName, p);
    if (u['uuid'] == AppCtx.userUuid) {
      throw AppError('Shahidi lazima awe mtu tofauti na aliyeingiza rekodi.');
    }
    return u['uuid'] as String;
  }
}

/// Skrini ya kuingia kwa watumiaji wa kifaa.
class LocalLoginPage extends StatefulWidget {
  final VoidCallback onDone;
  const LocalLoginPage({super.key, required this.onDone});

  @override
  State<LocalLoginPage> createState() => _LocalLoginPageState();
}

class _LocalLoginPageState extends State<LocalLoginPage> {
  final _user = TextEditingController();
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _user.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await LocalAuth.login(_user.text, _pin.text);
      _pin.clear();
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.diamond_outlined, size: 56),
                const SizedBox(height: 8),
                Text('Madini Track Tanzania',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(AppCtx.company),
                const SizedBox(height: 24),
                TextField(
                    controller: _user,
                    decoration: InputDecoration(
                        labelText: tr('Jina la mtumiaji'),
                        border: const OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _go(),
                  decoration: const InputDecoration(
                      labelText: 'PIN', border: OutlineInputBorder()),
                ),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: _busy ? null : _go, child: Text(tr('Ingia'))),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
