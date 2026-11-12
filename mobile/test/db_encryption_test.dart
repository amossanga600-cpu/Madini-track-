import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:madini_tracker/db_encryption.dart';

void main() {
  test('ufunguo wa database ni bits 256 za hex na hutofautiana', () {
    final first = DbEncryption.generateKeyHex();
    final second = DbEncryption.generateKeyHex();
    expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(second, isNot(first));
  });

  test('header ya SQLite wazi hutambuliwa', () async {
    final directory = await Directory.systemTemp.createTemp('madini_enc');
    try {
      final plain = File('${directory.path}/plain.db');
      await plain.writeAsBytes([
        ...'SQLite format 3\u0000'.codeUnits,
        ...List<int>.filled(100, 0),
      ]);
      final encrypted = File('${directory.path}/encrypted.db');
      await encrypted.writeAsBytes(
        List<int>.generate(200, (index) => (index * 37 + 11) % 256),
      );

      expect(await DbEncryption.isPlainSqlite(plain.path), isTrue);
      expect(await DbEncryption.isPlainSqlite(encrypted.path), isFalse);
      expect(
        await DbEncryption.isPlainSqlite('${directory.path}/missing.db'),
        isFalse,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('database iliyosimbwa bila ufunguo hukataa kuunda ufunguo mpya',
      () async {
    final directory = await Directory.systemTemp.createTemp('madini_enc');
    final originalReader = DbEncryption.keyReader;
    final originalWriter = DbEncryption.keyWriter;
    var wroteKey = false;
    try {
      DbEncryption.keyReader = () async => null;
      DbEncryption.keyWriter = (_) async {
        wroteKey = true;
      };
      final encrypted = File('${directory.path}/encrypted.db');
      await encrypted.writeAsBytes(
        List<int>.generate(4096, (index) => (index * 31 + 7) % 256),
      );

      await expectLater(
        DbEncryption.prepare(encrypted.path),
        throwsA(isA<DbKeyMissingError>()),
      );
      expect(wroteKey, isFalse);
    } finally {
      DbEncryption.keyReader = originalReader;
      DbEncryption.keyWriter = originalWriter;
      await directory.delete(recursive: true);
    }
  });

  test('ufunguo ulioharibika hauandikwi upya kimyakimya', () async {
    final directory = await Directory.systemTemp.createTemp('madini_enc');
    final originalReader = DbEncryption.keyReader;
    final originalWriter = DbEncryption.keyWriter;
    var wroteKey = false;
    try {
      DbEncryption.keyReader = () async => 'invalid-key';
      DbEncryption.keyWriter = (_) async {
        wroteKey = true;
      };
      final plain = File('${directory.path}/plain.db');
      await plain.writeAsBytes([
        ...'SQLite format 3\u0000'.codeUnits,
        ...List<int>.filled(100, 0),
      ]);

      await expectLater(
        DbEncryption.prepare(plain.path),
        throwsA(isA<DbKeyMissingError>()),
      );
      expect(wroteKey, isFalse);
    } finally {
      DbEncryption.keyReader = originalReader;
      DbEncryption.keyWriter = originalWriter;
      await directory.delete(recursive: true);
    }
  });

  test('nakala wazi ya urejeshaji haifutwi ikiwa ufunguo wa encrypted haupo',
      () async {
    final directory = await Directory.systemTemp.createTemp('madini_enc');
    final originalReader = DbEncryption.keyReader;
    final originalWriter = DbEncryption.keyWriter;
    try {
      DbEncryption.keyReader = () async => null;
      DbEncryption.keyWriter = (_) async {};
      final encrypted = File('${directory.path}/madini_local.db');
      await encrypted.writeAsBytes(
        List<int>.generate(4096, (index) => (index * 17 + 3) % 256),
      );
      final recovery = File('${encrypted.path}.plain-old');
      await recovery.writeAsBytes([
        ...'SQLite format 3\u0000'.codeUnits,
        ...List<int>.filled(100, 0),
      ]);

      await expectLater(
        DbEncryption.prepare(encrypted.path),
        throwsA(isA<DbKeyMissingError>()),
      );
      expect(await recovery.exists(), isTrue);
    } finally {
      DbEncryption.keyReader = originalReader;
      DbEncryption.keyWriter = originalWriter;
      await directory.delete(recursive: true);
    }
  });
}
