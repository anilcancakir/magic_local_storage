# Queries

Run raw SQL, build queries with the fluent `QueryBuilder` and group writes in a transaction through the `DB` facade.

- [Basic Usage](#basic-usage)
- [Quick Reference](#quick-reference)
- [Raw Queries](#raw-queries)
- [Query Builder](#query-builder)
- [Transactions](#transactions)
- [Schema Awareness](#schema-awareness)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="basic-usage"></a>
## Basic Usage

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> main() async {
  final int id = await DB.table('users').insert({'name': 'Ada', 'email': 'ada@example.com'});

  final List<Map<String, dynamic>> adults = await DB.table('users')
      .where('age', '>=', 18)
      .orderBy('name')
      .limit(10)
      .get();

  print('$id, ${adults.length}');
}
```

<a name="quick-reference"></a>
## Quick Reference

| Call | Returns | Meaning |
|:-----|:--------|:--------|
| `DB.table(name)` | `QueryBuilder` | Starts a query on a table. |
| `DB.select(sql, [params])` | `List<Map<String, dynamic>>` | Synchronous raw `SELECT`. |
| `DB.insert(sql, [params])` | `int` | Raw insert; the last inserted row id. |
| `DB.update(sql, [params])`, `DB.delete(sql, [params])` | `int` | Raw write; the number of changed rows. |
| `DB.statement(sql, [params])` | `void` | Raw statement with no result: DDL, `PRAGMA`, savepoints. |
| `DB.transaction(callback)` | `Future<T>` | Runs the callback in one transaction. |
| `DB.beginTransaction()`, `DB.commit()`, `DB.rollback()` | `void` | Manual control. |

<a name="raw-queries"></a>
## Raw Queries

Raw calls are synchronous: `DatabaseManager().connection` is a local SQLite handle, so nothing waits on a network. Bind values with `?` placeholders and pass them as the second argument; never interpolate user input into the SQL string.

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

void main() {
  final List<Map<String, dynamic>> adults = DB.select('SELECT * FROM users WHERE age > ?', [18]);

  final int id = DB.insert('INSERT INTO users (name, email) VALUES (?, ?)', ['Ada', 'ada@example.com']);
  final int changed = DB.update('UPDATE users SET name = ? WHERE id = ?', ['Grace', id]);
  final int removed = DB.delete('DELETE FROM users WHERE id = ?', [id]);

  DB.statement('CREATE INDEX idx_users_email ON users(email)');

  print('${adults.length} $changed $removed');
}
```

<a name="query-builder"></a>
## Query Builder

`DB.table(name)` returns a `QueryBuilder`. Chain constraints, then end with a method that runs the query.

| Constraint | Meaning |
|:-----------|:--------|
| `select(columns)` | Restricts the columns; the default is `*`. Each entry is a raw SQL fragment, see below. |
| `where(column, value)`, `where(column, operator, value)` | An `AND` condition; two arguments mean `=`. |
| `whereNull(column)`, `whereNotNull(column)` | `IS NULL` and `IS NOT NULL`. |
| `orderBy(column, [direction])` | `asc` by default, `asc` or `desc` in any case; repeat for a second sort key. |

`where` accepts the operators `=`, `!=`, `<>`, `<`, `<=`, `>`, `>=`, `like`, `not like`, `is` and `is not`, in any case; any other operator, `in` included, throws an `ArgumentError`, and so does an `orderBy` direction other than `asc` or `desc`. A `null` value becomes `IS NULL` with `=` or `is` (and in the two-argument form) and `IS NOT NULL` with `!=`, `<>` or `is not`; with any other operator it throws an `ArgumentError`.

Table names and the columns of `where`, `whereNull`, `whereNotNull`, `orderBy`, `insert` and `update` are quoted as identifiers, so a keyword column such as `order` or `group` works and `users.id` still names a qualified column. `select([...])`, `value(column)` and `pluck(column)` write their entries into the `SELECT` list as raw SQL, so an expression such as `COUNT(*) AS total` works there and a keyword column has to be quoted by hand: `select(['"order"'])`.
| `limit(count)`, `offset(count)` | Paging. |

| Terminal | Returns | Meaning |
|:---------|:--------|:--------|
| `get()` | `Future<List<Map<String, dynamic>>>` | Every matching row. |
| `first()` | `Future<Map<String, dynamic>?>` | The first row, or `null`. |
| `value<T>(column)` | `Future<T?>` | One column of the first row. |
| `pluck<T>(column)` | `Future<List<T>>` | One column of every row. |
| `count()`, `exists()` | `Future<int>`, `Future<bool>` | Aggregate checks. |
| `insert(map)` | `Future<int>` | The new row id; `0` when no key matches a column. |
| `insertAll(records)` | `Future<void>` | One insert per record. |
| `update(map)`, `delete()` | `Future<int>` | The number of changed rows. |
| `truncate()` | `Future<void>` | Deletes every row of the table. |

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> main() async {
  final Map<String, dynamic>? user = await DB.table('users').where('email', 'ada@example.com').first();
  final List<String> names = await DB.table('users').whereNotNull('email').orderBy('name', 'desc').pluck<String>('name');
  final bool taken = await DB.table('users').where('name', 'Ada').exists();

  await DB.table('users').where('id', 1).update({'name': 'Grace'});
  await DB.table('users').whereNull('email').delete();

  print('$user $names $taken');
}
```

Values are converted on the way in: `bool` becomes `1` or `0`, `DateTime` and `Carbon` become ISO 8601 text, and a `Map` or `List` becomes JSON text. Reads return the raw SQLite values, so a boolean column comes back as `0` or `1`; a `Model` cast turns them back, see [Models](./models.md).

<a name="transactions"></a>
## Transactions

`DB.transaction` runs the callback between `BEGIN` and `COMMIT` and rolls back when it throws, rethrowing your error.

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> main() async {
  await DB.transaction(() async {
    final int userId = await DB.table('users').insert({'name': 'Ada'});
    await DB.table('profiles').insert({'user_id': userId, 'bio': 'Mathematician'});
  });
}
```

Do not call `DB.commit()` or `DB.rollback()` inside the callback: the block owns the transaction, and anything written afterwards would run outside it. When the callback fails after closing it, the rollback is skipped so your error is not replaced by `cannot rollback - no transaction is active`; on success the call throws a `StateError` naming the mistake, because returning normally would claim the block was atomic.

To interleave other work between statements, use the manual API throughout instead of mixing the two:

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> main() async {
  DB.beginTransaction();

  try {
    await DB.table('accounts').where('id', 1).update({'balance': 90});
    await DB.table('transfers').insert({'account_id': 1, 'amount': 10});
    DB.commit();
  } catch (_) {
    DB.rollback();
    rethrow;
  }
}
```

`BEGIN` does not nest. A block that has to run inside someone else's transaction uses a `SAVEPOINT` through `DB.statement`, which is what `Migrator` and `SyncLedger` do.

<a name="schema-awareness"></a>
## Schema Awareness

`QueryBuilder.insert` and `update` drop every key that is not a column of the table, using the cached `PRAGMA table_info` of `DatabaseManager`. A map that carries a computed or remote-only attribute therefore never fails the write; the price is that a typo in a column name is dropped without an error. When `insert` returns `0`, none of your keys matched a column.

A table with no columns does not exist, so `insert` and `update` on it throw a `StateError` naming the table, usually because its migration has not run yet. The manager caches only tables that exist, so a table created afterwards, even by a raw `DB.statement`, is seen by the next write.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Passing input as a table, column, operator or direction | Only values are bound. Names are quoted but still choose what is read, and `select` entries are raw SQL: whitelist names before they reach `table`, `where`, `orderBy` or `select`. |
| `where('age', '>', null)` | It throws an `ArgumentError`; a `null` value only pairs with `=`, `!=`, `<>`, `is` and `is not`. |
| `where('id', 'in', [1, 2])` | `in` is not supported and throws an `ArgumentError`; use a raw `DB.select` with one `?` per value. |
| Writing to a table before its migration ran | It throws a `StateError` naming the table; run `Migrator().run` first. |
| Looking for an `OR` condition | Constraints are always `AND`ed; write the `OR` in a raw `DB.select`. |
| `insertAll` for an atomic bulk write | It is one insert per record; wrap it in `DB.transaction`. |
| `DB.commit()` inside `DB.transaction` | Remove it; the block commits for you. |
| Awaiting `DB.select` | It is synchronous and returns the list directly. |
| Expecting booleans back from a raw read | SQLite stores `0` and `1`; cast with a model or compare to `1`. |

<a name="related-documentation"></a>
## Related Documentation

- [Models](./models.md): `useLocal` models over the same connection.
- [Migrations](./migrations.md): creating the tables you query.
- [Configuration](./configuration.md): the connection behind `DB`.
- [Testing](../guides/testing.md): assertions with `DB.table`.
