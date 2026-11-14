# Configuration

Choose the database file with the `database` config, and learn how `DatabaseManager` opens SQLite on native platforms and on the web.

- [Basic Usage](#basic-usage)
- [Quick Reference](#quick-reference)
- [Platforms](#platforms)
- [DatabaseManager](#databasemanager)
- [The Provider](#the-provider)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="basic-usage"></a>
## Basic Usage

`databaseConfig`, exported from the package barrel, is the default config. The installer registers `() => databaseConfig` in `configFactories`; to change the file name, register your own map under the same key instead:

```dart
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> main() async {
  await Magic.init(
    configs: [
      {
        'database': {
          'default': 'sqlite',
          'connections': {
            'sqlite': {'driver': 'sqlite', 'database': 'notes.db', 'prefix': ''},
          },
        },
        'app': {
          'providers': [
            (app) => DatabaseServiceProvider(app),
          ],
        },
      },
    ],
  );
}
```

<a name="quick-reference"></a>
## Quick Reference

| Key | Type | Default | Meaning |
|:----|:-----|:--------|:--------|
| `database.default` | `String` | `sqlite` | The connection name `DatabaseManager.init` opens. |
| `database.connections.<name>.database` | `String` | `magic_app.db` | The database file name (native) or the IndexedDB store name (web). |
| `database.connections.<name>.driver` | `String` | `sqlite` | Carried for Laravel's shape; the manager always opens SQLite. |
| `database.connections.<name>.prefix` | `String` | empty | Carried for Laravel's shape; table names are not prefixed. |

Without any `database` config the manager still opens `magic_app.db` on the `sqlite` connection, so `databaseConfig` is a convenience rather than a requirement.

<a name="platforms"></a>
## Platforms

| Platform | Backend | Where the data lives |
|:---------|:--------|:---------------------|
| Android, iOS, macOS, Windows, Linux | `sqlite3` over FFI | A file named by `database` in the application documents directory, which survives restarts and updates. |
| Web | `sqlite3.wasm` | An IndexedDB-backed file system named by `database`, so rows survive a page reload. |

The platform factory is chosen at compile time, so the same code runs on every target. On the web the wasm loads from the fixed root path `/sqlite3.wasm`, so `web/sqlite3.wasm` in your project is found only when the app is served from the site root, not from a sub-path; see [Installation](../getting-started/installation.md#web-setup).

<a name="databasemanager"></a>
## DatabaseManager

`DatabaseManager` is a singleton over the active `CommonDatabase`. Resolve it with `Magic.make<DatabaseManager>('db')` or call `DatabaseManager()`; both return the same instance.

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> main() async {
  final DatabaseManager manager = DatabaseManager();

  print(manager.isInitialized);
  print(await manager.getColumns('users')); // [id, name, email, created_at, updated_at]
  print(await manager.hasColumn('users', 'email'));

  manager.clearSchemaCache('users'); // omit the name to clear every table
  manager.dispose(); // closes the connection
}
```

| Member | Meaning |
|:-------|:--------|
| `init()` | Opens the configured connection once and dispatches core's `DatabaseConnected` event; a second call does nothing. |
| `connection` | The `CommonDatabase`; throws a `StateError` before `init()` completes. |
| `getColumns(table)`, `hasColumn(table, column)` | Column names from `PRAGMA table_info`, cached per table. |
| `clearSchemaCache([table])` | Forgets the cached columns; `Schema` and `Migrator` call it after every change. |
| `dispose()` | Closes the connection and clears the cache. |

The query builder and the model store filter every write against `getColumns`, so a stale cache after a manual `ALTER TABLE` drops the new column silently. Use `Schema.table` for column changes, or call `clearSchemaCache` yourself.

<a name="the-provider"></a>
## The Provider

`DatabaseServiceProvider.register()` binds `db` (the `DatabaseManager`) and `local_model_store` (a `QueryModelStore`) as singletons. `boot()` awaits `DatabaseManager.init()` and logs `Database ready [sqlite]`. A connection failure therefore surfaces during `Magic.init`, before `runApp`.

The `DatabaseConnected` event and its `db_events` siblings stay in core, so a listener written against them needs no change.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Using `:memory:` as the `database` value in tests | The native factory joins the name onto the documents directory. Open `sqlite3.openInMemory()` yourself and pass it to `DatabaseManager().setConnection`, see [Testing](../guides/testing.md). |
| Forgetting `web/sqlite3.wasm` on a web target | The first boot fails with a WebAssembly error. Run `local_storage:install` again. |
| Expecting `driver` to switch databases | Only SQLite is supported; `driver` is not read. |
| Calling `DatabaseManager().connection` before boot | It throws `Database not initialized`; wait for `Magic.init` or call `await DatabaseManager().init()`. |

<a name="related-documentation"></a>
## Related Documentation

- [Installation](../getting-started/installation.md): register the provider and the web wasm.
- [Queries](./queries.md): the `DB` facade over this connection.
- [Testing](../guides/testing.md): an in-memory connection per test.
