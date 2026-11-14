# Sync

Keep a local table consistent with a server across many devices with `SyncFeed`, a push-then-pull loop over one resource, and `SyncLedger`, its bookmark store.

- [Basic Usage](#basic-usage)
- [Quick Reference](#quick-reference)
- [The Wire Protocol](#the-wire-protocol)
- [Writing a Feed](#writing-a-feed)
- [Registering the Ledger Table](#registering-the-ledger-table)
- [The Two-Clock Rule](#the-two-clock-rule)
- [The Savepoint Note](#the-savepoint-note)
- [What Stays App-Side](#what-stays-app-side)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="basic-usage"></a>
## Basic Usage

`SyncFeed.run` pushes every row this device wrote since its last push and, only when that push had no failure, pulls everything the server holds past this device's last pull. It never throws: a failure arrives in the `SyncReport`, because a sync is a convenience on top of a local store that already works without it. Only a thrown exception is also logged, through `Log.error`; a refused HTTP response (a non-2xx push or pull) returns a report with `failure` set and logs nothing.

```dart
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> syncItems(SyncFeed feed, String teamId, String userId) async {
  final SyncReport report = await feed.run(scope: teamId, account: userId);

  if (!report.complete) {
    Log.warning('items sync did not finish: ${report.failure}');
  }
}
```

<a name="quick-reference"></a>
## Quick Reference

| Member | Meaning |
|:-------|:--------|
| `SyncFeed.run({scope, account})` | Runs both halves and answers a `SyncReport`. |
| `SyncReport` | `pushed` (rows the server accepted), `adopted` (rows taken from another device), `failure` (`String?`) and `complete`. |
| `feed`, `resource`, `envelopeKey` | The bookmark name, the API path and the push body key; you override them. |
| `pending(...)`, `adoptRow(...)` | Read the rows owed to the server and write a row the server sent; you override them. |
| `batchSize` | Rows per push request; `500` by default. |
| `maxPages` | Pull pages one run walks; `100` by default. |
| `SyncLedger({table})` | Reads and writes the bookmarks; `sync_cursors` by default. |
| `CreateSyncCursorsTable` | The migration that creates the ledger table. |

<a name="the-wire-protocol"></a>
## The Wire Protocol

**Push.** `POST '$resource/sync'` with `{envelopeKey: [row.data, ...]}`, in batches of `batchSize`. The response is read the way a pull page is (`{"data": [...]}`), so a write this device lost to a conflicting write elsewhere adopts the winner at once instead of waiting for the next pull.

**Pull.** `GET resource` with the query `{scope, cursor}`, `cursor` omitted when there is none yet. The response is `{"data": [...], "cursor": "<opaque text>", "has_more": bool}`. The cursor is taken from the body, never derived from the last row: the pair it encodes is the server's business. A run walks pages until `has_more` is false or `maxPages` is reached.

Both halves go through `Http`, so the app needs a network driver (`NetworkServiceProvider`) with the API base URL. A missing leading slash on `resource` is added for you.

Push runs first and the pull runs only after a push with no failure. The push makes the server's pull answer already reflect this device's own writes, so one round leaves the device consistent. A failed push still advances the mark over whatever landed before the failure, and leaves the pull cursor untouched.

<a name="writing-a-feed"></a>
## Writing a Feed

A feed supplies where its bookmarks live (`feed`), which endpoint it talks to (`resource`, `envelopeKey`), and how to read and write its own rows (`pending`, `adoptRow`).

```dart
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

class ItemsSyncFeed extends SyncFeed {
  @override
  String get feed => 'items';

  @override
  String get resource => 'items';

  @override
  String get envelopeKey => 'items';

  @override
  Future<List<SyncPushRow>> pending({
    required String account,
    required int sinceMillis,
    required String scope,
  }) async {
    final List<Map<String, dynamic>> rows = DB.select(
      'SELECT * FROM items WHERE scope = ? AND updated_at_ms > ? ORDER BY updated_at_ms ASC',
      <Object?>[scope, sinceMillis],
    );

    return [
      for (final Map<String, dynamic> row in rows) (data: row, mark: row['updated_at_ms'] as int),
    ];
  }

  @override
  Future<bool> adoptRow({
    required String account,
    required Map<String, dynamic> row,
  }) async {
    final int? remoteMark = Cast.intOrNull(row['updated_at_ms']);
    if (remoteMark == null) return false;

    final List<Map<String, dynamic>> existing = DB.select(
      'SELECT updated_at_ms FROM items WHERE id = ?',
      <Object?>[row['id']],
    );

    if (existing.isNotEmpty && (existing.single['updated_at_ms'] as int) >= remoteMark) {
      return false;
    }

    DB.statement(
      'INSERT OR REPLACE INTO items (id, scope, updated_at_ms, payload) VALUES (?, ?, ?, ?)',
      <Object?>[row['id'], row['scope'], remoteMark, row['payload']],
    );

    return true;
  }
}
```

`pending` answers rows oldest first, with `sinceMillis` as a strict lower bound: the push advances its mark to the last row of each batch, so a batch that did not end on its newest row would move the mark past rows it never sent. Each `SyncPushRow` is a record of the wire payload (`data`) and this device's own epoch millis for the row (`mark`); marks need not be unique.

`adoptRow` answers `true` when the row was newer than what the device held and `false` otherwise. A row this client cannot read answers `false` rather than throwing, so one bad row does not stop the rest of a page from landing. Use `Cast.intOrNull`, `doubleOrNull` and `boolOrNull` for wire values whose numeric type is not guaranteed (`int` against `double` on the web).

<a name="registering-the-ledger-table"></a>
## Registering the Ledger Table

`CreateSyncCursorsTable` creates the `sync_cursors` table the default `SyncLedger` uses. List it explicitly with the app's own migrations:

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> main() async {
  await Migrator().run([
    CreateSyncCursorsTable(),
  ]);
}
```

The table has five columns (`scope`, `feed`, `account`, `pull_cursor`, `push_mark`), no `id()`, no `timestamps()` and no unique index. `SyncLedger` upserts by delete-then-insert, so an app that already keeps a table of this shape passes `SyncLedger(table: 'my_cursors')` as the `ledger` argument of its feed's `super` constructor and skips the migration. An unknown `(scope, feed)` pair reads as no cursor and a zero mark, which asks for everything.

<a name="the-two-clock-rule"></a>
## The Two-Clock Rule

A run tracks two clocks and only one advances locally. The **push mark** is this device's own `updated_at` in epoch millis and decides which rows are worth sending next time. The **pull cursor** is the server's, opaque text handed back unread.

Only the push advances the mark. A row adopted from the server carries the originating device's clock, so moving this device's mark to it would step over a local row written earlier and never sent. The cost is small: an adopted row is echoed back once on the next run, where the server's own `>=` rejects it and the mark then covers it.

<a name="the-savepoint-note"></a>
## The Savepoint Note

`SyncLedger.write` issues its delete-then-insert inside a `SAVEPOINT` and `RELEASE`, not `DB.transaction`, because `BEGIN` does not nest and a feed may already run inside a caller's transaction. A savepoint opened inside a transaction joins it and rolls back with it. A caller whose outer transaction fails after the release therefore loses the bookmark write, and the next run resends a tail the server already absorbs: one extra round trip, never a duplicate write.

<a name="what-stays-app-side"></a>
## What Stays App-Side

The skeleton is narrow on purpose. Three things are the app's:

- **Scope.** An opaque string passed straight to the ledger and the wire calls; a team id or a workspace id.
- **Salt.** Any value mixed into local identifiers or cache keys beyond `scope` and `account`.
- **Orchestration.** When a feed runs (a timer, a reconnect, an app resume). `run` answers one call and never schedules itself.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| `pending` returning rows newest first | Order oldest first; the mark advances to the last row of each batch. |
| Advancing a mark from an adopted row | Never; only the push advances it. |
| Wrapping `run` in `try`/`catch` for failures | It never throws; read `SyncReport.failure`. |
| Forgetting `CreateSyncCursorsTable` | The first `run` throws inside the ledger and answers a failed report. List it in `Migrator().run`. |
| Running a feed with no network driver | `Http` has no driver; register `NetworkServiceProvider` first. |
| Throwing from `adoptRow` on a bad row | Answer `false`; one malformed row must not stop the page. |

<a name="related-documentation"></a>
## Related Documentation

- [Migrations](../basics/migrations.md): registering `CreateSyncCursorsTable`.
- [Queries](../basics/queries.md): `DB.select` and `DB.statement` for `pending` and `adoptRow`.
- [Testing](./testing.md): driving a feed against an in-memory database.
