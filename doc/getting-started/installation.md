# Installation

Add `magic_local_storage` to a Magic app, register its provider and config, and check that the `DB` facade reaches an open SQLite connection.

- [Install](#install)
- [Requirements](#requirements)
- [What the Installer Does](#what-the-installer-does)
- [Register by Hand](#register-by-hand)
- [Web Setup](#web-setup)
- [Verify](#verify)
- [Related Documentation](#related-documentation)

<a name="install"></a>
## Install

```bash
flutter pub add magic_local_storage
dart run magic:dowel plugin:install magic_local_storage
```

The barrel, `package:magic_local_storage/magic_local_storage.dart`, is the only runtime import; everything under `src/` is private. The package also ships a Flutter-free `package:magic_local_storage/cli.dart` for the generators, which the dowel dispatcher loads for you.

Magic core no longer carries the SQLite layer. A model with `useLocal => true` needs this package: without it the first `find`, `all`, `save`, `delete` or `refresh` throws a `StateError` naming `magic_local_storage`, see [Models](../basics/models.md).

<a name="requirements"></a>
## Requirements

| Requirement | Value |
|:------------|:------|
| Dart | `>=3.13.0` |
| Flutter | `>=3.47.0` |
| Magic | `^0.1.0`, installed and bootstrapped (`lib/config/app.dart` exists) |
| Native | Android, iOS, macOS, Windows and Linux through `sqlite3` FFI, no setup |
| Web | `web/sqlite3.wasm`, downloaded by the installer, see [Web Setup](#web-setup) |

<a name="what-the-installer-does"></a>
## What the Installer Does

`plugin:install` reads the package's `install.yaml` and makes two edits: it adds `DatabaseServiceProvider` to the `providers` list of `lib/config/app.dart`, and it adds `() => databaseConfig` to the `configFactories` of `lib/main.dart`. No config file is published, because `databaseConfig` is a getter the package exports.

It then chains `local_storage:install`, which downloads `web/sqlite3.wasm` when the project has a `web/` folder. Both steps skip work that is already done, so running the installer twice changes nothing.

<a name="register-by-hand"></a>
## Register by Hand

To wire it yourself, register the provider and the config factory in `Magic.init`:

```dart
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> main() async {
  await Magic.init(
    configFactories: [
      () => databaseConfig,
    ],
    configs: [
      {
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

`DatabaseServiceProvider` is not auto-registered. Its `register()` binds the `DatabaseManager` at `db` and the `QueryModelStore` at `local_model_store`; its `boot()` opens the connection, so the first statement after `Magic.init` already has one. List the provider before any provider whose `boot()` runs a query.

<a name="web-setup"></a>
## Web Setup

Flutter web loads SQLite from `web/sqlite3.wasm`. The installer downloads release `sqlite3-3.9.1` of the `sqlite3` package into `web/` when the folder exists and keeps a file that is already there. Add the web target later with `flutter create --platforms=web .`, then run:

```bash
dart run magic:dowel local_storage:install
```

A failed download prints the `curl -L ... -o web/sqlite3.wasm` line to run by hand and does not fail the install. Keep the wasm at the release that matches the `sqlite3` Dart package: a mismatched wasm corrupts data at runtime. `dart run magic:dowel local_storage:install --dry-run` stages the edits without writing.

<a name="verify"></a>
## Verify

```dart
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

void main() {
  // Magic.init(...) has run with the provider and config above.
  print(Magic.bound('db')); // true
  print(Magic.bound('local_model_store')); // true
  print(DB.select('SELECT sqlite_version() AS version').single['version']);
}
```

If `DB` throws `Database not initialized`, `DatabaseServiceProvider` is missing from `providers` or `Magic.init` has not completed.

<a name="related-documentation"></a>
## Related Documentation

- [Configuration](../basics/configuration.md): the `database` config, platforms and the connection.
- [Migrations](../basics/migrations.md): create your first table.
- [Models](../basics/models.md): persisting a `useLocal` model.
- [Generators](../guides/generators.md): `make:migration`, `make:seeder`, `make:factory`.
