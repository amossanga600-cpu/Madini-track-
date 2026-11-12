import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'app_context.dart';
import 'database_helper.dart';
import 'utils.dart';

class SyncSummary {
  int applied = 0;
  int duplicate = 0;
  int conflicts = 0;
  int rejected = 0;
  int failed = 0;
  bool authRequired = false;
  String? error;

  int get delivered => applied + duplicate;
  @override
  String toString() =>
      'imetumwa: $delivered, mgongano: $conflicts, imekataliwa: $rejected, imeshindwa: $failed'
      '${authRequired ? ', inahitaji kuingia tena' : ''}${error == null ? '' : ', kosa: $error'}';
}

class PullSummary {
  int applied = 0;
  int skipped = 0;
  int deferred = 0;
  int pages = 0;
  bool authRequired = false;
  String? error;
  @override
  String toString() =>
      'zimepakuliwa: $applied, zimeruka: $skipped, zimeahirishwa: $deferred'
      '${authRequired ? ', inahitaji kuingia tena' : ''}${error == null ? '' : ', kosa: $error'}';
}

/// Sync halisi ya Transactional Outbox. Rekodi inatambuliwa kuwa "Synced" TU baada ya
/// seva kurudisha acknowledgement ya `applied`/`duplicate` kwa idempotency key yake.
class SyncService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'madini_sync_token';
  static bool _running = false;

  /// Inaweza kubadilishwa kwenye tests (secure storage haipo kwenye unit tests).
  static Future<String?> Function() tokenProvider =
      () => _storage.read(key: _tokenKey);
  static Future<void> Function(String) tokenWriter =
      (t) => _storage.write(key: _tokenKey, value: t);

  static bool _pulling = false;

  /// UUID ya kampuni hii kwenye simu; seva inatumia ile ile kama tenant id.
  static Future<String?> localCompanyUuid() async {
    final db = await DatabaseHelper.instance.database;
    final r = await db.query('companies',
        columns: ['uuid'],
        where: 'name = ?',
        whereArgs: [AppCtx.company],
        limit: 1);
    return r.isEmpty ? null : r.first['uuid'] as String?;
  }

  static int? _tokenExp(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
      return payload['exp'] as int?;
    } catch (_) {
      return null;
    }
  }

  /// Token ikibakiwa na chini ya saa 1, ihuishwe (refresh) kabla ya kutumika.
  static Future<String?> _freshToken(String url, http.Client c) async {
    final t = await tokenProvider();
    if (t == null) return null;
    final exp = _tokenExp(t);
    if (exp != null &&
        exp - DateTime.now().millisecondsSinceEpoch ~/ 1000 < 3600) {
      try {
        final res = await c.post(Uri.parse('$url/v1/auth/refresh'), headers: {
          'Authorization': 'Bearer $t'
        }).timeout(const Duration(seconds: 20));
        if (res.statusCode == 200) {
          final nt = (jsonDecode(res.body)
              as Map<String, dynamic>)['access_token'] as String?;
          if (nt != null && nt.isNotEmpty) {
            await tokenWriter(nt);
            return nt;
          }
        }
      } catch (_) {
        // Bila mtandao: tumia token iliyopo; itashindwa kwa 401 ikiwa imeisha.
      }
    }
    return t;
  }

  static String _detail(http.Response res) {
    try {
      final d = (jsonDecode(res.body) as Map<String, dynamic>)['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty && d.first is Map) {
        return (d.first as Map)['msg']?.toString() ?? 'taarifa si sahihi';
      }
    } catch (_) {}
    return 'Seva imejibu ${res.statusCode}.';
  }

  static Future<String?> serverUrl() async {
    final saved = await DatabaseHelper.instance.getSetting('sync_url');
    return saved == null ? null : normalizeServerUrl(saved);
  }

  static String normalizeServerUrl(String url) {
    final value = url.trim();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw AppError('Anwani ya seva si sahihi.');
    }
    final localHosts = {'localhost', '127.0.0.1', '::1', '10.0.2.2'};
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' && localHosts.contains(uri.host))) {
      throw AppError('Seva lazima itumie HTTPS; HTTP inaruhusiwa kwa majaribio ya kifaa cha ndani pekee.');
    }
    return uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), '')).toString();
  }

  static Future<void> saveServerUrl(String url) async {
    final u = normalizeServerUrl(url);
    await DatabaseHelper.instance.setSetting('sync_url', u);
  }

  /// Muda wa kusubiri kabla ya jaribio lijalo: 30s, 60s, 120s ... hadi saa 6.
  static int backoffSeconds(int retryCount) {
    final n = retryCount < 0 ? 0 : (retryCount > 10 ? 10 : retryCount);
    return min(30 * (1 << n), 6 * 3600);
  }

  static Future<void> login({
    required String username,
    required String password,
    http.Client? client,
  }) async {
    final url = await serverUrl();
    if (url == null) throw AppError('Weka anwani ya seva kwanza.');
    final c = client ?? http.Client();
    try {
      final res = await c
          .post(
            Uri.parse('$url/v1/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username.trim(),
              'password': password,
              'device_id': await DatabaseHelper.instance.getDeviceId(),
              'device_name': 'Android',
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw AppError(res.statusCode == 401
            ? 'Jina la mtumiaji au nywila si sahihi.'
            : _detail(res));
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final token = body['access_token'] as String?;
      if (token == null || token.isEmpty) {
        throw AppError('Seva haikurudisha token.');
      }
      // Hakikisha akaunti ina uanachama wa kampuni hii (UUID lazima ilingane na ya seva).
      final me = await c.get(Uri.parse('$url/v1/auth/me'), headers: {
        'Authorization': 'Bearer $token'
      }).timeout(const Duration(seconds: 30));
      if (me.statusCode != 200) {
        throw AppError(_detail(me));
      }
      final meBody = jsonDecode(me.body) as Map<String, dynamic>;
      final memberships = meBody['memberships'] as Map? ?? const {};
      final mine = await localCompanyUuid();
      if (mine == null || !memberships.containsKey(mine)) {
        throw AppError(
            'Akaunti hii haina uanachama wa kampuni hii. Mwambie msimamizi wa seva atumie UUID ya kampuni: ${mine ?? '-'}');
      }
      await tokenWriter(token);
    } finally {
      if (client == null) c.close();
    }
  }

  static Future<void> logout({http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final token = await tokenProvider();
      final url = await serverUrl();
      if (token != null && url != null) {
        final response = await c
            .post(
              Uri.parse('$url/v1/auth/logout'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw AppError(
              'Token imeondolewa kwenye kifaa, lakini seva haikuthibitisha kutoka.');
        }
      }
    } catch (error) {
      await _storage.delete(key: _tokenKey);
      if (error is AppError) rethrow;
      throw AppError(
          'Token imeondolewa kwenye kifaa; seva haikufikiwa ili kuifuta.');
    } finally {
      if (client == null) c.close();
    }
    await _storage.delete(key: _tokenKey);
  }

  static Future<bool> hasToken() async => (await tokenProvider()) != null;

  static Future<SyncSummary> syncNow(
      {http.Client? client, int batchSize = 50}) async {
    final summary = SyncSummary();
    if (_running) {
      summary.error = 'Sync tayari inaendelea.';
      return summary;
    }
    _running = true;
    final c = client ?? http.Client();
    try {
      final url = await serverUrl();
      final token = url == null ? null : await _freshToken(url, c);
      if (url == null || token == null) {
        summary.authRequired = true;
        return summary;
      }
      final db = await DatabaseHelper.instance.database;
      final deviceId = await DatabaseHelper.instance.getDeviceId();

      await _recoverStuck(db);

      // Chagua events zilizo tayari na uzifunge kama 'sending' ndani ya transaction.
      final due = await db.transaction<List<Map<String, Object?>>>((txn) async {
        final rows = await txn.rawQuery(
          "SELECT * FROM sync_outbox WHERE sync_status IN ('pending','failed') "
          'AND (next_retry_at IS NULL OR next_retry_at <= ?) ORDER BY id LIMIT ?',
          [nowIso(), batchSize],
        );
        for (final r in rows) {
          await txn.update(
              'sync_outbox', {'sync_status': 'sending', 'updated_at': nowIso()},
              where: 'uuid = ?', whereArgs: [r['uuid']]);
        }
        return rows;
      });
      if (due.isEmpty) {
        await _touchLastSync(db);
        return summary;
      }

      // Jenga events kutoka kwenye hali ya SASA ya kila rekodi.
      final events = <Map<String, Object?>>[];
      final byKey = <String, Map<String, Object?>>{};
      final sentVersion = <String, int>{};
      for (final ob in due) {
        final entity = ob['entity'] as String;
        if (!kSyncTables.contains(entity)) {
          await _finish(db, ob, 'rejected', error: 'entity_haikubaliki');
          summary.rejected++;
          continue;
        }
        final rows = await db.query(entity,
            where: 'uuid = ?', whereArgs: [ob['record_uuid']], limit: 1);
        if (rows.isEmpty) {
          await _finish(db, ob, 'rejected', error: 'rekodi_haipo');
          summary.rejected++;
          continue;
        }
        final row = Map<String, Object?>.from(rows.first);
        final version = intv(row['version']);
        final key = '$entity:${ob['record_uuid']}:$version';
        String? companyUuid;
        if (entity == 'companies') {
          companyUuid = row['uuid'] as String?;
        } else {
          final cr = await db.query('companies',
              columns: ['uuid'],
              where: 'name = ?',
              whereArgs: [ob['company_name']],
              limit: 1);
          if (cr.isNotEmpty) companyUuid = cr.first['uuid'] as String?;
        }
        if (companyUuid == null) {
          await _finish(db, ob, 'rejected', error: 'kampuni_haijulikani');
          summary.rejected++;
          continue;
        }
        final ev = <String, Object?>{
          'idempotency_key': key,
          'entity': entity,
          'record_uuid': ob['record_uuid'],
          'company_uuid': companyUuid,
          'version': version,
          'data': row,
        };
        events.add(ev);
        byKey[key] = ob;
        sentVersion[key] = version;
      }
      if (events.isEmpty) return summary;

      http.Response res;
      try {
        res = await c
            .post(
              Uri.parse('$url/v1/sync/push'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token'
              },
              body: jsonEncode({'device_id': deviceId, 'events': events}),
            )
            .timeout(const Duration(seconds: 45));
      } catch (e) {
        for (final ob in byKey.values) {
          await _finish(db, ob, 'failed',
              error: 'mtandao: ${errText(e)}', result: 'network_error');
          summary.failed++;
        }
        summary.error = 'Hakuna mtandao au seva haipatikani.';
        return summary;
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        for (final ob in byKey.values) {
          await _finish(db, ob, 'pending',
              error: 'auth',
              result: 'auth_required',
              httpStatus: res.statusCode,
              bumpRetry: false);
        }
        summary.authRequired = true;
        return summary;
      }
      if (res.statusCode != 200) {
        for (final ob in byKey.values) {
          await _finish(db, ob, 'failed',
              error: 'http_${res.statusCode}',
              result: 'server_error',
              httpStatus: res.statusCode);
          summary.failed++;
        }
        summary.error = 'Seva imejibu ${res.statusCode}.';
        return summary;
      }

      Map<String, dynamic> body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        for (final ob in byKey.values) {
          await _finish(db, ob, 'failed',
              error: 'jibu_batili', result: 'bad_response', httpStatus: 200);
          summary.failed++;
        }
        summary.error = 'Jibu la seva si sahihi.';
        return summary;
      }

      final acked = <String>{};
      for (final r in (body['results'] as List? ?? const [])) {
        final m = r as Map<String, dynamic>;
        final key = m['idempotency_key'] as String?;
        final ob = key == null ? null : byKey[key];
        if (ob == null) continue;
        acked.add(key!);
        final status = m['status'] as String?;
        final msg = m['message'] as String?;
        if (status == 'applied' || status == 'duplicate') {
          await db.transaction((txn) async {
            await txn.update(
                'sync_outbox',
                {
                  'sync_status': 'synced',
                  'updated_at': nowIso(),
                  'last_error': null
                },
                where: 'uuid = ?',
                whereArgs: [ob['uuid']]);
            await _attempt(txn, ob['uuid'] as String, status!, 200, null);
            // Weka Synced TU ikiwa rekodi haijabadilika tangu ilipotumwa.
            await txn.update(ob['entity'] as String, {'sync_status': 'Synced'},
                where: 'uuid = ? AND version = ?',
                whereArgs: [ob['record_uuid'], sentVersion[key]]);
          });
          if (status == 'applied') {
            summary.applied++;
          } else {
            summary.duplicate++;
          }
        } else if (status == 'conflict') {
          await _finish(db, ob, 'conflict',
              error: msg ?? 'mgongano', result: 'conflict', httpStatus: 200);
          summary.conflicts++;
        } else {
          await _finish(db, ob, 'rejected',
              error: msg ?? 'imekataliwa', result: 'rejected', httpStatus: 200);
          summary.rejected++;
        }
      }
      // Event yoyote ambayo seva haikuijibu HAIHESABIWI kuwa imefanikiwa.
      for (final e in byKey.entries) {
        if (!acked.contains(e.key)) {
          await _finish(db, e.value, 'failed',
              error: 'hakuna_ack', result: 'no_ack', httpStatus: 200);
          summary.failed++;
        }
      }
      if (summary.failed == 0) await _touchLastSync(db);
      return summary;
    } finally {
      if (client == null) c.close();
      _running = false;
    }
  }

  // ------------------------------------------------------------------ PULL
  static Future<String?> _state(Database db, String key) async {
    final r = await db.query('sync_state',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  static Future<void> _setState(Database db, String key, String value) async {
    await db.insert(
        'sync_state', {'key': key, 'value': value, 'updated_at': nowIso()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Pakua mabadiliko ya vifaa vingine. Data iliyopakuliwa haitengenezi events za kutuma tena
  /// (flag `applying_pull` ndani ya transaction moja), na rekodi zenye mabadiliko ya ndani
  /// yasiyotumwa HAZIFUTWI: zinaachwa na seva itaamua mgongano wakati wa push.
  static Future<PullSummary> pullNow({http.Client? client}) async {
    final s = PullSummary();
    if (_pulling) {
      s.error = 'Pull tayari inaendelea.';
      return s;
    }
    _pulling = true;
    final c = client ?? http.Client();
    try {
      final url = await serverUrl();
      final token = url == null ? null : await _freshToken(url, c);
      final company = await localCompanyUuid();
      if (url == null || token == null) {
        s.authRequired = true;
        return s;
      }
      if (company == null) {
        s.error = 'Kampuni haijapatikana kwenye simu.';
        return s;
      }
      final db = await DatabaseHelper.instance.database;
      final deviceId = await DatabaseHelper.instance.getDeviceId();
      var cursor =
          int.tryParse(await _state(db, 'pull_cursor_$company') ?? '0') ?? 0;
      for (var page = 0; page < 50; page++) {
        http.Response res;
        try {
          res = await c.get(
              Uri.parse(
                  '$url/v1/sync/pull?company_uuid=$company&cursor=$cursor&limit=200'),
              headers: {
                'Authorization': 'Bearer $token'
              }).timeout(const Duration(seconds: 45));
        } catch (e) {
          s.error = 'Hakuna mtandao au seva haipatikani.';
          return s;
        }
        if (res.statusCode == 401) {
          s.authRequired = true;
          return s;
        }
        if (res.statusCode != 200) {
          s.error = _detail(res);
          return s;
        }
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        await _applyPulled(
            db, (body['records'] as List? ?? const []), deviceId, s);
        cursor = (body['next_cursor'] as num?)?.toInt() ?? cursor;
        await _setState(db, 'pull_cursor_$company', '$cursor');
        s.pages++;
        if (body['has_more'] != true) break;
      }
      await _setState(db, 'last_pull_at', nowIso());
      return s;
    } finally {
      if (client == null) c.close();
      _pulling = false;
    }
  }

  static Future<void> _applyPulled(
      Database db, List records, String deviceId, PullSummary s) async {
    var todo = <Map<String, dynamic>>[
      for (final r in records)
        if (r is Map<String, dynamic>) r
    ];
    // Pasi 2: mtoto (mfano attendance) akifika kabla ya mzazi, anajaribiwa tena baada ya wengine.
    for (var pass = 0; pass < 2 && todo.isNotEmpty; pass++) {
      final failed = <Map<String, dynamic>>[];
      for (final r in todo) {
        try {
          if (await _applyOne(db, r, deviceId)) {
            s.applied++;
          } else {
            s.skipped++;
          }
        } on DatabaseException {
          failed.add(r);
        }
      }
      todo = failed;
    }
    if (todo.isNotEmpty) {
      s.deferred += todo.length;
      await _setState(
          db,
          'pull_failed',
          todo
              .map((r) => '${r['entity']}:${r['record_uuid']}')
              .take(50)
              .join(','));
    }
  }

  static Future<bool> _applyOne(
      Database db, Map<String, dynamic> r, String deviceId) async {
    final entity = r['entity'] as String?;
    final uuid = r['record_uuid'] as String?;
    if (entity == null || uuid == null || !kSyncTables.contains(entity)) {
      return false;
    }
    if (r['device_id'] == deviceId) return false; // data ya kifaa hiki chenyewe
    final data = Map<String, Object?>.from(r['data'] as Map);
    final version = intv(r['version']);
    return db.transaction<bool>((txn) async {
      final cols = (await txn.rawQuery('PRAGMA table_info($entity)'))
          .map((c) => c['name'] as String)
          .toSet();
      final row = <String, Object?>{
        for (final e in data.entries)
          if (cols.contains(e.key) && e.key != 'id') e.key: e.value,
      };
      row['sync_status'] = 'Synced';
      row['version'] = version;
      final local = await txn.query(entity,
          columns: ['version', 'sync_status'],
          where: 'uuid = ?',
          whereArgs: [uuid],
          limit: 1);
      if (local.isNotEmpty) {
        if (local.first['sync_status'] != 'Synced') return false;
        if (intv(local.first['version']) >= version) return false;
      }
      await txn.execute(
          "INSERT OR REPLACE INTO sync_state(key, value, updated_at) VALUES('applying_pull', '1', ?)",
          [nowIso()]);
      try {
        if (local.isEmpty) {
          await txn.insert(entity, row);
        } else {
          await txn.update(entity, row, where: 'uuid = ?', whereArgs: [uuid]);
        }
      } finally {
        await txn.execute(
            "UPDATE sync_state SET value = '0' WHERE key = 'applying_pull'");
      }
      return true;
    });
  }

  // ------------------------------------------------------------------ CONFLICTS
  static Future<Map<String, String>?> _authHeaders(
      String url, http.Client c) async {
    final t = await _freshToken(url, c);
    return t == null
        ? null
        : {'Authorization': 'Bearer $t', 'Content-Type': 'application/json'};
  }

  static Future<List<Map<String, dynamic>>> listConflicts(
      {http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final url = await serverUrl();
      final company = await localCompanyUuid();
      final h = url == null ? null : await _authHeaders(url, c);
      if (url == null || h == null || company == null) {
        throw AppError('Weka seva na uingie kwanza.');
      }
      final res = await c
          .get(Uri.parse('$url/v1/sync/conflicts?company_uuid=$company'),
              headers: h)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw AppError(_detail(res));
      return ((jsonDecode(res.body) as Map<String, dynamic>)['conflicts']
              as List)
          .cast<Map<String, dynamic>>();
    } finally {
      if (client == null) c.close();
    }
  }

  /// decision: 'accept_conflict' (kubali toleo la kifaa hicho) au 'keep_server' (baki na la seva).
  static Future<void> resolveConflict(int id, String decision,
      {http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final url = await serverUrl();
      final company = await localCompanyUuid();
      final h = url == null ? null : await _authHeaders(url, c);
      if (url == null || h == null || company == null) {
        throw AppError('Weka seva na uingie kwanza.');
      }
      final res = await c
          .post(
              Uri.parse(
                  '$url/v1/sync/conflicts/$id/resolve?company_uuid=$company'),
              headers: h,
              body: jsonEncode({'decision': decision}))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw AppError(_detail(res));
    } finally {
      if (client == null) c.close();
    }
  }

  // ------------------------------------------------------------------ ndani
  static Future<void> _recoverStuck(Database db) async {
    // Events zilizokwama 'sending' (app ilifungwa katikati) zinarudishwa, au zinawekwa
    // 'rejected: superseded' ikiwa tayari kuna event mpya wazi kwa rekodi ile ile.
    await db.execute(
        "UPDATE sync_outbox SET sync_status = 'rejected', last_error = 'superseded' "
        "WHERE sync_status = 'sending' AND EXISTS (SELECT 1 FROM sync_outbox o2 "
        "WHERE o2.entity = sync_outbox.entity AND o2.record_uuid = sync_outbox.record_uuid "
        "AND o2.sync_status IN ('pending','failed'))");
    await db.execute(
        "UPDATE sync_outbox SET sync_status = 'pending' WHERE sync_status = 'sending'");
  }

  static Future<void> _touchLastSync(Database db) async {
    await db.insert('sync_state',
        {'key': 'last_sync_at', 'value': nowIso(), 'updated_at': nowIso()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> _attempt(DatabaseExecutor ex, String outboxUuid,
      String result, int? httpStatus, String? err) {
    return ex.insert('sync_attempts', {
      'outbox_uuid': outboxUuid,
      'attempted_at': nowIso(),
      'http_status': httpStatus,
      'result': result,
      'error': err,
    });
  }

  /// Hamisha event kutoka 'sending' kwenda hali ya mwisho/ya kujaribu tena.
  static Future<void> _finish(
    Database db,
    Map<String, Object?> ob,
    String status, {
    String? error,
    String result = 'local',
    int? httpStatus,
    bool bumpRetry = true,
  }) async {
    await db.transaction((txn) async {
      var finalStatus = status;
      var retry = intv(ob['retry_count']);
      String? next;
      if (status == 'failed' || status == 'pending') {
        // Epuka kuvunja uq_outbox_open: ikiwa event mpya wazi ipo, hii imepitwa.
        final open = await txn.rawQuery(
          "SELECT 1 FROM sync_outbox WHERE entity = ? AND record_uuid = ? "
          "AND sync_status IN ('pending','failed') AND uuid <> ? LIMIT 1",
          [ob['entity'], ob['record_uuid'], ob['uuid']],
        );
        if (open.isNotEmpty) {
          finalStatus = 'rejected';
          error = 'superseded';
        } else if (status == 'failed') {
          retry += bumpRetry ? 1 : 0;
          next = DateTime.now()
              .add(Duration(seconds: backoffSeconds(retry)))
              .toIso8601String();
        }
      }
      await txn.update(
        'sync_outbox',
        {
          'sync_status': finalStatus,
          'retry_count': retry,
          'next_retry_at': next,
          'last_error': error,
          'updated_at': nowIso(),
        },
        where: 'uuid = ?',
        whereArgs: [ob['uuid']],
      );
      await _attempt(txn, ob['uuid'] as String, result, httpStatus, error);
    });
  }
}
