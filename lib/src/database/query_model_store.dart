import 'package:magic/magic.dart';

import 'database_manager.dart';
import 'query/query_builder.dart';

/// The SQLite [LocalModelStore], backed by [QueryBuilder] over the
/// [DatabaseManager] SQLite connection.
///
/// `DatabaseServiceProvider` binds it to `'local_model_store'`. Writes keep only
/// the attributes the table has a column for, so a model may carry computed or
/// remote-only attributes without breaking the insert.
class QueryModelStore implements LocalModelStore {
  @override
  Future<Map<String, dynamic>?> find(
    String table,
    String primaryKey,
    dynamic id,
  ) {
    return QueryBuilder(table).where(primaryKey, id).first();
  }

  @override
  Future<List<Map<String, dynamic>>> all(String table) {
    return QueryBuilder(table).get();
  }

  @override
  Future<dynamic> insert(String table, Map<String, dynamic> data) async {
    return QueryBuilder(table).insert(await _onlyTableColumns(table, data));
  }

  @override
  Future<void> update(
    String table,
    String primaryKey,
    dynamic id,
    Map<String, dynamic> data,
  ) async {
    await QueryBuilder(table)
        .where(primaryKey, id)
        .update(await _onlyTableColumns(table, data));
  }

  @override
  Future<void> delete(String table, String primaryKey, dynamic id) async {
    await QueryBuilder(table).where(primaryKey, id).delete();
  }

  @override
  Future<void> upsert(
    String table,
    String primaryKey,
    dynamic id,
    Map<String, dynamic> data,
  ) async {
    if (await find(table, primaryKey, id) != null) {
      await update(table, primaryKey, id, data);

      return;
    }

    await insert(table, data);
  }

  Future<Map<String, dynamic>> _onlyTableColumns(
    String table,
    Map<String, dynamic> data,
  ) async {
    final DatabaseManager db = DatabaseManager();
    if (!db.isInitialized) {
      await db.init();
    }

    final List<String> columns = await db.getColumns(table);

    return {
      for (final MapEntry<String, dynamic> entry in data.entries)
        if (columns.contains(entry.key)) entry.key: entry.value,
    };
  }
}

/// Direct [QueryBuilder] access to a model's table.
extension ModelQuery on Model {
  /// A query builder over this model's [Model.table].
  QueryBuilder query() => QueryBuilder(table);
}
