# magic_local_storage example

A Magic app with one local SQLite table. At startup it registers `DatabaseServiceProvider`, runs the `CreateNotesTable` migration, and `Add note` saves a `Note` (a model with `useLocal => true`) and lists every row back. The rows live in `magic_app.db` in the app documents directory, so they survive a restart.

```bash
cd example
flutter create --platforms=macos .
flutter run -d macos
```

`flutter create` adds the platform folder once; it leaves `lib/` and `pubspec.yaml` as they are.

For a web target, create it with `--platforms=web` and run `dart run magic:dowel local_storage:install` from `example/` to download `web/sqlite3.wasm`, which the browser loads SQLite from.

The migration is hand-written to show the shape; in your own app generate it with `dart run magic:dowel make:migration create_notes_table --create=notes`.
