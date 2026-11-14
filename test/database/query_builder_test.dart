import 'package:flutter_test/flutter_test.dart';
import 'package:magic_local_storage/magic_local_storage.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('QueryBuilder', () {
    late Database db;

    setUp(() {
      // Use in-memory database for testing
      db = sqlite3.openInMemory();
      DatabaseManager().setConnection(db);

      // Create a test table
      db.execute('''
        CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT,
          age INTEGER,
          is_active INTEGER DEFAULT 1
        )
      ''');

      // Seed data
      db.execute(
        "INSERT INTO users (name, email, age) VALUES ('Alice', 'alice@example.com', 25)",
      );
      db.execute(
        "INSERT INTO users (name, email, age) VALUES ('Bob', 'bob@example.com', 30)",
      );
      db.execute(
        "INSERT INTO users (name, email, age) VALUES ('Charlie', null, 35)",
      );
    });

    tearDown(() {
      DatabaseManager().dispose();
    });

    test('selects all rows', () async {
      final users = await DB.table('users').get();
      expect(users.length, 3);
      expect(users[0]['name'], 'Alice');
    });

    test('selects specific columns', () async {
      final users = await DB.table('users').select(['name']).get();
      expect(users[0].keys, ['name']);
      expect(users[0]['name'], 'Alice');
    });

    test('filters with where clause', () async {
      final users = await DB.table('users').where('age', '>=', 30).get();
      expect(users.length, 2); // Bob and Charlie
      expect(users[0]['name'], 'Bob');
    });

    test('filters with whereNull', () async {
      final users = await DB.table('users').whereNull('email').get();
      expect(users.length, 1);
      expect(users[0]['name'], 'Charlie');
    });

    test('orders results', () async {
      final users = await DB.table('users').orderBy('age', 'desc').get();
      expect(users[0]['name'], 'Charlie');
      expect(users[1]['name'], 'Bob');
      expect(users[2]['name'], 'Alice');
    });

    test('limits results', () async {
      final users = await DB.table('users').limit(1).get();
      expect(users.length, 1);
    });

    test('counts rows', () async {
      final count = await DB.table('users').count();
      expect(count, 3);
    });

    test('checks existence', () async {
      final exists = await DB.table('users').where('name', 'Alice').exists();
      expect(exists, isTrue);

      final notExists = await DB.table('users').where('name', 'Dave').exists();
      expect(notExists, isFalse);
    });

    test('inserts records (schema aware)', () async {
      final id = await DB.table('users').insert({
        'name': 'Dave',
        'email': 'dave@example.com',
        'age': 40,
        'unknown_column': 'should be ignored',
      });

      expect(id, 4);
      final count = await DB.table('users').count();
      expect(count, 4);
    });

    test('updates records', () async {
      final affected = await DB.table('users').where('name', 'Alice').update({
        'age': 26,
      });

      expect(affected, 1);
      final alice = await DB.table('users').where('name', 'Alice').first();
      expect(alice!['age'], 26);
    });

    test('deletes records', () async {
      final affected = await DB.table('users').where('name', 'Bob').delete();
      expect(affected, 1);
      final count = await DB.table('users').count();
      expect(count, 2);
    });

    test('truncates table', () async {
      await DB.table('users').truncate();
      final count = await DB.table('users').count();
      expect(count, 0);
    });

    group('a missing table', () {
      test('insert throws a StateError naming the table', () async {
        await expectLater(
          DB.table('missing_notes').insert({'title': 'Lost'}),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('missing_notes'),
            ),
          ),
        );
      });

      test('update throws a StateError naming the table', () async {
        await expectLater(
          DB.table('missing_notes').where('id', 1).update({'title': 'Lost'}),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('missing_notes'),
            ),
          ),
        );
      });

      test('insert sees a table created after a failed write', () async {
        await expectLater(
          DB.table('late_notes').insert({'title': 'Early'}),
          throwsStateError,
        );

        db.execute('CREATE TABLE late_notes (id INTEGER PRIMARY KEY, title)');

        expect(await DB.table('late_notes').insert({'title': 'Late'}), 1);
      });
    });

    group('keyword identifiers', () {
      setUp(() {
        Schema.create('order', (table) {
          table.id();
          table.integer('order');
          table.string('group');
          table.string('index').nullable();
        });
      });

      test('writes, reads, filters and sorts an order column', () async {
        await DB.table('order').insert({'order': 2, 'group': 'b'});
        await DB.table('order').insert({'order': 1, 'group': 'a'});
        await DB.table('order').insert({'order': 3, 'group': 'a'});

        final sorted = await DB.table('order').orderBy('order', 'desc').get();
        expect(sorted.map((row) => row['order']), [3, 2, 1]);

        final filtered = await DB
            .table('order')
            .where('group', 'a')
            .where('order', '>', 1)
            .get();
        expect(filtered.single['order'], 3);

        expect(
          await DB.table('order').where('group', 'b').update({'index': 'x'}),
          1,
        );
        expect(await DB.table('order').whereNotNull('index').count(), 1);
        expect(await DB.table('order').where('order', 1).delete(), 1);
        await DB.table('order').truncate();
        expect(await DB.table('order').exists(), isFalse);
      });

      test('pluck and value read a keyword column by its bare name', () async {
        await DB.table('order').insert({'order': 2, 'group': 'b'});
        await DB.table('order').insert({'order': 1, 'group': 'a'});

        expect(await DB.table('order').orderBy('order').pluck<int>('order'), [
          1,
          2,
        ]);
        expect(
          await DB.table('order').where('group', 'b').value<int>('order'),
          2,
        );
      });

      test('a hand-quoted name is written as given', () async {
        await DB.table('order').insert({'order': 5, 'group': 'a'});
        await DB.table('order').insert({'order': 4, 'group': 'b'});

        final rows = await DB
            .table('order')
            .where('"group"', 'b')
            .orderBy('"order"')
            .get();

        expect(rows.single['order'], 4);
      });
    });

    group('expressions in column positions', () {
      setUp(() {
        db.execute('''
          CREATE TABLE events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            created_at TEXT,
            data TEXT
          )
        ''');
        db.execute('''
          INSERT INTO events (name, created_at, data) VALUES
            ('beta', '2026-01-01 10:00:00', '{"a": 1}'),
            ('Alpha', '2026-03-01 10:00:00', '{"a": 2}'),
            ('gamma', '2026-05-01 10:00:00', '{"a": 3}')
        ''');
      });

      test('orderBy keeps a COLLATE expression raw', () async {
        final rows = await DB
            .table('events')
            .orderBy('name COLLATE NOCASE')
            .pluck<String>('name');

        expect(rows, ['Alpha', 'beta', 'gamma']);
      });

      test('orderBy keeps a function call raw', () async {
        expect(
          await DB.table('events').orderBy('RANDOM()').get(),
          hasLength(3),
        );
      });

      test('where keeps lower() raw', () async {
        final rows = await DB
            .table('users')
            .where('lower(email)', 'alice@example.com')
            .get();

        expect(rows.single['name'], 'Alice');
      });

      test('where keeps date() raw', () async {
        final count = await DB
            .table('events')
            .where('date(created_at)', '>=', '2026-03-01')
            .count();

        expect(count, 2);
      });

      test('where and pluck keep json_extract raw', () async {
        final rows = await DB
            .table('events')
            .where(r"json_extract(data, '$.a')", '>', 1)
            .orderBy(r"json_extract(data, '$.a')", 'desc')
            .pluck<int>(r"json_extract(data, '$.a')");

        expect(rows, [3, 2]);
      });
    });

    test('a schema-qualified table is read and written', () async {
      db.execute("ATTACH DATABASE ':memory:' AS cache");
      db.execute('CREATE TABLE cache.items (id INTEGER PRIMARY KEY, label)');

      expect(await DatabaseManager().getColumns('cache.items'), [
        'id',
        'label',
      ]);
      await DB.table('cache.items').insert({'label': 'kept'});
      expect(await DB.table('cache.items').pluck<String>('label'), ['kept']);
    });

    test('a table-qualified column still addresses the column', () async {
      final rows = await DB
          .table('users')
          .where('users.age', '>=', 30)
          .orderBy('users.age', 'desc')
          .get();

      expect(rows.map((row) => row['name']), ['Charlie', 'Bob']);
    });

    group('where operators', () {
      test('accepts every supported operator, case-insensitively', () async {
        // Ages are 25, 30 and 35; names Alice, Bob and Charlie.
        final List<(String, String, Object, int)> cases = [
          ('age', '=', 30, 1),
          ('age', '==', 30, 1),
          ('name', 'glob', 'B*', 1),
          ('name', 'NOT GLOB', 'B*', 2),
          ('age', '!=', 30, 2),
          ('age', '<>', 30, 2),
          ('age', '<', 30, 1),
          ('age', '<=', 30, 2),
          ('age', '>', 30, 1),
          ('age', '>=', 30, 2),
          ('age', 'is', 30, 1),
          ('age', 'Is Not', 30, 2),
          ('name', 'like', 'B%', 1),
          ('name', 'NOT LIKE', 'B%', 2),
        ];

        for (final (column, operator, value, expected) in cases) {
          final int count = await DB
              .table('users')
              .where(column, operator, value)
              .count();
          expect(count, expected, reason: 'operator $operator');
        }
      });

      test('match searches an FTS5 table', () async {
        db.execute('CREATE VIRTUAL TABLE notes USING fts5(body)');
        db.execute(
          "INSERT INTO notes (body) VALUES ('buy milk'), ('walk the dog')",
        );

        final rows = await DB
            .table('notes')
            .where('notes', 'MATCH', 'milk')
            .get();

        expect(rows.single['body'], 'buy milk');
      });

      test('rejects an unsupported operator with an ArgumentError', () {
        for (final String operator in <String>[
          '= 1 OR 1 = 1 --',
          'in',
          'not in',
          ';',
          '',
        ]) {
          expect(
            () => DB.table('users').where('age', operator, 30),
            throwsArgumentError,
            reason: 'operator "$operator"',
          );
        }
      });
    });

    group('orderBy direction', () {
      test('accepts asc and desc in any case', () async {
        final asc = await DB.table('users').orderBy('age', 'ASC').get();
        expect(asc.first['name'], 'Alice');

        final desc = await DB.table('users').orderBy('age', 'Desc').get();
        expect(desc.first['name'], 'Charlie');
      });

      test('rejects any other direction with an ArgumentError', () {
        for (final String direction in <String>[
          'desc; DROP TABLE users',
          'sideways',
          '',
        ]) {
          expect(
            () => DB.table('users').orderBy('age', direction),
            throwsArgumentError,
            reason: 'direction "$direction"',
          );
        }
      });
    });

    group('a null value', () {
      test('where with = and null matches IS NULL', () async {
        final rows = await DB.table('users').where('email', '=', null).get();
        expect(rows.single['name'], 'Charlie');
      });

      test('where with two arguments and null matches IS NULL', () async {
        final rows = await DB.table('users').where('email', null).get();
        expect(rows.single['name'], 'Charlie');
      });

      test('where with is and null matches IS NULL', () async {
        expect(await DB.table('users').where('email', 'is', null).count(), 1);
      });

      test('where with != or is not and null matches IS NOT NULL', () async {
        for (final String operator in <String>['!=', '<>', 'is not']) {
          expect(
            await DB.table('users').where('email', operator, null).count(),
            2,
            reason: 'operator $operator',
          );
        }
      });

      test('where with an ordering operator and null throws', () {
        expect(
          () => DB.table('users').where('age', '>', null),
          throwsArgumentError,
        );
      });
    });
  });
}
