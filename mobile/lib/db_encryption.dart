import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class DbKeyMissingError implements Exception {
  final String message;

  DbKeyMissingError(this.message);

  @override
  String toString() => message;
}

class DbEncryption {
  static const _keyName = 'madini_db_key_v1';
  static const _plainHeader = 'SQLite format 3\u0000';
  static const _keyPattern = r'^[0-9a-f]{64}$';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<String?> Function() keyReader =
      () => _storage.read(key: _keyName);
  static Future<void> Function(String) keyWriter =
      (key) => _storage.write(key: _keyName, value: key);

  static Future<String>? _creating;

  static String generateKeyHex({Random? rng}) {
    final random = rng ?? Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static bool _validKey(String? key) =>
      key != null && RegExp(_keyPattern).hasMatch(key);

  static Future<String> _getOrCreateKey() async {
    final pending = _creating;
    if (pending != null) return pending;

    final existing = await keyReader();
    if (existing != null) {
      if (!_validKey(existing)) {
        throw DbKeyMissingError(
          'Ufunguo wa database haujatambulika. Data haijabadilishwa; '
          'wasiliana na msimamizi au rejesha backup.',
        );
      }
      return existing;
    }

    final pendingAfterRead = _creating;
    if (pendingAfterRead != null) return pendingAfterRead;

    final created = () async {
      final key = generateKeyHex();
      await keyWriter(key);
      if (await keyReader() != key) {
        throw DbKeyMissingError(
          'Imeshindikana kuhifadhi ufunguo wa usalama kwenye kifaa.',
        );
      }
      return key;
    }();
    _creating = created;
    try {
      return await created;
    } finally {
      _creating = null;
    }
  }

  static Future<bool> isPlainSqlite(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    final handle = await file.open();
    try {
      final header = await handle.read(_plainHeader.length);
      return String.fromCharCodes(header) == _plainHeader;
    } finally {
      await handle.close();
    }
  }

  static Future<void> _removeDatabaseFiles(String path) async {
    for (final suffix in ['', '-journal', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  static Future<void> _removeDatabaseSidecars(String path) async {
    for (final suffix in ['-journal', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  static Future<String> prepare(String path) async {
    final old = '$path.plain-old';
    final temporary = '$path.enc.tmp';
    final original = File(path);
    final oldFile = File(old);

    if (!await original.exists() && await oldFile.exists()) {
      await oldFile.rename(path);
      await _removeDatabaseFiles(temporary);
    } else if (await original.exists() && await oldFile.exists()) {
      if (await isPlainSqlite(path)) {
        throw DbKeyMissingError(
          'Database ya awali na nakala ya uhamishaji zipo pamoja. '
          'Hazijabadilishwa; wasiliana na msimamizi.',
        );
      }
      final key = await keyReader();
      if (!_validKey(key)) {
        throw DbKeyMissingError(
          'Ufunguo wa database haupo. Nakala ya urejeshaji imehifadhiwa; '
          'usifute app wala data.',
        );
      }
      Database? encrypted;
      try {
        encrypted = await openDatabase(path, password: key, readOnly: true);
        final integrity = await encrypted.rawQuery('PRAGMA quick_check');
        if (integrity.isEmpty || integrity.first.values.first != 'ok') {
          throw DbKeyMissingError(
            'Uhakiki wa database iliyosimbwa umeshindwa. '
            'Nakala ya urejeshaji imehifadhiwa.',
          );
        }
      } catch (error) {
        if (error is DbKeyMissingError) rethrow;
        throw DbKeyMissingError(
          'Database iliyosimbwa haikufunguka kwa ufunguo huu. '
          'Nakala ya urejeshaji imehifadhiwa.',
        );
      } finally {
        await encrypted?.close();
      }
    }

    final hasData = await original.exists() && await original.length() > 0;
    if (!hasData) return _getOrCreateKey();

    if (await isPlainSqlite(path)) {
      final key = await _getOrCreateKey();
      await _migratePlain(path, key, temporary, old);
      return key;
    }

    final key = await keyReader();
    if (!_validKey(key)) {
      throw DbKeyMissingError(
        'Database imesimbwa lakini ufunguo wake haupo au si sahihi kwenye '
        'kifaa hiki. Usifute app wala data. Rejesha backup (.mtbackup) au '
        'wasiliana na msimamizi.',
      );
    }
    return key!;
  }

  static Future<void> verifyAndFinalizeMigration(
    String path,
    Database database,
  ) async {
    final integrity = await database.rawQuery('PRAGMA quick_check');
    final foreignKeyViolations =
        await database.rawQuery('PRAGMA foreign_key_check');
    if (integrity.isEmpty ||
        integrity.first.values.first != 'ok' ||
        foreignKeyViolations.isNotEmpty) {
      throw DbKeyMissingError(
        'Uhakiki wa database baada ya kuifungua umeshindwa. '
        'Nakala za urejeshaji zimehifadhiwa.',
      );
    }
    await _removeDatabaseFiles('$path.plain-old');
    await _removeDatabaseFiles('$path.enc.tmp');
    await _deleteLegacyPlainBackups(path);
  }

  static Future<void> _migratePlain(
    String path,
    String key,
    String temporary,
    String old,
  ) async {
    await _removeDatabaseFiles(temporary);
    final plain = await openDatabase(path);
    try {
      final checkpoint =
          await plain.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      if (checkpoint.isNotEmpty &&
          (checkpoint.first['busy'] as num?)?.toInt() != 0) {
        throw DbKeyMissingError(
          'Database ina WAL ambayo haikuweza kuhifadhiwa salama; '
          'faili la awali limeachwa bila kubadilishwa.',
        );
      }
      final version = await plain.getVersion();
      final objectCount = Sqflite.firstIntValue(
            await plain.rawQuery('SELECT COUNT(*) FROM sqlite_master'),
          ) ??
          0;
      final escapedPath = temporary.replaceAll("'", "''");
      await plain.execute(
        "ATTACH DATABASE '$escapedPath' AS encrypted KEY '$key'",
      );
      await plain.rawQuery("SELECT sqlcipher_export('encrypted')");
      await plain.execute('PRAGMA encrypted.user_version = $version');
      await plain.execute('DETACH DATABASE encrypted');

      final encrypted = await openDatabase(
        temporary,
        password: key,
        readOnly: true,
      );
      try {
        final encryptedVersion = await encrypted.getVersion();
        final encryptedObjectCount = Sqflite.firstIntValue(
              await encrypted.rawQuery('SELECT COUNT(*) FROM sqlite_master'),
            ) ??
            -1;
        final integrity = await encrypted.rawQuery('PRAGMA quick_check');
        final isValid =
            integrity.isNotEmpty && integrity.first.values.first == 'ok';
        if (encryptedVersion != version ||
            encryptedObjectCount != objectCount ||
            !isValid) {
          throw DbKeyMissingError(
            'Uhamishaji wa database kwenda usimbaji haukupita uhakiki; '
            'database ya asili imehifadhiwa.',
          );
        }
      } finally {
        await encrypted.close();
      }
    } catch (_) {
      await _removeDatabaseFiles(temporary);
      rethrow;
    } finally {
      await plain.close();
    }

    await File(path).rename(old);
    await _removeDatabaseSidecars(path);
    try {
      await File(temporary).rename(path);
    } catch (_) {
      if (!await File(path).exists() && await File(old).exists()) {
        await File(old).rename(path);
      }
      rethrow;
    }
  }

  static Future<void> _deleteLegacyPlainBackups(String path) async {
    final directory = File(path).parent;
    final baseName = path.split(Platform.pathSeparator).last;
    await for (final entity in directory.list()) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is File &&
          name.startsWith('$baseName.pre-v') &&
          name.endsWith('.bak') &&
          await isPlainSqlite(entity.path)) {
        await entity.delete();
      }
    }
  }
}
