import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database_helper.dart';
import 'db_reports.dart';
import 'utils.dart';

class BackupPreview {
  final String createdAt;
  final int schemaVersion;
  final bool encrypted;
  final Map<String, int> counts;
  final String json;
  const BackupPreview(this.createdAt, this.schemaVersion, this.encrypted,
      this.counts, this.json);

  int get totalRows => counts.values.fold(0, (a, b) => a + b);
}

/// Backup ya faili halisi: schema version, SHA-256 checksum, usimbaji wa hiari
/// (AES-256-GCM, ufunguo kutoka PBKDF2-HMAC-SHA256), preview kabla ya restore, na
/// snapshot ya hali ya sasa kabla ya kurejesha.
class BackupService {
  static const String format = 'madini_track_backup';
  static const int _iterations = 60000;

  static List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  static Future<SecretKey> _deriveKey(
      String password, List<int> salt, int iterations) {
    return Pbkdf2(
            macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
        .deriveKeyFromPassword(password: password, nonce: salt);
  }

  static Future<Directory> backupDir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'backups'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> createBackupFile(
      {String? password, String prefix = 'madini_backup'}) async {
    final json = await DatabaseHelper.instance.exportBackupJson();
    final plain = utf8.encode(json);
    final envelope = <String, dynamic>{
      'format': format,
      'format_version': 1,
      'schema_version': kDbVersion,
      'created_at': nowIso(),
      'sha256': crypto.sha256.convert(plain).toString(),
      'encrypted': false,
    };
    if (password != null && password.isNotEmpty) {
      final salt = _randomBytes(16);
      final key = await _deriveKey(password, salt, _iterations);
      final box = await AesGcm.with256bits().encrypt(plain, secretKey: key);
      envelope['encrypted'] = true;
      envelope['kdf'] = {
        'name': 'pbkdf2-hmac-sha256',
        'iterations': _iterations,
        'salt': base64Encode(salt),
      };
      envelope['payload'] = base64Encode(box.concatenation());
    } else {
      envelope['payload'] = json;
    }
    final dir = await backupDir();
    final stamp = nowIso().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
    final file = File(p.join(dir.path, '${prefix}_$stamp.mtbackup'));
    await file.writeAsString(jsonEncode(envelope), flush: true);
    return file;
  }

  /// Inathibitisha faili (muundo, checksum, nywila) BILA kubadilisha database.
  static Future<BackupPreview> inspect(String fileText,
      {String? password}) async {
    Map<String, dynamic> env;
    try {
      env = jsonDecode(fileText) as Map<String, dynamic>;
    } catch (_) {
      throw AppError('Faili si backup sahihi ya Madini Track.');
    }
    if (env['format'] != format ||
        env['format_version'] != 1 ||
        env['payload'] is! String) {
      throw AppError('Faili si backup sahihi ya Madini Track.');
    }
    final schema = env['schema_version'];
    if (schema is! int || schema < 7 || schema > kDbVersion) {
      throw AppError(
          'Backup hii ni ya toleo jipya zaidi la app. Sasisha app kwanza.');
    }
    final encrypted = env['encrypted'] == true;
    List<int> plain;
    if (encrypted) {
      if (password == null || password.isEmpty) {
        throw AppError('Backup hii imesimbwa; weka nywila.');
      }
      try {
        final kdf = env['kdf'] as Map<String, dynamic>;
        final key = await _deriveKey(password,
            base64Decode(kdf['salt'] as String), kdf['iterations'] as int);
        final box = SecretBox.fromConcatenation(
            base64Decode(env['payload'] as String),
            nonceLength: 12,
            macLength: 16);
        plain = await AesGcm.with256bits().decrypt(box, secretKey: key);
      } catch (_) {
        throw AppError('Nywila si sahihi au faili limeharibika.');
      }
    } else {
      plain = utf8.encode(env['payload'] as String);
    }
    final digest = crypto.sha256.convert(plain).toString();
    if (digest != env['sha256']) {
      throw AppError(
          'Checksum haiendani: faili limeharibika au limebadilishwa.');
    }
    final json = utf8.decode(plain);
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final tables = (decoded['tables'] as Map?) ?? const {};
    final counts = <String, int>{
      for (final e in tables.entries) e.key as String: (e.value as List).length,
    };
    return BackupPreview(
        env['created_at'] as String? ?? '', schema, encrypted, counts, json);
  }

  static Future<File?> restore(BackupPreview preview) async {
    // Snapshot ya hali ya sasa kabla ya kubadilisha chochote.
    final snapshot = await createBackupFile(prefix: 'kabla_ya_restore');
    await DatabaseHelper.instance.restoreBackupJson(preview.json);
    return snapshot;
  }
}
