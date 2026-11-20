<p align="center">
  <img src="https://raw.githubusercontent.com/anilcancakir/magic_local_storage/master/screenshots/logo.png" width="120" alt="Magic Local Storage logo" />
</p>

<h1 align="center">Magic Local Storage</h1>

<p align="center">
  <strong>SQLite for Magic apps, the Laravel way.</strong><br/>
  The <code>DB</code> and <code>Schema</code> facades, migrations, seeders, factories and a push-then-pull sync skeleton on one local SQLite connection, with the storage behind every <code>useLocal</code> model. Native through FFI, web through <code>sqlite3.wasm</code>.
</p>

<p align="center">
  <a href="https://pub.dev/packages/magic_local_storage"><img src="https://img.shields.io/pub/v/magic_local_storage.svg" alt="pub package"></a>
  <a href="https://github.com/anilcancakir/magic_local_storage/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/magic_local_storage/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://codecov.io/gh/anilcancakir/magic_local_storage"><img src="https://codecov.io/gh/anilcancakir/magic_local_storage/graph/badge.svg" alt="codecov"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/magic_local_storage/score"><img src="https://img.shields.io/pub/points/magic_local_storage" alt="pub points"></a>
</p>

<p align="center">
  <a href="https://anilcancakir.com/magic/docs/local_storage">Documentation</a> ·
  <a href="https://pub.dev/packages/magic_local_storage">pub.dev</a> ·
  <a href="https://github.com/anilcancakir/magic_local_storage/issues">Issues</a>
</p>

## At a glance

| Fact | Value |
|---|---|
| Package | [`magic_local_storage`](https://pub.dev/packages/magic_local_storage) |
| Install | `flutter pub add magic_local_storage`, then `dart run magic:dowel plugin:install magic_local_storage` |
| Import | `package:magic_local_storage/magic_local_storage.dart` |
| Entry points | `DB` and `Schema` (facades), `DatabaseServiceProvider` (wiring), `databaseConfig` (config factory), `Migration` and `Migrator`, `Seeder`, `Factory` and `Seeding.run`, `SyncFeed` and `SyncLedger`, `QueryModelStore` |
| Generators | `make:migration`, `make:seeder`, `make:factory`, `local_storage:install` |
| Platforms | Android, iOS, macOS, Windows, Linux and web |
| Requires | Dart >=3.13, Flutter >=3.47, `magic` ^1.0.0; web needs `web/sqlite3.wasm`, which the installer downloads |
| Dependencies | `magic`, `sqlite3`, `path_provider`, `path`, `faker`; dowel runs the installer |
| License | MIT |

## Install

```bash
flutter pub add magic_local_storage
dart run magic:dowel plugin:install magic_local_storage
```

The installer adds `DatabaseServiceProvider` to the `providers` list of `lib/config/app.dart` and `() => databaseConfig` to the `configFactories` of `lib/main.dart`, then chains `local_storage:install`, which downloads `web/sqlite3.wasm` (the release of the `sqlite3` version your project resolved) when the project has a `web/` folder. No config file is published.

Core `magic` 1.0.0 no longer carries SQLite. A model with `useLocal => true` needs this package: without it the first `find`, `all`, `save`, `delete` or `refresh` throws a `StateError` naming `magic_local_storage`.

## Schema and migrations

Define tables with `Migration` classes and run them after `Magic.init`.

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

class CreatePostsTable extends Migration {
  @override
  String get name => '20261114120000_create_posts_table';

  @override
  void up() {
    Schema.create('posts', (Blueprint table) {
      table.id();
      table.string('title');
      table.boolean('is_published').defaultValue(false);
      table.timestamps();
    });
  }

  @override
  void down() {
    Schema.dropIfExists('posts');
  }
}

Future<void> main() async {
  await Migrator().run([CreatePostsTable()]);
}
```

`run` applies every pending migration in one `SAVEPOINT`: if one throws, none is recorded and the next launch retries from a clean schema. `up()` and `down()` are synchronous; `void up() async` compiles and silently breaks the ledger.

## DB

Query with the fluent builder or raw SQL.

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> main() async {
  final int id = await DB.table('posts').insert({'title': 'Hello'});

  final List<Map<String, dynamic>> published = await DB.table('posts')
      .where('is_published', true)
      .orderBy('id', 'desc')
      .limit(10)
      .get();

  await DB.transaction(() async {
    await DB.table('posts').where('id', id).update({'title': 'Hello again'});
  });

  print(published.length);
}
```

| Member | Meaning |
|--------|---------|
| `DB.table(name)` | A `QueryBuilder`: `where`, `whereNull`, `orderBy`, `limit`, `get`, `first`, `count`, `exists`, `insert`, `update`, `delete`. |
| `DB.select(sql, params)`, `DB.insert`, `DB.update`, `DB.delete`, `DB.statement` | Synchronous raw SQL with `?` placeholders. |
| `DB.transaction(callback)` | One transaction; rolls back when the callback throws. |
| `Schema.create`, `Schema.table`, `Schema.drop`, `Schema.dropIfExists`, `Schema.rename` | Table changes. |

Writes keep only the keys the table has a column for, so a stray attribute never fails an insert; a write to a table that does not exist yet throws a `StateError` naming it. Plain table and column names are quoted, so a column called `order` works; an expression such as `lower(email)` or `name COLLATE NOCASE` is written as given, and `select([...])` entries stay raw SQL.

## Models

A `useLocal` model persists through the `LocalModelStore` this package binds at `local_model_store`.

```dart
import 'package:magic/magic.dart';

class Post extends Model with HasTimestamps, InteractsWithPersistence {
  @override
  String get table => 'posts';

  @override
  String get resource => 'posts';

  @override
  List<String> get fillable => ['title'];

  @override
  bool get useLocal => true;

  @override
  bool get useRemote => false;

  static Future<List<Post>> all() => InteractsWithPersistence.allModels<Post>(Post.new);
}

Future<void> main() async {
  await (Post()..fill({'title': 'Hello'})).save();

  print((await Post.all()).length);
}
```

`Post().query()` returns a `QueryBuilder` over the model's table. Any class that implements core's `LocalModelStore` can replace `QueryModelStore` at the same container key.

## Seeders and factories

```dart
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

class Post extends Model with InteractsWithPersistence {
  @override
  String get table => 'posts';

  @override
  String get resource => 'posts';

  @override
  List<String> get fillable => ['title'];

  @override
  bool get useLocal => true;

  @override
  bool get useRemote => false;
}

class PostFactory extends Factory<Post> {
  @override
  Factory<Post> newFactory() => PostFactory();

  @override
  Post newInstance() => Post();

  @override
  Map<String, dynamic> definition() => {'title': faker.lorem.sentence()};
}

class PostSeeder extends Seeder {
  @override
  Future<void> run() async {
    await PostFactory().count(10).create();
  }
}

Future<void> main() async {
  await Seeding.run([PostSeeder()]);
}
```

`Seeding.run(List<Seeder>)` replaces core's removed `Magic.seed`.

## Generators

| Command | Writes |
|---------|--------|
| `dart run magic:dowel make:migration create_posts_table --create=posts` | `lib/database/migrations/m_<timestamp>_create_posts_table.dart` |
| `dart run magic:dowel make:seeder Post` | `lib/database/seeders/post_seeder.dart` |
| `dart run magic:dowel make:factory Post` | `lib/database/factories/post_factory.dart` |
| `dart run magic:dowel local_storage:install` | The provider, the config factory and `web/sqlite3.wasm` |

Core's `make:model -m -f -s` and `make:resource` find these in the dowel registry and print a hint naming this package when it is absent.

## Sync

`SyncFeed` is a push-then-pull loop over one resource: `POST <resource>/sync` with the rows written since the last push, then `GET <resource>` pages with an opaque server cursor. `SyncLedger` keeps both bookmarks in the `sync_cursors` table that `CreateSyncCursorsTable` creates. `run` never throws; read `SyncReport.failure`. See the sync guide for the two-clock rule.

## Testing

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
    expect(DB.select('SELECT 1 AS one').single['one'], 1);
  });
}
```

Add `sqlite3` as a dev dependency to open the in-memory connection. `DatabaseManager` is a singleton that `Magic.flush()` does not clear, so dispose it in `tearDown`.

## For AI coding agents

Rules for an agent writing code against this package. Each one is a mistake that costs a user a crash or a silent no-op.

| Do | Because |
|----|---------|
| Import `package:magic_local_storage/magic_local_storage.dart` only | Everything under `src/` is private; `cli.dart` is for the dowel dispatcher. |
| Register `DatabaseServiceProvider` in `providers` and `() => databaseConfig` in `configFactories` | Neither is automatic; without the provider no `local_model_store` is bound. |
| Install the package before setting `useLocal => true` | Core's `InteractsWithPersistence` throws a `StateError` on every persistence leg when no store is bound. |
| Keep `Migration.up()` and `down()` synchronous | `void up() async` compiles, and `run` records the migration at its first suspension. |
| Never call `DB.commit()` or `DB.rollback()` in a migration or inside `DB.transaction` | The run or the block owns the transaction; `run` and `transaction` throw a `StateError` naming the mistake. |
| Pass every migration to `Migrator().run`, in order | There is no discovery, so an unlisted migration never runs. |
| Call `Seeding.run([...])` for seeders | `Magic.seed` is gone from core. |
| Prefer `whereNull` and `whereNotNull` for null checks | `where(column, null)` also compiles to `IS NULL`, but `where(column, '>', null)` throws an `ArgumentError`. |
| Never put user input in a table, column, `select` entry, operator or order direction | Only values are bound. Plain names are quoted but still choose what is read; any other column text and every `select` entry is raw SQL; an operator outside `=`, `==`, `!=`, `<>`, `<`, `<=`, `>`, `>=`, `like`, `not like`, `glob`, `not glob`, `match`, `is`, `is not`, or a direction other than `asc`/`desc`, throws an `ArgumentError`. |
| Set a new connection in `setUp` and call `DatabaseManager().dispose()` in `tearDown` | The manager is a singleton that `Magic.flush()` does not clear. |

## Dependencies

`magic` for the container, `Config`, `Log`, `Http` and the model layer; `sqlite3` for the engine (FFI on native, `sqlite3.wasm` on web); `path_provider` and `path` for the native file location; `faker` for factories; dowel to run the installer through `dart run magic:dowel`.

## Links

- [Documentation](https://anilcancakir.com/magic/docs/local_storage/getting-started/installation): installation, configuration, queries, migrations, models, seeding, sync, testing and generators
- [API reference](https://pub.dev/documentation/magic_local_storage/latest/)
- [llms.txt](llms.txt) and the [agent skill](skills/magic-local-storage/SKILL.md) for AI coding agents: `npx skills add anilcancakir/magic_local_storage`
- [Changelog](CHANGELOG.md)
- [Report an issue](https://github.com/anilcancakir/magic_local_storage/issues)
- [Security policy](SECURITY.md)

## License

MIT, see [LICENSE](LICENSE). Built by [Anılcan Çakır](https://anilcancakir.com).
