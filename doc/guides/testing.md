# Testing

Test code that persists to SQLite against an in-memory database per test, run migrations and factories in it, assert with `DB`, and fake the store when a test needs no database at all.

- [In-Memory Database](#in-memory-database)
- [Running Migrations](#running-migrations)
- [Models and Factories](#models-and-factories)
- [Database Assertions](#database-assertions)
- [Faking the Store](#faking-the-store)
- [Testing a Feed](#testing-a-feed)
- [Resetting Static State](#resetting-static-state)
- [Related Documentation](#related-documentation)

<a name="in-memory-database"></a>
## In-Memory Database

A `useLocal` model resolves a store before every local leg, so each test binds one: the plugin's `QueryModelStore` over an in-memory SQLite connection. Add the `sqlite3` package as a dev dependency to open the connection:

```bash
flutter pub add --dev sqlite3
```

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  setUp(() {
    MagicApp.reset();
    Magic.flush();

    DatabaseManager().setConnection(sqlite3.openInMemory());
    MagicApp.instance.singleton('local_model_store', () => QueryModelStore());
  });

  tearDown(() {
    DatabaseManager().dispose();
  });

  test('the connection is open', () {
    expect(DatabaseManager().isInitialized, isTrue);
    expect(DB.select('SELECT 1 AS one').single['one'], 1);
  });
}
```

`DatabaseServiceProvider(MagicApp.instance).register()` binds `db` and `local_model_store` together if you prefer it to the manual line; do not call its `boot()`, which opens the file database. The name `:memory:` does not work as the `database` config value on native platforms, because the factory joins it onto the documents directory.

`DatabaseManager` is a singleton that `Magic.flush()` does not touch: set a connection in `setUp` and call `dispose()` in `tearDown`, so no test sees another test's tables.

<a name="running-migrations"></a>
## Running Migrations

A fresh connection has no tables, so run the migrations the test needs. The ledger lives in the same connection, which makes every test start from a clean slate.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';
import 'package:sqlite3/sqlite3.dart';

class CreateItemsTable extends Migration {
  @override
  String get name => '20261114120000_create_items_table';

  @override
  void up() {
    Schema.create('items', (Blueprint table) {
      table.id();
      table.string('name');
    });
  }

  @override
  void down() {
    Schema.dropIfExists('items');
  }
}

void main() {
  setUp(() async {
    MagicApp.reset();
    Magic.flush();

    DatabaseManager().setConnection(sqlite3.openInMemory());
    await Migrator().run([CreateItemsTable()]);
  });

  tearDown(() {
    DatabaseManager().dispose();
  });

  test('the table exists', () async {
    expect(await Schema.hasTable('items'), isTrue);
    expect(await Migrator().getPending([CreateItemsTable()]), isEmpty);
  });
}
```

<a name="models-and-factories"></a>
## Models and Factories

With the store bound and the tables created, a model and a factory behave as in the app:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';
import 'package:sqlite3/sqlite3.dart';

class Item extends Model with InteractsWithPersistence {
  @override
  String get table => 'items';

  @override
  String get resource => 'items';

  @override
  List<String> get fillable => ['name'];

  @override
  bool get useLocal => true;

  @override
  bool get useRemote => false;

  String? get name => getAttribute('name') as String?;

  static Future<Item?> find(dynamic id) => InteractsWithPersistence.findById<Item>(id, Item.new);
}

class ItemFactory extends Factory<Item> {
  @override
  Factory<Item> newFactory() => ItemFactory();

  @override
  Item newInstance() => Item();

  @override
  Map<String, dynamic> definition() => {'name': faker.lorem.word()};
}

void main() {
  setUp(() {
    MagicApp.reset();
    Magic.flush();

    final db = sqlite3.openInMemory()..execute('CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');
    DatabaseManager().setConnection(db);
    MagicApp.instance.singleton('local_model_store', () => QueryModelStore());
  });

  tearDown(() {
    DatabaseManager().dispose();
  });

  test('a factory creates and a model finds', () async {
    final Item created = (await ItemFactory().state({'name': 'Anvil'}).create()).first;

    final Item? found = await Item.find(created.id);

    expect(found?.name, 'Anvil');
  });

  test('a model without a bound store fails loudly', () async {
    MagicApp.reset();
    Magic.flush();

    await expectLater(Item.find(1), throwsStateError);
  });
}
```

A seeder run goes through `Log`, so call `Log.fake()` in that test's `setUp`.

<a name="database-assertions"></a>
## Database Assertions

Assert against the table with `DB.table`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

import 'package:sqlite3/sqlite3.dart';

void main() {
  setUp(() {
    DatabaseManager().setConnection(sqlite3.openInMemory());
    DB.statement('CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');
  });

  tearDown(() {
    DatabaseManager().dispose();
  });

  test('rows reach the table', () async {
    await DB.table('items').insertAll([
      {'name': 'Anvil'},
      {'name': 'Bolt'},
    ]);

    expect(await DB.table('items').count(), 2);
    expect(await DB.table('items').where('name', 'Anvil').exists(), isTrue);

    final Map<String, dynamic>? row = await DB.table('items').where('id', 1).first();
    expect(row?['name'], 'Anvil');
  });
}
```

<a name="faking-the-store"></a>
## Faking the Store

A test for code that only needs a `useLocal` model to save, and not a SQL engine, binds a fake `LocalModelStore`. Implement the contract, see the sample under [Custom Stores](../basics/models.md#custom-stores), and bind it:

```dart
import 'package:magic/magic.dart';

void bindFake(LocalModelStore store) {
  MagicApp.instance.singleton('local_model_store', () => store);
}
```

There is no mocking library: implement the abstract class, as with every Magic contract.

<a name="testing-a-feed"></a>
## Testing a Feed

A `SyncFeed` talks to `Http` and to the ledger. Fake the network with `Http.fake`, create the `sync_cursors` table with `CreateSyncCursorsTable`, run the feed and read the bookmarks back:

```dart
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> checkSync(SyncFeed feed) async {
  Http.fake((MagicRequest request) {
    return Http.response({'data': <Object?>[], 'has_more': false}, 200);
  });

  await Migrator().run([CreateSyncCursorsTable()]);

  final SyncReport report = await feed.run(scope: 'team-1', account: 'user-1');
  final SyncBookmarks bookmarks = const SyncLedger().read(scope: 'team-1', feed: 'items');

  print('${report.complete} ${bookmarks.pushMark}');

  Http.unfake();
}
```

<a name="resetting-static-state"></a>
## Resetting Static State

`Magic.flush()` and `MagicApp.reset()` clear the container, not the statics this package keeps. Reset them yourself.

| State | Reset |
|:------|:------|
| The `DatabaseManager` connection and schema cache | `DatabaseManager().dispose()` in `tearDown`; set a new connection in `setUp`. |
| A faked network | `Http.unfake()` after `Http.fake`. |
| The faked log | `Log.fake()` again in `setUp`; the container reset drops it. |

Call `MagicApp.reset()` and `Magic.flush()` in every `setUp`, before you bind a store: the reset also clears the binding.

<a name="related-documentation"></a>
## Related Documentation

- [Models](../basics/models.md): the store contract and the `StateError`.
- [Migrations](../basics/migrations.md): the migrations a test runs.
- [Seeding](../basics/seeding.md): factories and seeders.
- [Sync](./sync.md): the feed under test.
