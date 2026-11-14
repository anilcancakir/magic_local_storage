import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_local_storage/src/database/connectors/connection_factory_io.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  late Directory documents;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('connection_factory_io_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => documents.path);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    documents.deleteSync(recursive: true);
  });

  test('opens the database file in the documents directory', () async {
    final Database db = await ConnectionFactory().connect({
      'database': 'probe.db',
    });
    addTearDown(db.close);

    expect(File('${documents.path}/probe.db').existsSync(), isTrue);
  });

  test('a mistyped quoted column raises no such column', () async {
    final Database db = await ConnectionFactory().connect({
      'database': 'probe.db',
    });
    addTearDown(db.close);
    db.execute('CREATE TABLE t (a INTEGER)');
    db.execute('INSERT INTO t VALUES (1)');

    expect(
      () => db.select('SELECT * FROM t WHERE "nope" = ?', ['nope']),
      throwsA(
        isA<SqliteException>().having(
          (e) => e.message,
          'message',
          contains('no such column'),
        ),
      ),
    );
  });
}
