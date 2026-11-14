# Generators

Scaffold migrations, seeders and factories with `make:migration`, `make:seeder` and `make:factory`, and wire the package into an app with `local_storage:install`.

- [Quick Reference](#quick-reference)
- [make:migration](#make-migration)
- [make:seeder](#make-seeder)
- [make:factory](#make-factory)
- [local_storage:install](#local-storage-install)
- [With make:model and make:resource](#with-make-model-and-make-resource)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Command | Writes | Notes |
|:--------|:-------|:------|
| `make:migration <name>` | `lib/database/migrations/m_<YYYYMMDDHHMMSS>_<snake_name>.dart` | `--create=<table>` or `--table=<table>`. |
| `make:seeder <name>` | `lib/database/seeders/<snake_name>_seeder.dart` | Adds the `Seeder` suffix. |
| `make:factory <name>` | `lib/database/factories/<snake_name>_factory.dart` | Adds the `Factory` suffix. |
| `local_storage:install` | Provider, config factory and `web/sqlite3.wasm` | Chained by `plugin:install`. |

Run them with `dart run magic:dowel <command>`. Each generator takes `--force` to overwrite an existing file. They load their stubs from this package, so `flutter pub get` must have run.

<a name="make-migration"></a>
## make:migration

```bash
dart run magic:dowel make:migration create_posts_table --create=posts
dart run magic:dowel make:migration add_slug_to_posts --table=posts
dart run magic:dowel make:migration CreateTagsTable --create=tags
```

The file name carries a 14-digit timestamp so files sort in run order. The class is the PascalCase of the name without the timestamp, and the migration's `name` is `<timestamp>_<snake_name>`, which is the ledger key.

| Option | Effect |
|:-------|:-------|
| `--create=<table>`, `-c` | Uses the stub with a `Schema.create` body, `id()` and `timestamps()`; the table name is the value. |
| `--table=<table>`, `-t` | Writes the skeleton: an empty `up()` and a `down()` that throws `UnsupportedError('<name> has no rollback yet.')`. The skeleton has no table placeholder, so add the `Schema.table` call yourself and replace the throw with the reverse statements. |
| neither | The same skeleton. |

A name with a `..` or `.` segment, an empty segment (a leading, trailing or doubled `/`), a backslash or a colon is refused with exit code `1` before anything is written, by all three generators; a nested name such as `admin/create_reports_table` stays inside the default directory.

The generator does not register the migration: add it to your `Migrator().run([...])` list, see [Migrations](../basics/migrations.md#running-migrations).

<a name="make-seeder"></a>
## make:seeder

```bash
dart run magic:dowel make:seeder PostSeeder
dart run magic:dowel make:seeder Post
```

Both write `lib/database/seeders/post_seeder.dart` with a `PostSeeder` class holding an empty `run()` and a comment showing a factory call. A nested name such as `blog/Post` keeps its directory.

<a name="make-factory"></a>
## make:factory

```bash
dart run magic:dowel make:factory Post
dart run magic:dowel make:factory PostFactory
```

Both write `lib/database/factories/post_factory.dart`. The stub types the factory as `Factory<Model>` and throws from `newInstance()` until you import your model and replace the `TODO` lines, so the file does not compile into a working factory before you edit it. A commented extension at the bottom shows where factory states go, see [Seeding](../basics/seeding.md#factory-states).

<a name="local-storage-install"></a>
## local_storage:install

```bash
dart run magic:dowel local_storage:install
dart run magic:dowel local_storage:install --dry-run
```

It reads the package's `install.yaml`, adds `DatabaseServiceProvider` to `lib/config/app.dart` and `() => databaseConfig` to `lib/main.dart`, then downloads `web/sqlite3.wasm` when the project has a `web/` folder and none exists yet. `plugin:install magic_local_storage` chains it for you.

| Flag | Effect |
|:-----|:-------|
| `--dry-run` | Prints the staged edits, writes nothing and skips the download. |
| `--force` | Overwrites files that differ from what the installer last wrote. |
| `--non-interactive` | Skips prompts and uses defaults. |
| `--no-bootstrap` | Skips auto-running the bootstrap command. |

It exits `1` with a hint when `flutter pub get` has not run, and when a file conflicts without `--force`. A failed wasm download is reported with the `curl` line to run by hand and does not fail the install.

<a name="with-make-model-and-make-resource"></a>
## With make:model and make:resource

Core's `make:model` and `make:resource` do not ship database generators of their own. They look up `make:migration`, `make:factory` and `make:seeder` in the dowel registry by name, so the plugin's commands appear once it is installed:

```bash
dart run magic:dowel make:model Post -mfs
dart run magic:dowel make:model Post --all
```

`-m` runs `make:migration create_posts_table --create=posts`, `-f` runs `make:factory Post` and `-s` runs `make:seeder Post`; `--all` runs all three together with the policy, repository and controller. Without this package the model is still written, and each missing generator prints a hint naming `magic_local_storage` and the `plugin:install` command, then the command carries on.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| `make:migration` fails to find a stub | Run `flutter pub get`; the stubs are resolved through `.dart_tool/package_config.json`. |
| A new migration that never runs | Add it to the `Migrator().run` list; there is no discovery. |
| A generated factory that throws `UnimplementedError` | Import your model and implement `newInstance()` and `newFactory()`. |
| Renaming a generated migration file after release | Keep the `name` getter; the ledger keys on it, not on the file name. |
| `make:model -m` printing a hint | Add `magic_local_storage` and run `plugin:install`. |

<a name="related-documentation"></a>
## Related Documentation

- [Installation](../getting-started/installation.md): what `plugin:install` changes.
- [Migrations](../basics/migrations.md): the migration the generator writes.
- [Seeding](../basics/seeding.md): seeders and factories.
