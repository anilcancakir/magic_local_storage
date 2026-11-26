import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_local_storage/src/database/connectors/connection_factory_io.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  late Directory documents;
  late Directory cache;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('connection_factory_io_');
    cache = Directory.systemTemp.createTempSync('connection_factory_cache_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'getApplicationDocumentsDirectory' => documents.path,
            'getApplicationCacheDirectory' => cache.path,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    MagicPlatform.debugTvOSOverride = null;
    documents.deleteSync(recursive: true);
    cache.deleteSync(recursive: true);
  });

  test('opens the database file in the documents directory', () async {
    final Database db = await ConnectionFactory().connect({
      'database': 'probe.db',
    });
    addTearDown(db.close);

    expect(File('${documents.path}/probe.db').existsSync(), isTrue);
  });

  test('on tvOS opens the database file under the cache directory', () async {
    MagicPlatform.debugTvOSOverride = true;

    final Database db = await ConnectionFactory().connect({
      'database': 'probe.db',
    });
    addTearDown(db.close);

    expect(File('${cache.path}/app_data/probe.db').existsSync(), isTrue);
    expect(File('${documents.path}/probe.db').existsSync(), isFalse);
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
