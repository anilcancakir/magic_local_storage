import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

/// Pins that the sync skeleton reaches a consumer through
/// `package:magic_local_storage/magic_local_storage.dart` alone.
void main() {
  setUp(() {
    MagicApp.reset();
    Magic.flush();
  });

  test(
    'SyncFeed, SyncLedger, CreateSyncCursorsTable resolve through the barrel',
    () {
      expect(SyncFeed, isNotNull);
      expect(const SyncLedger(), isNotNull);
      expect(CreateSyncCursorsTable(), isNotNull);

      final report = SyncReport(pushed: 1, adopted: 2);
      expect(report.complete, isTrue);
    },
  );
}
