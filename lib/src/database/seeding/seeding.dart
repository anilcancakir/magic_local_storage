import 'package:magic/magic.dart';

import 'seeder.dart';

/// Entry point for seeding the local database from app code.
///
/// ```dart
/// await Magic.init(...);
///
/// if (kDebugMode) {
///   await Seeding.run([DatabaseSeeder()]);
/// }
/// ```
class Seeding {
  Seeding._();

  /// Run [seeders] one after another, each awaited before the next starts.
  ///
  /// A seeder that throws stops the run and the error propagates; the
  /// seeders after it do not run.
  static Future<void> run(List<Seeder> seeders) async {
    Log.info('Starting database seeding...');
    for (final Seeder seeder in seeders) {
      await seeder.run();
    }
    Log.info('Database seeding complete');
  }
}
