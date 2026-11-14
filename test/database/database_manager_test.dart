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

    test('reads the columns of a keyword-named table', () async {
      db.execute('CREATE TABLE "order" ("group" INTEGER)');

      expect(await DatabaseManager().getColumns('order'), ['group']);
    });
  });
}
