/// SQLite local database layer for Magic apps.
///
/// [DatabaseServiceProvider] binds the [DatabaseManager] under `'db'` and the
/// [QueryModelStore] under `'local_model_store'`, which is what a `useLocal`
/// model persists through. The `DB` and `Schema` facades, [Migrator],
/// [Factory], [Seeder] and the sync skeleton ([SyncFeed], [SyncLedger]) sit on
/// that connection; `databaseConfig` is the config factory the manager reads.
library;

export 'config/database.dart';
export 'src/database/database_manager.dart';
export 'src/database/database_service_provider.dart';
export 'src/database/migrations/migration.dart';
export 'src/database/migrations/migrator.dart';
export 'src/database/query/query_builder.dart';
export 'src/database/query_model_store.dart';
export 'src/database/schema/blueprint.dart';
export 'src/database/seeding/factory.dart';
export 'src/database/seeding/seeder.dart';
export 'src/database/seeding/seeding.dart';
export 'src/facades/db.dart';
export 'src/facades/schema.dart';
export 'src/sync/create_sync_cursors_table.dart';
export 'src/sync/sync_feed.dart';
export 'src/sync/sync_ledger.dart';
