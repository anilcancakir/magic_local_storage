# magic_local_storage example

A Magic app with one local SQLite table. At startup it registers `DatabaseServiceProvider`, runs the `CreateNotesTable` migration, and `Add note` saves a `Note` (a model with `useLocal => true`) and lists every row back. The rows live in `magic_app.db` in the app documents directory, so they survive a restart.

```bash
cd example
flutter create --platforms=macos .
flutter run -d macos
```

`flutter create` adds the platform folder once; it leaves `lib/` and `pubspec.yaml` as they are.

For a web target, create it with `--platforms=web` and put `web/sqlite3.wasm`, which the browser loads SQLite from, in place by hand: the example has no dowel dispatcher, so `local_storage:install` does not run here. Download the wasm of the `sqlite3` release in `example/pubspec.lock` from the [sqlite3.dart releases](https://github.com/simolus3/sqlite3.dart/releases):

```bash
curl -L https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.9.1/sqlite3.wasm -o web/sqlite3.wasm
```

In your own app, `dart run magic:dowel magic:install` scaffolds the dispatcher and `dart run magic:dowel plugin:install magic_local_storage` then downloads it for you.

The migration is hand-written to show the shape; in your own app generate it with `dart run magic:dowel make:migration create_notes_table --create=notes`.
