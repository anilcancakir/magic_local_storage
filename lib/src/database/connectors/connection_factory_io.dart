import 'dart:io';

import 'package:magic/magic.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'connection_factory_contract.dart';

/// Native Connection Factory (IO).
///
/// This factory creates SQLite database connections for native platforms
/// (Android, iOS, macOS, Linux, Windows) using the FFI-based sqlite3 package.
///
/// ## File Location
///
/// The database file is stored in the directory `MagicPaths.appData()` names:
/// the application's documents directory, which is persistent across app
/// restarts and updates, or `app_data` under the cache directory on tvOS, where
/// the system may purge it when storage runs low.
///
/// ## Example
///
/// ```dart
/// final factory = ConnectionFactory();
/// final db = await factory.connect({'database': 'my_app.db'});
/// ```
class ConnectionFactory implements ConnectionFactoryContract {
  @override
  Future<Database> connect(Map<String, dynamic> config) async {
    final dbName = config['database'] as String? ?? 'magic_app.db';

    // Documents everywhere except tvOS, where an Apple TV denies writes to it.
    final Directory appDir = await MagicPaths.appData();

    // Resolve the full database path
    final String dbPath = p.join(appDir.path, dbName);

    // Open the database. A double-quoted name must stay an identifier, so a
    // mistyped quoted column fails with "no such column" instead of being
    // compared as a string literal.
    final Database db = sqlite3.open(dbPath);
    db.config.doubleQuotedStringLiterals = false;

    return db;
  }
}
