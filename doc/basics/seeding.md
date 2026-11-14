# Seeding

Fill the local database with sample or default rows using `Seeder` classes and model `Factory` classes, and run them with `Seeding.run`.

- [Basic Usage](#basic-usage)
- [Quick Reference](#quick-reference)
- [Running Seeders](#running-seeders)
- [Writing Seeders](#writing-seeders)
- [Writing Factories](#writing-factories)
- [Using Factories](#using-factories)
- [Factory States](#factory-states)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="basic-usage"></a>
## Basic Usage

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
  // After Magic.init(...) and Migrator().run(...).
  await Seeding.run([PostSeeder()]);
}
```

<a name="quick-reference"></a>
## Quick Reference

| Call | Returns | Meaning |
|:-----|:--------|:--------|
| `Seeding.run(seeders)` | `Future<void>` | Runs each seeder in order and logs the start and the end. |
| `Seeder.run()` | `Future<void>` | The body of a seeder; you implement it. |
| `Seeder.call(seeders)` | `Future<void>` | Runs other seeders from inside one. |
| `Factory.count(n)` | `Factory<T>` | A copy that builds `n` models. |
| `Factory.state(map)` | `Factory<T>` | A copy with `map` merged over the definition. |
| `Factory.create()` | `Future<List<T>>` | Builds and saves the models. |
| `Factory.make()` | `List<T>` | Builds the models without saving. |
| `Factory.raw()` | `List<Map<String, dynamic>>` | The attribute maps only. |

<a name="running-seeders"></a>
## Running Seeders

`Seeding.run(List<Seeder>)` is the entry point, and it replaces core's removed `Magic.seed`. Call it from `main()` after the migrations, and guard it so a restart does not seed twice:

```dart
import 'package:flutter/foundation.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

class DatabaseSeeder extends Seeder {
  @override
  Future<void> run() async {}
}

Future<void> seedOnce() async {
  if (!kDebugMode) return;

  if (await DB.table('posts').count() == 0) {
    await Seeding.run([DatabaseSeeder()]);
  }
}
```

<a name="writing-seeders"></a>
## Writing Seeders

Generate one with `dart run magic:dowel make:seeder PostSeeder`, which writes `lib/database/seeders/post_seeder.dart` and adds the `Seeder` suffix when you leave it off. A seeder has one method, `run()`. A `DatabaseSeeder` that fans out uses `call`:

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

class UserSeeder extends Seeder {
  @override
  Future<void> run() async {}
}

class PostSeeder extends Seeder {
  @override
  Future<void> run() async {}
}

class DatabaseSeeder extends Seeder {
  @override
  Future<void> run() async {
    await call([
      UserSeeder(),
      PostSeeder(),
    ]);
  }
}
```

Order matters: a seeder that needs rows from another runs after it.

<a name="writing-factories"></a>
## Writing Factories

Generate one with `dart run magic:dowel make:factory Post`, which writes `lib/database/factories/post_factory.dart` with the `Factory` suffix added. A factory extends `Factory<T>` and implements three methods:

| Method | Returns | Meaning |
|:-------|:--------|:--------|
| `definition()` | `Map<String, dynamic>` | The default attributes. |
| `newInstance()` | `T` | An empty model. |
| `newFactory()` | `Factory<T>` | A fresh factory of the same class; `count` and `state` copy through it. |

`faker` is a getter on the base class, so `faker.person.name()`, `faker.internet.email()` and `faker.lorem.sentence()` need no import. The generated stub types the factory as `Factory<Model>` with `TODO` markers; replace those with your model.

Like Laravel, a factory fills its models unguarded: `id`, timestamps and keys missing from `fillable` are kept, so a factory can build a model exactly as an API returns it. Outside a factory `fill()` still honours `fillable` and `guarded`. The same switch is available directly, and it needs a synchronous callback:

```dart
import 'package:magic/magic.dart';

class User extends Model {
  @override
  String get table => 'users';

  @override
  String get resource => 'users';
}

void main() {
  final User user = Model.unguarded(() => User()..fill({'id': 1, 'name': 'Taylor'}));

  print(user.id);
}
```

<a name="using-factories"></a>
## Using Factories

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

Future<void> main() async {
  final Post one = (await PostFactory().create()).first; // saved
  final List<Post> fifty = await PostFactory().count(50).create();
  final List<Post> drafts = await PostFactory().state({'title': 'Draft'}).count(5).create();

  final List<Post> unsaved = PostFactory().count(10).make(); // in memory only
  final List<Map<String, dynamic>> payloads = PostFactory().count(3).raw(); // attribute maps

  print('${one.id} ${fifty.length} ${drafts.length} ${unsaved.length} ${payloads.length}');
}
```

`state()` and `count()` never change the factory they are called on; they return a copy built through `newFactory()`, so a shared base factory can branch without one branch leaking into the other. `make()` leaves each model unsaved with every attribute dirty, and `raw()` returns one map per model.

`create()` saves through the model's `save()`, so the model needs `InteractsWithPersistence`. A refused save throws a `StateError` carrying the model's validation errors instead of returning a half-built list.

<a name="factory-states"></a>
## Factory States

Write reusable states as an extension on `Factory<Post>`. `state()` and `count()` return `Factory<Post>`, so an extension method chains before or after either of them:

```dart
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

class Post extends Model {
  @override
  String get table => 'posts';

  @override
  String get resource => 'posts';
}

extension PostFactoryStates on Factory<Post> {
  Factory<Post> published() => state({'is_published': true});

  Factory<Post> draft() => state({'is_published': false});
}

Future<void> seedPosts(Factory<Post> posts) async {
  await posts.published().count(3).create();
  await posts.count(10).draft().create();
}
```

A method declared on `PostFactory` itself would be unreachable after the first `state()` or `count()` call, because their result is typed `Factory<Post>`.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Calling `Magic.seed` | Removed from core; call `Seeding.run([...])`. |
| Seeding on every launch | Guard with a `count()` check or run it behind `kDebugMode`. |
| `Factory.create()` on a model without `InteractsWithPersistence` | The factory calls `save()` dynamically; add the mixin or use `make()`. |
| Naming a state method on the factory subclass | Declare it as an extension on `Factory<T>`; the subclass method is lost after `count()`. |
| Expecting `create()` to return one model | It returns a list; take `.first` for a single model. |
| Seeding before the migrations | Run `Migrator().run` first; a missing table makes the store throw a `StateError`, `save()` answers `false` and `create()` throws a `StateError`. |

<a name="related-documentation"></a>
## Related Documentation

- [Models](./models.md): the `useLocal` models a factory builds.
- [Migrations](./migrations.md): the tables a seeder fills.
- [Generators](../guides/generators.md): `make:seeder` and `make:factory`.
- [Testing](../guides/testing.md): factories in tests.
