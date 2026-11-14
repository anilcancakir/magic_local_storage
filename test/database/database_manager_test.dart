import 'package:flutter_test/flutter_test.dart';
import 'package:magic_local_storage/magic_local_storage.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('DatabaseManager.getColumns', () {
    late Database db;

    setUp(() {
      db = sqlite3.openInMemory();
      DatabaseManager().setConnection(db);
    });

    tearDown(() {
      DatabaseManager().dispose();
    });

    test('does not cache the empty list of a missing table', () async {
      expect(await DatabaseManager().getColumns('later'), isEmpty);

      db.execute('CREATE TABLE later (id INTEGER, title TEXT)');

      expect(await DatabaseManager().getColumns('later'), ['id', 'title']);
    });

    test('a schema change reaches the schema-qualified cache entry', () async {
      db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY)');
      expect(await DatabaseManager().getColumns('main.users'), ['id']);

      Schema.table('users', (table) {
        table.string('name').nullable();
      });
      await DB.table('main.users').insert({'name': 'Ada'});

      expect(db.select('SELECT name FROM users').single['name'], 'Ada');
    });

    test('clearing a qualified name clears the plain entry too', () async {
      db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY)');
      expect(await DatabaseManager().getColumns('users'), ['id']);

      db.execute('ALTER TABLE users ADD COLUMN name TEXT');
      DatabaseManager().clearSchemaCache('main.users');

      expect(await DatabaseManager().getColumns('users'), ['id', 'name']);
    });

    test('reads the columns of a keyword-named table', () async {
      db.execute('CREATE TABLE "order" ("group" INTEGER)');

      expect(await DatabaseManager().getColumns('order'), ['group']);
    });
  });
}
