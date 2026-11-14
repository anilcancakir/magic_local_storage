# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.0.1] - 2026-11-14

### Added

- **First release.** The SQLite layer for Magic apps, moved out of `magic` core 0.1.0. A model with `useLocal => true` needs this package.
- `DB` and `Schema` facades on one local SQLite connection, with `Migration` and `Migrator`, `Seeder`, `Factory` and `Seeding.run`, and a `QueryBuilder` behind `Model.query()`.
- `QueryModelStore`, the storage behind every `useLocal` model, replaceable at the `LocalModelStore` container key.
- `SyncFeed` and `SyncLedger`: a push-then-pull sync skeleton.
- `DatabaseServiceProvider` and the `databaseConfig` config factory.
- Generators `make:migration`, `make:seeder` and `make:factory`, and `local_storage:install`, which downloads `web/sqlite3.wasm` for a project with a `web/` folder.
- A `dowel` plugin provider (`MagicLocalStorageDowelProvider`) that `dart run magic:dowel plugin:install magic_local_storage` registers.
- Native through FFI, web through `sqlite3.wasm`. Built on `sqlite3` 3.9.1, `path_provider` ^2.1.6, `path` ^1.9.1 and `dowel` ^0.0.21. Requires Dart 3.13, Flutter 3.47 and `magic` ^0.1.0.
