import 'package:flutter_test/flutter_test.dart';
import 'package:magic_local_storage/magic_local_storage.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('Schema', () {
    late Database db;

    setUp(() {
      db = sqlite3.openInMemory();
      DatabaseManager().setConnection(db);
    });

    tearDown(() {
      DatabaseManager().dispose();
    });

    test('creates table with columns', () async {
      Schema.create('products', (table) {
        table.id();
        table.string('name');
        table.integer('price');
        table.timestamps();
      });

      // Verify via sqlite
      final result = db.select("PRAGMA table_info(products)");
      final columns = result.map((row) => row['name']).toList();

      expect(
        columns,
        containsAll(['id', 'name', 'price', 'created_at', 'updated_at']),
      );
    });

    test('drops table', () async {
      db.execute('CREATE TABLE temp (id INTEGER)');

      Schema.drop('temp');

      // Verify table is gone
      // Catch error or check tables list
      try {
        db.select('SELECT * FROM temp');
        fail('Table should have been dropped');
      } catch (e) {
        // Expected
      }
    });

    test('drops table if exists', () async {
      Schema.dropIfExists('non_existent');
      // Should not throw
    });

    test('checks if table has column', () async {
      db.execute('CREATE TABLE users (id INTEGER, name TEXT)');

      expect(await Schema.hasColumn('users', 'name'), isTrue);
      expect(await Schema.hasColumn('users', 'email'), isFalse);
    });

    test('creates, alters and drops keyword-named tables and columns', () {
      Schema.create('order', (table) {
        table.id();
        table.integer('group');
        table.string('index').defaultValue("Ada's");
      });

      db.execute('INSERT INTO "order" ("group") VALUES (7)');
      expect(db.select('SELECT "index" FROM "order"').first['index'], "Ada's");

      Schema.table('order', (table) {
        table.string('select').nullable();
        table.renameColumn('group', 'where');
        table.dropColumn('index');
      });
      final columns = db
          .select('PRAGMA table_info("order")')
          .map((row) => row['name'])
          .toList();
      expect(columns, ['id', 'where', 'select']);

      Schema.rename('order', 'table');
      expect(db.select('SELECT "where" FROM "table"').first['where'], 7);

      Schema.drop('table');
      Schema.dropIfExists('table');
      expect(
        db.select("SELECT name FROM sqlite_master WHERE type = 'table'"),
        isNot(contains(containsPair('name', 'table'))),
      );
    });

    test('checks if table has table', () async {
      db.execute('CREATE TABLE users (id INTEGER, name TEXT)');

      expect(await Schema.hasTable('users'), isTrue);
      expect(await Schema.hasTable('non_existent'), isFalse);
    });
  });
}
