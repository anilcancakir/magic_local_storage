# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed

- **The database opens on an Apple TV.** The native connection factory resolves the database directory through `MagicPaths.appData()` instead of the documents directory, so on tvOS, which denies writes to Documents on a device, the file lives in `app_data` under the cache directory; every other platform still uses the documents directory. The system may purge the cache directory when storage runs low, so keep only rebuildable data in a tvOS database. Needs a `magic` release that ships `MagicPaths`. (`lib/src/database/connectors/connection_factory_io.dart`)

### Changed

- **The README shows the plugin's own logo instead of the Magic logo.** `.github/logo.png`, a 512 pixel PNG of the mark the docs site serves, replaces `.github/magic-logo.svg`. (`README.md`, `.github/`)

## [1.0.1] - 2026-11-15

### Fixed

- Saving a `useLocal` model, or calling `insert` or `update`, on a table that does not exist yet now throws a `StateError` naming the table instead of reporting success, so `save()` returns `false` before the migration ran; a table created later is seen without a restart.
- Plain table and column names (letters, digits and underscores, optionally dotted such as `users.id` or `cache.items`) are quoted in `Schema.create`, `Schema.table`, `Schema.drop`, `Schema.rename` and the query builder's `where`, `orderBy`, `value`, `pluck`, `insert` and `update`, so a column named `order`, `group` or `index` works; any other text, such as `lower(email)` or `name COLLATE NOCASE`, is written as given, so a caller passing an expression sees no change. A string default containing `'` no longer breaks `CREATE TABLE`, and a schema-qualified table such as `cache.items` is now read and written.
- `where` rejects an operator outside `=`, `==`, `!=`, `<>`, `<`, `<=`, `>`, `>=`, `like`, `not like`, `glob`, `not glob`, `match`, `is` and `is not`, and `orderBy` a direction other than `asc` or `desc`, with an `ArgumentError`, so neither can carry SQL.
- A connection opened by the provider treats a double-quoted name as an identifier only, so a mistyped quoted column fails with `no such column` instead of matching a string literal.
- `where(column, '=', null)` no longer binds `'='` as the value: a `null` value compiles to `IS NULL` with `=`, `==`, `is` or two arguments and to `IS NOT NULL` with `!=`, `<>` or `is not`, and throws an `ArgumentError` with any other operator.
- `make:migration`, `make:seeder` and `make:factory` refuse a name with `..`, an empty segment, a backslash or a colon instead of writing outside `lib/database/`.
- Corrected the sqlite3 repository links and the wasm compatibility notes, the example's web setup, and the `llms.txt` setup sample, which now calls `Magic.init`.
- The documentation and the agent skill now match the code: a write to a table that does not exist throws a `StateError` (so `save()` returns `false` on a local-only model and `Factory.create()` throws) rather than dropping every attribute or answering `0`; with `useLocal` and `useRemote` both on, `find` falls back to the API on a miss and `all` only when the local read throws; `SyncFeed.run` logs only a thrown exception, not a refused HTTP response; the testing guide no longer lists `Http.unfake()` among the statics a container reset leaves; and the web wasm is always requested at the origin root `/sqlite3.wasm`, so an app served from a sub-path must still serve the file there.
- The agent skill listing is shorter.

### Changed

- The `make:migration` skeleton's `down()` throws `UnsupportedError` until you write the rollback, so a rollback can no longer forget a migration that is still applied.
- `local_storage:install` downloads the `sqlite3.wasm` of the `sqlite3` release the project resolved, falling back to 3.9.1 when it cannot read it.
- The package page is `https://anilcancakir.com/magic/local_storage` and the documentation links sit under `https://anilcancakir.com/magic/docs/local_storage`.

## [1.0.0] - 2026-11-14

### Added

- **First release.** The SQLite layer for Magic apps, moved out of `magic` core 1.0.0. A model with `useLocal => true` needs this package.
- `DB` and `Schema` facades on one local SQLite connection, with `Migration` and `Migrator`, `Seeder`, `Factory` and `Seeding.run`, and a `QueryBuilder` behind `Model.query()`.
- `QueryModelStore`, the storage behind every `useLocal` model, replaceable at the `LocalModelStore` container key.
- `SyncFeed` and `SyncLedger`: a push-then-pull sync skeleton.
- `DatabaseServiceProvider` and the `databaseConfig` config factory.
- Generators `make:migration`, `make:seeder` and `make:factory`, and `local_storage:install`, which downloads `web/sqlite3.wasm` for a project with a `web/` folder.
- A `dowel` plugin provider (`MagicLocalStorageDowelProvider`) that `dart run magic:dowel plugin:install magic_local_storage` registers.
- Native through FFI, web through `sqlite3.wasm`. Built on `sqlite3` 3.9.1, `path_provider` ^2.1.6, `path` ^1.9.1 and `dowel` ^1.0.0. Requires Dart 3.13, Flutter 3.47 and `magic` ^1.0.0.
