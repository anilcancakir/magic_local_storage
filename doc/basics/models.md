# Models

Persist a Magic `Model` to the local SQLite database with `useLocal => true`, and understand the `LocalModelStore` contract this package fulfils.

- [Basic Usage](#basic-usage)
- [Quick Reference](#quick-reference)
- [The Store](#the-store)
- [Without the Plugin](#without-the-plugin)
- [Direct Queries](#direct-queries)
- [Custom Stores](#custom-stores)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="basic-usage"></a>
## Basic Usage

The model lives in core; this package only supplies the storage behind `useLocal`. The `posts` table comes from [Migrations](./migrations.md) and must exist.

```dart
import 'package:magic/magic.dart';

class Post extends Model with HasTimestamps, InteractsWithPersistence {
  @override
  String get table => 'posts';

  @override
  String get resource => 'posts';

  @override
  List<String> get fillable => ['title', 'body', 'is_published'];

  @override
  Map<String, String> get casts => const {'is_published': 'bool'};

  @override
  bool get useLocal => true;

  @override
  bool get useRemote => false;

  String? get title => getAttribute('title') as String?;

  static Future<Post?> find(dynamic id) => InteractsWithPersistence.findById<Post>(id, Post.new);

  static Future<List<Post>> all() => InteractsWithPersistence.allModels<Post>(Post.new);
}

Future<void> main() async {
  final Post post = Post()..fill({'title': 'Hello', 'is_published': true});
  await post.save();

  final Post? found = await Post.find(post.id);
  final List<Post> everything = await Post.all();

  await found?.delete();

  print(everything.length);
}
```

<a name="quick-reference"></a>
## Quick Reference

| `useLocal` | `useRemote` | Behaviour |
|:-----------|:------------|:----------|
| `true` | `false` | SQLite only; no HTTP call is made. |
| `true` | `true` | Both. `find` reads SQLite first and asks the API on a miss; `all` reads SQLite and asks the API only when that read throws. A row pulled from the API is upserted locally; writes go to both. |
| `false` | `true` | API only; the store is never resolved. This is the default. |

`save`, `delete`, `refresh`, `findById` and `allModels` are core's `InteractsWithPersistence`; see the Eloquent pages of the core documentation for fillable lists, casts, events and the remote leg.

<a name="the-store"></a>
## The Store

Core defines the contract, `LocalModelStore`, and resolves it from the container key `local_model_store` before every local leg. `DatabaseServiceProvider` binds a `QueryModelStore` there.

| Method | Meaning |
|:-------|:--------|
| `find(table, primaryKey, id)` | The row map, or `null`. |
| `all(table)` | Every row. |
| `insert(table, data)` | The new row key. |
| `update(table, primaryKey, id, data)` | Overwrites the row. |
| `delete(table, primaryKey, id)` | Removes the row. |
| `upsert(table, primaryKey, id, data)` | Updates the row when it exists, inserts otherwise; used for rows pulled from the remote side. |

`QueryModelStore` runs these through `QueryBuilder`. Writes keep only the attributes the table has a column for, so a model may carry a computed or remote-only attribute without breaking the insert. An `insert` or `update` on a table that does not exist throws a `StateError` naming it, which core's `save()` reports as `false`; a `delete` there fails with SQLite's own `no such table` error instead. Booleans, dates and maps are stored as described in [Queries](./queries.md), and the model's `casts` restore them when a row is hydrated.

<a name="without-the-plugin"></a>
## Without the Plugin

A `useLocal` model resolves the store before its first local statement. When nothing is bound to `local_model_store`, every leg throws a `StateError` that names `magic_local_storage`:

```text
A model with useLocal enabled needs a LocalModelStore bound to "local_model_store".
Add magic_local_storage and register its service provider, or set useLocal to false.
```

The check runs before the leg's own `try`, so the error is never swallowed by a local-or-remote fallback. The fix is one of two: add this package and register `DatabaseServiceProvider`, or set `useLocal` to `false`.

<a name="direct-queries"></a>
## Direct Queries

The `ModelQuery` extension adds `query()` to every `Model`: a `QueryBuilder` over the model's table, for conditions the static helpers do not cover.

```dart
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

class Post extends Model {
  @override
  String get table => 'posts';

  @override
  String get resource => 'posts';
}

Future<void> main() async {
  final List<Map<String, dynamic>> drafts = await Post().query().where('is_published', false).orderBy('id', 'desc').get();

  print(drafts.length);
}
```

The result is raw row maps, not models. Hydrate them with `InteractsWithPersistence.hydrate<Post>(row, Post.new)` when you need the typed accessors.

<a name="custom-stores"></a>
## Custom Stores

Any class that implements `LocalModelStore` can replace the default, which is how a test double or another engine plugs in. Bind it to the same key after the provider has registered:

```dart
import 'package:magic/magic.dart';

class MemoryModelStore implements LocalModelStore {
  final Map<String, Map<dynamic, Map<String, dynamic>>> _tables = {};

  Map<dynamic, Map<String, dynamic>> _rows(String table) => _tables.putIfAbsent(table, () => {});

  @override
  Future<Map<String, dynamic>?> find(String table, String primaryKey, dynamic id) async => _rows(table)[id];

  @override
  Future<List<Map<String, dynamic>>> all(String table) async => _rows(table).values.toList();

  @override
  Future<dynamic> insert(String table, Map<String, dynamic> data) async {
    final int id = _rows(table).length + 1;
    _rows(table)[id] = {...data, 'id': id};

    return id;
  }

  @override
  Future<void> update(String table, String primaryKey, dynamic id, Map<String, dynamic> data) async {
    _rows(table)[id] = {...data};
  }

  @override
  Future<void> delete(String table, String primaryKey, dynamic id) async {
    _rows(table).remove(id);
  }

  @override
  Future<void> upsert(String table, String primaryKey, dynamic id, Map<String, dynamic> data) async {
    _rows(table)[id] = {...data};
  }
}

void main() {
  MagicApp.instance.singleton('local_model_store', () => MemoryModelStore());
}
```

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| A `StateError` mentioning `local_model_store` | Register `DatabaseServiceProvider`, or bind a `LocalModelStore`, or set `useLocal` to `false`. |
| Saving a model before its migration ran | The store throws a `StateError` naming the missing table, so `save()` returns `false` on a local-only model and it keeps `exists == false` (core's `save` catches the error; with `useRemote` on, a successful remote write still reports `true`). Run `Migrator().run` first. |
| A typo in `fillable` or an attribute name | A key without a column is dropped silently by the store. Check the table's columns. |
| Reading a boolean column through `query()` | Raw rows hold `0` and `1`; hydrate through the model to apply its casts. |
| Expecting `Magic.seed` | It is gone; use `Seeding.run`, see [Seeding](./seeding.md). |
| Running a `useLocal` test with no store bound | Bind the plugin provider, a `QueryModelStore` or a fake, see [Testing](../guides/testing.md). |

<a name="related-documentation"></a>
## Related Documentation

- [Queries](./queries.md): the `QueryBuilder` behind the store.
- [Migrations](./migrations.md): the tables a model persists to.
- [Seeding](./seeding.md): factories that create models.
- [Sync](../guides/sync.md): keeping the local store consistent with a server.
- [Testing](../guides/testing.md): binding a store in a test.
