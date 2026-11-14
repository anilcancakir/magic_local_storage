# Migrations

Define and change SQLite tables with `Migration` classes, the `Schema` facade and a `Blueprint`, and apply them with the `Migrator`.

- [Basic Usage](#basic-usage)
- [Quick Reference](#quick-reference)
- [Generating a Migration](#generating-a-migration)
- [Running Migrations](#running-migrations)
- [The Run Is Atomic](#the-run-is-atomic)
- [Synchronous up and down](#synchronous-up-and-down)
- [Creating Tables](#creating-tables)
- [Modifying and Dropping Tables](#modifying-and-dropping-tables)
- [Checking the Schema](#checking-the-schema)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="basic-usage"></a>
## Basic Usage

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
      table.text('body').nullable();
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
  // After Magic.init(...) has booted DatabaseServiceProvider.
  final List<String> ran = await Migrator().run([CreatePostsTable()]);

  print('Ran ${ran.length} migration(s)');
}
```

<a name="quick-reference"></a>
## Quick Reference

| Call | Returns | Meaning |
|:-----|:--------|:--------|
| `Migrator().run(migrations)` | `Future<List<String>>` | Applies every pending migration as one batch; returns the names it ran. |
| `Migrator().rollback(migrations)` | `Future<List<String>>` | Reverses the last batch, newest first. |
| `Migrator().reset(migrations)` | `Future<List<String>>` | Reverses every applied migration. |
| `Migrator().refresh(migrations)` | `Future<void>` | `reset` then `run`. |
| `Migrator().getExecuted()` | `Future<List<String>>` | Applied names in order. |
| `Migrator().getPending(migrations)` | `Future<List<String>>` | Names not applied yet. |

The ledger is the `magic_migrations` table, with one row per migration and its batch number. `name` is the ledger key, so it must be unique and must never change once released.

<a name="generating-a-migration"></a>
## Generating a Migration

```bash
dart run magic:dowel make:migration create_posts_table --create=posts
dart run magic:dowel make:migration add_slug_to_posts --table=posts
```

This writes `lib/database/migrations/m_<YYYYMMDDHHMMSS>_<snake_name>.dart` holding a PascalCase class with `up` and `down`. `--create=<table>` selects the stub with a `Schema.create` body; without it (or with `--table`) you get a skeleton with an empty `up()` and a `down()` that throws `UnsupportedError` until you write the rollback. The command lives in this package, see [Generators](../guides/generators.md).

<a name="running-migrations"></a>
## Running Migrations

Magic has no migration discovery: list every migration in order. Run them after `Magic.init`, once the provider has opened the connection:

```dart
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

class CreateUsersTable extends Migration {
  @override
  String get name => '20261114120000_create_users_table';

  @override
  void up() => Schema.create('users', (Blueprint table) => table.id());

  @override
  void down() => Schema.dropIfExists('users');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    configFactories: [() => databaseConfig],
    configs: [
      {
        'app': {
          'providers': [(app) => DatabaseServiceProvider(app)],
        },
      },
    ],
  );

  final List<String> ran = await Migrator().run([
    CreateUsersTable(),
    CreateSyncCursorsTable(), // from this package, only when you use SyncFeed
  ]);

  if (ran.isNotEmpty) {
    Log.info('Ran ${ran.length} migration(s)');
  }
}
```

`run` skips names already in the ledger, so calling it on every launch is safe.

<a name="the-run-is-atomic"></a>
## The Run Is Atomic

Every pending migration of one `run()` is applied inside a single `SAVEPOINT`. If one throws, all of them roll back and the ledger records none, so the next launch retries from a clean schema instead of meeting half-applied work. That matters most when you migrate before `runApp`, where there is no screen to report a failure on.

A savepoint rather than `BEGIN` lets it nest inside a transaction you opened yourself:

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> main() async {
  final List<Migration> migrations = [];

  await Migrator().run(migrations); // the migrator's savepoint alone
  await DB.transaction(() => Migrator().run(migrations)); // nested in yours
}
```

A migration must not call `DB.beginTransaction`, `DB.commit` or `DB.rollback`. The run is already one unit; a commit inside `up()` closes the migrator's savepoint, and `run()` throws a `StateError` naming the migration. That is the one case that cannot be undone, because the earlier statements are committed by the time it is detected.

<a name="synchronous-up-and-down"></a>
## Synchronous up and down

`up()` and `down()` return `void`. Writing `void up() async` compiles and is a silent defect: `run` cannot await a `void`, so an async body is recorded as complete at its first suspension.

Inside a migration use the synchronous API: `Schema.create`, `Schema.table`, `Schema.drop`, `Schema.dropIfExists`, `Schema.rename`, `DB.statement` and `DB.select`. The introspection helpers return futures and do not belong there: `Schema.hasTable`, `Schema.hasColumn`, `Schema.getColumns`, `DatabaseManager.getColumns` and `hasColumn`. To sense a column synchronously, read the pragma:

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

class AddAvatarToUsers extends Migration {
  @override
  String get name => '20261115090000_add_avatar_to_users';

  @override
  void up() {
    final bool present = DB.select('PRAGMA table_info(users)').any((Map<String, dynamic> row) => row['name'] == 'avatar');

    if (!present) {
      DB.statement("ALTER TABLE users ADD COLUMN avatar TEXT NOT NULL DEFAULT ''");
    }
  }

  @override
  void down() {
    throw UnsupportedError('Dropping the avatar column loses data.');
  }
}
```

A migration with no honest rollback throws `UnsupportedError` from `down()`; doing nothing would let `rollback` delete the ledger row of a migration that is still applied.

<a name="creating-tables"></a>
## Creating Tables

`Schema.create(table, callback)` builds a `Blueprint` and runs `CREATE TABLE IF NOT EXISTS`.

| Method | SQLite type | Notes |
|:-------|:------------|:------|
| `id([name])` | `INTEGER PRIMARY KEY AUTOINCREMENT` | Named `id` by default. |
| `string(name)` | `TEXT` | A length argument is accepted and ignored. |
| `text(name)` | `TEXT` | Long text. |
| `integer(name)`, `bigInteger(name)` | `INTEGER` | Identical in SQLite. |
| `boolean(name)` | `INTEGER` | `0` or `1`. |
| `real(name)` | `REAL` | Floating point. |
| `blob(name)` | `BLOB` | Binary data. |
| `timestamps()` | `TEXT` x 2 | Nullable `created_at` and `updated_at`. |

Every column is `NOT NULL` unless you chain a modifier:

| Modifier | Effect |
|:---------|:-------|
| `nullable()` | Allows `NULL`. |
| `unique()` | Adds `UNIQUE`. |
| `defaultValue(value)` | Adds `DEFAULT`; a `bool` becomes `1` or `0`. |

<a name="modifying-and-dropping-tables"></a>
## Modifying and Dropping Tables

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

void main() {
  Schema.table('users', (Blueprint table) {
    table.string('phone').nullable();
    table.renameColumn('name', 'full_name');
    table.dropColumn('legacy_field');
  });

  Schema.rename('posts', 'articles');
  Schema.dropIfExists('temporary_data');
  Schema.drop('old_table'); // throws when the table is absent
}
```

`Schema.table` adds columns first, then renames, then drops. A column added to an existing table must be `nullable()` or carry a `defaultValue`, because SQLite refuses to add a `NOT NULL` column with no default. Renaming a column needs SQLite 3.25 and dropping one needs 3.35. SQLite cannot change a column type: add a new column, copy with `DB.statement('UPDATE users SET name_new = name')`, then drop the old one.

<a name="checking-the-schema"></a>
## Checking the Schema

Outside migrations, the introspection helpers answer futures:

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> main() async {
  if (await Schema.hasTable('users')) {
    print(await Schema.getColumns('users')); // [id, name, email, created_at, updated_at]
    print(await Schema.hasColumn('users', 'avatar'));
  }
}
```

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| `void up() async` | Keep `up` and `down` synchronous; use `DB.statement`, not awaited helpers. |
| Awaiting `Schema.hasTable` inside `up()` | Read `sqlite_master` or `PRAGMA table_info` with `DB.select`. |
| Renaming a released migration's `name` | The ledger key changes and the migration runs again. Keep the name for good. |
| Adding a `NOT NULL` column with no default | Chain `nullable()` or `defaultValue(...)`. |
| Calling `DB.commit()` in `up()` | Remove it; `run` throws a `StateError` naming the migration. |
| Expecting migrations to be found by file name | Pass every migration to `Migrator().run`, in order. |
| A `down()` that does nothing | Throw `UnsupportedError`, or `rollback` forgets a migration that is still applied. |

<a name="related-documentation"></a>
## Related Documentation

- [Queries](./queries.md): `DB.statement` and `DB.select`.
- [Models](./models.md): the model that persists to the table.
- [Generators](../guides/generators.md): `make:migration`.
- [Sync](../guides/sync.md): `CreateSyncCursorsTable`.
- [Testing](../guides/testing.md): running migrations in a test.
