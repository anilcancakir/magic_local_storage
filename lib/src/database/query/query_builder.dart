import 'dart:convert';

import 'package:magic/magic.dart';
import 'package:sqlite3/common.dart';

import '../database_manager.dart';
import 'identifier.dart';

/// Laravel-style Query Builder.
///
/// Provides a fluent API for building and executing SQL queries. The builder
/// is schema-aware and will automatically filter insert/update data to only
/// include columns that exist in the table.
///
/// ## Getting Started
///
/// ```dart
/// // Get all users
/// final users = await DB.table('users').get();
///
/// // Get first user matching condition
/// final user = await DB.table('users').where('id', 1).first();
/// ```
///
/// ## Selecting Data
///
/// ```dart
/// // Select specific columns
/// final names = await DB.table('users')
///   .select(['name', 'email'])
///   .get();
///
/// // With conditions
/// final activeUsers = await DB.table('users')
///   .where('is_active', true)
///   .where('role', 'admin')
///   .get();
///
/// // With ordering and limits
/// final recent = await DB.table('posts')
///   .orderBy('created_at', 'desc')
///   .limit(10)
///   .get();
/// ```
///
/// ## Inserting Data
///
/// ```dart
/// // Insert single record
/// await DB.table('users').insert({
///   'name': 'John Doe',
///   'email': 'john@example.com',
/// });
///
/// // Schema-aware: unknown columns are automatically filtered out
/// await DB.table('users').insert({
///   'name': 'Jane',
///   'unknown_field': 'ignored', // Won't cause error
/// });
/// ```
///
/// ## Updating Data
///
/// ```dart
/// await DB.table('users')
///   .where('id', 1)
///   .update({'name': 'Updated Name'});
/// ```
///
/// ## Deleting Data
///
/// ```dart
/// await DB.table('users')
///   .where('id', 1)
///   .delete();
/// ```
class QueryBuilder {
  /// Marks the absent third argument of [where], so a `null` value is told
  /// apart from the two-argument form.
  static const Object _noValue = Object();

  /// The operators [where] writes into the SQL, in lower case.
  static const Set<String> _operators = {
    '=',
    '==',
    '!=',
    '<>',
    '<',
    '<=',
    '>',
    '>=',
    'like',
    'not like',
    'glob',
    'not glob',
    'match',
    'is',
    'is not',
  };

  /// The table name.
  final String _table;

  /// Selected columns (null means all).
  List<String>? _selectColumns;

  /// Where clauses.
  final List<_WhereClause> _wheres = [];

  /// Order by clauses.
  final List<_OrderClause> _orders = [];

  /// Limit value.
  int? _limitValue;

  /// Offset value.
  int? _offsetValue;

  /// Create a new query builder for a table.
  QueryBuilder(this._table);

  /// Get the database manager.
  DatabaseManager get _db => DatabaseManager();

  /// Select specific columns.
  ///
  /// Each entry is a raw SQL fragment written into the `SELECT` list as given,
  /// so an expression such as `COUNT(*) AS total` works and a keyword column
  /// has to be quoted by hand (`'"order"'`), or read through [value] or
  /// [pluck]. Never pass user input here.
  ///
  /// ```dart
  /// DB.table('users').select(['name', 'email']).get();
  /// ```
  QueryBuilder select(List<String> columns) {
    _selectColumns = columns;
    return this;
  }

  /// Add a where clause.
  ///
  /// A plain [column] (`order`, `users.id`) is quoted as an identifier; any
  /// other text, such as `lower(email)`, is written as given. The value is
  /// bound. The operator is one of `=`, `==`, `!=`, `<>`, `<`, `<=`, `>`,
  /// `>=`, `like`, `not like`, `glob`, `not glob`, `match`, `is` and
  /// `is not`, in any case. A `null` value compiles to `IS NULL` for `=`, `==`
  /// and `is`, and to `IS NOT NULL` for `!=`, `<>` and `is not`.
  ///
  /// Throws an [ArgumentError] for any other operator, or for `null` with any
  /// other operator.
  ///
  /// ```dart
  /// // Equality
  /// DB.table('users').where('id', 1);
  ///
  /// // With operator
  /// DB.table('users').where('age', '>=', 18);
  /// ```
  QueryBuilder where(
    String column,
    dynamic operatorOrValue, [
    dynamic value = _noValue,
  ]) {
    // 1. Two arguments mean equality; count them rather than test for null,
    //    so `where(column, '=', null)` keeps its operator.
    if (identical(value, _noValue)) {
      return where(column, '=', operatorOrValue);
    }

    // 2. Only a known operator reaches the SQL text.
    final String operator = _normalizeOperator(operatorOrValue);

    // 3. A null value never matches through `= ?`; route it to IS [NOT] NULL.
    if (value == null) {
      return switch (operator) {
        '=' || '==' || 'is' => whereNull(column),
        '!=' || '<>' || 'is not' => whereNotNull(column),
        _ => throw ArgumentError.value(
          value,
          'value',
          'Operator "$operator" cannot compare with null',
        ),
      };
    }

    _wheres.add(_WhereClause(column, operator, value));
    return this;
  }

  /// Add a where null clause.
  ///
  /// ```dart
  /// DB.table('users').whereNull('deleted_at');
  /// ```
  QueryBuilder whereNull(String column) {
    _wheres.add(_WhereClause(column, 'IS', null, isNull: true));
    return this;
  }

  /// Add a where not null clause.
  ///
  /// ```dart
  /// DB.table('users').whereNotNull('email');
  /// ```
  QueryBuilder whereNotNull(String column) {
    _wheres.add(_WhereClause(column, 'IS NOT', null, isNull: true));
    return this;
  }

  /// Add an order by clause.
  ///
  /// A plain [column] is quoted as an identifier; an expression such as
  /// `name COLLATE NOCASE` or `RANDOM()` is written as given. Throws an
  /// [ArgumentError] when [direction] is not `asc` or `desc`, in any case.
  ///
  /// ```dart
  /// DB.table('posts').orderBy('created_at', 'desc');
  /// ```
  QueryBuilder orderBy(String column, [String direction = 'asc']) {
    final String normalized = direction.toUpperCase();
    if (normalized != 'ASC' && normalized != 'DESC') {
      throw ArgumentError.value(
        direction,
        'direction',
        'Order direction must be "asc" or "desc"',
      );
    }

    _orders.add(_OrderClause(column, normalized));
    return this;
  }

  /// Limit the number of results.
  ///
  /// ```dart
  /// DB.table('posts').limit(10);
  /// ```
  QueryBuilder limit(int count) {
    _limitValue = count;
    return this;
  }

  /// Offset the results.
  ///
  /// ```dart
  /// DB.table('posts').limit(10).offset(20); // Page 3
  /// ```
  QueryBuilder offset(int count) {
    _offsetValue = count;
    return this;
  }

  /// Execute the query and get all results.
  ///
  /// ```dart
  /// final users = await DB.table('users').get();
  /// for (final user in users) {
  ///   print(user['name']);
  /// }
  /// ```
  Future<List<Map<String, dynamic>>> get() async {
    final sql = _buildSelectSql();
    final params = _buildWhereParams();

    final ResultSet result = _db.connection.select(sql, params);
    return _resultSetToList(result);
  }

  /// Get the first result.
  ///
  /// ```dart
  /// final user = await DB.table('users').where('id', 1).first();
  /// if (user != null) {
  ///   print(user['name']);
  /// }
  /// ```
  Future<Map<String, dynamic>?> first() async {
    _limitValue = 1;
    final results = await get();
    return results.isEmpty ? null : results.first;
  }

  /// Get a single value from the first result.
  ///
  /// A plain [column] is quoted, so a keyword column such as `order` works;
  /// an expression is selected as given.
  ///
  /// ```dart
  /// final name = await DB.table('users')
  ///   .where('id', 1)
  ///   .value<String>('name');
  /// ```
  Future<T?> value<T>(String column) async {
    _selectColumns = [wrapIdentifier(column)];
    final row = await first();
    return row?[resultKey(column)] as T?;
  }

  /// Get a list of values for a single column.
  ///
  /// A plain [column] is quoted, so a keyword column such as `order` works;
  /// an expression is selected as given.
  ///
  /// ```dart
  /// final emails = await DB.table('users').pluck<String>('email');
  /// ```
  Future<List<T>> pluck<T>(String column) async {
    _selectColumns = [wrapIdentifier(column)];
    final results = await get();
    final String key = resultKey(column);
    return results.map((row) => row[key] as T).toList();
  }

  /// Count the number of matching rows.
  ///
  /// ```dart
  /// final count = await DB.table('users').where('is_active', true).count();
  /// ```
  Future<int> count() async {
    final sql = _buildCountSql();
    final params = _buildWhereParams();
    final result = _db.connection.select(sql, params);
    return result.first['count'] as int;
  }

  /// Check if any rows exist matching the query.
  ///
  /// ```dart
  /// if (await DB.table('users').where('email', email).exists()) {
  ///   throw Exception('Email already in use');
  /// }
  /// ```
  Future<bool> exists() async {
    return await count() > 0;
  }

  /// Insert a new record (schema-aware).
  ///
  /// Unknown columns are automatically filtered out to prevent errors when
  /// the API returns fields that don't exist in the local database.
  ///
  /// ```dart
  /// await DB.table('users').insert({
  ///   'name': 'John',
  ///   'email': 'john@example.com',
  /// });
  /// ```
  Future<int> insert(Map<String, dynamic> data) async {
    // Filter data to only include existing columns
    final filteredData = await _filterDataBySchema(data);

    if (filteredData.isEmpty) {
      return 0;
    }

    final columns = filteredData.keys.map(quoteIdentifier).join(', ');
    final placeholders = List.filled(filteredData.length, '?').join(', ');
    final values = filteredData.values.toList();

    final sql = 'INSERT INTO $_wrappedTable ($columns) VALUES ($placeholders)';
    _db.connection.execute(sql, _prepareValues(values));

    // Return last insert ID
    final result = _db.connection.select('SELECT last_insert_rowid() as id');
    return result.first['id'] as int;
  }

  /// Insert multiple records.
  ///
  /// ```dart
  /// await DB.table('users').insertAll([
  ///   {'name': 'John', 'email': 'john@example.com'},
  ///   {'name': 'Jane', 'email': 'jane@example.com'},
  /// ]);
  /// ```
  Future<void> insertAll(List<Map<String, dynamic>> records) async {
    for (final record in records) {
      await insert(record);
    }
  }

  /// Update records matching the query (schema-aware).
  ///
  /// ```dart
  /// await DB.table('users')
  ///   .where('id', 1)
  ///   .update({'name': 'Updated Name'});
  /// ```
  Future<int> update(Map<String, dynamic> data) async {
    // Filter data to only include existing columns
    final filteredData = await _filterDataBySchema(data);

    if (filteredData.isEmpty) {
      return 0;
    }

    final setClauses = filteredData.keys
        .map((col) => '${quoteIdentifier(col)} = ?')
        .join(', ');
    final values = filteredData.values.toList();

    final whereSql = _buildWhereSql();
    final whereParams = _buildWhereParams();

    final sql = 'UPDATE $_wrappedTable SET $setClauses$whereSql';
    _db.connection.execute(sql, [..._prepareValues(values), ...whereParams]);

    // Return affected rows
    final result = _db.connection.select('SELECT changes() as count');
    return result.first['count'] as int;
  }

  /// Delete records matching the query.
  ///
  /// ```dart
  /// await DB.table('users').where('id', 1).delete();
  /// ```
  Future<int> delete() async {
    final whereSql = _buildWhereSql();
    final whereParams = _buildWhereParams();

    final sql = 'DELETE FROM $_wrappedTable$whereSql';
    _db.connection.execute(sql, whereParams);

    // Return affected rows
    final result = _db.connection.select('SELECT changes() as count');
    return result.first['count'] as int;
  }

  /// Truncate the table (delete all rows).
  ///
  /// ```dart
  /// await DB.table('logs').truncate();
  /// ```
  Future<void> truncate() async {
    _db.connection.execute('DELETE FROM $_wrappedTable');
  }

  // ---------------------------------------------------------------------------
  // Private Helpers
  // ---------------------------------------------------------------------------

  /// The table name, quoted when it is a plain name.
  String get _wrappedTable => wrapIdentifier(_table);

  /// Lower-cases [operator] and checks it against [_operators].
  String _normalizeOperator(dynamic operator) {
    final String? normalized = operator is String
        ? operator.toLowerCase()
        : null;
    if (normalized == null || !_operators.contains(normalized)) {
      throw ArgumentError.value(
        operator,
        'operator',
        'Unsupported where operator; use one of ${_operators.join(', ')}',
      );
    }

    return normalized;
  }

  /// Build the SELECT SQL statement. The select list stays raw, see [select].
  String _buildSelectSql() {
    final columns = _selectColumns?.join(', ') ?? '*';
    final buffer = StringBuffer('SELECT $columns FROM $_wrappedTable');

    buffer.write(_buildWhereSql());
    buffer.write(_buildOrderSql());
    buffer.write(_buildLimitSql());

    return buffer.toString();
  }

  /// Build the COUNT SQL statement.
  String _buildCountSql() {
    final buffer = StringBuffer('SELECT COUNT(*) as count FROM $_wrappedTable');
    buffer.write(_buildWhereSql());
    return buffer.toString();
  }

  /// Build the WHERE clause.
  String _buildWhereSql() {
    if (_wheres.isEmpty) return '';

    final clauses = _wheres
        .map((w) {
          final String column = wrapIdentifier(w.column);
          if (w.isNull) {
            return '$column ${w.operator} NULL';
          }
          return '$column ${w.operator} ?';
        })
        .join(' AND ');

    return ' WHERE $clauses';
  }

  /// Get the WHERE parameter values.
  List<Object?> _buildWhereParams() {
    return _wheres
        .where((w) => !w.isNull)
        .map((w) => _prepareValue(w.value))
        .toList();
  }

  /// Build the ORDER BY clause.
  String _buildOrderSql() {
    if (_orders.isEmpty) return '';
    final clauses = _orders
        .map((o) => '${wrapIdentifier(o.column)} ${o.direction}')
        .join(', ');
    return ' ORDER BY $clauses';
  }

  /// Build the LIMIT/OFFSET clause.
  String _buildLimitSql() {
    final buffer = StringBuffer();
    if (_limitValue != null) {
      buffer.write(' LIMIT $_limitValue');
    }
    if (_offsetValue != null) {
      buffer.write(' OFFSET $_offsetValue');
    }
    return buffer.toString();
  }

  /// Filter data map to only include columns that exist in the table.
  ///
  /// Throws a [StateError] naming the table when it has no columns, which is
  /// a table that does not exist yet: answering an empty map there would let
  /// a write to it report success.
  Future<Map<String, dynamic>> _filterDataBySchema(
    Map<String, dynamic> data,
  ) async {
    final columns = await _db.getColumns(_table);
    if (columns.isEmpty) {
      throw StateError(
        'Table "$_table" does not exist. Run the migration that creates it '
        '(Migrator().run) before writing to it.',
      );
    }

    final filtered = <String, dynamic>{};

    for (final entry in data.entries) {
      if (columns.contains(entry.key)) {
        filtered[entry.key] = entry.value;
      }
    }

    return filtered;
  }

  /// Convert ResultSet to List of Maps.
  List<Map<String, dynamic>> _resultSetToList(ResultSet result) {
    return result.map((row) {
      final map = <String, dynamic>{};
      for (final col in result.columnNames) {
        map[col] = row[col];
      }
      return map;
    }).toList();
  }

  /// Prepare a value for SQLite (convert booleans, etc.).
  Object? _prepareValue(dynamic value) {
    if (value is bool) {
      return value ? 1 : 0;
    }
    if (value is Carbon) {
      return value.toIso8601String();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Map || value is List) {
      return jsonEncode(value);
    }
    return value;
  }

  /// Prepare multiple values.
  List<Object?> _prepareValues(List<dynamic> values) {
    return values.map(_prepareValue).toList();
  }
}

/// Internal where clause representation.
class _WhereClause {
  final String column;
  final String operator;
  final dynamic value;
  final bool isNull;

  _WhereClause(this.column, this.operator, this.value, {this.isNull = false});
}

/// Internal order clause representation.
class _OrderClause {
  final String column;
  final String direction;

  _OrderClause(this.column, this.direction);
}
