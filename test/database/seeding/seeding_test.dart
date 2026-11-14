import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

void main() {
  setUp(() {
    MagicApp.reset();
    Magic.flush();
    Log.fake();
  });

  group('Seeding.run', () {
    test('runs every seeder once, in the order given', () async {
      final List<String> calls = [];

      await Seeding.run([
        _RecordingSeeder('users', calls),
        _RecordingSeeder('posts', calls),
        _RecordingSeeder('comments', calls),
      ]);

      expect(calls, ['users', 'posts', 'comments']);
    });

    test('waits for each seeder before starting the next', () async {
      final List<String> calls = [];

      await Seeding.run([
        _RecordingSeeder(
          'slow',
          calls,
          delay: const Duration(milliseconds: 20),
        ),
        _RecordingSeeder('fast', calls),
      ]);

      expect(calls, ['slow', 'fast']);
    });

    test('propagates a failing seeder and skips the rest', () async {
      final List<String> calls = [];

      await expectLater(
        Seeding.run([_FailingSeeder(), _RecordingSeeder('never', calls)]),
        throwsStateError,
      );
      expect(calls, isEmpty);
    });
  });
}

class _RecordingSeeder extends Seeder {
  _RecordingSeeder(this.name, this.calls, {this.delay = Duration.zero});

  final String name;
  final List<String> calls;
  final Duration delay;

  @override
  Future<void> run() async {
    await Future<void>.delayed(delay);
    calls.add(name);
  }
}

class _FailingSeeder extends Seeder {
  @override
  Future<void> run() async {
    throw StateError('seed failed');
  }
}
