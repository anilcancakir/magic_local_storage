import 'package:magic/magic.dart';

import 'database_manager.dart';
import 'query_model_store.dart';

/// Database Service Provider.
///
/// Registers the database manager as a singleton in the service container.
/// The database is initialized automatically during the boot phase.
class DatabaseServiceProvider extends ServiceProvider {
  /// Create a new database service provider.
  DatabaseServiceProvider(super.app);

  @override
  void register() {
    // Register the database manager as a singleton
    app.singleton('db', () => DatabaseManager());
    app.singleton('local_model_store', () => QueryModelStore());
  }

  @override
  Future<void> boot() async {
    // Initialize the database connection
    final db = app.make<DatabaseManager>('db');
    await db.init();

    final dbConfig = Config.get<Map<String, dynamic>>('database', {});
    final defaultConnection = dbConfig?['default'] ?? 'sqlite';

    Log.info('Database ready [$defaultConnection]');
  }
}
