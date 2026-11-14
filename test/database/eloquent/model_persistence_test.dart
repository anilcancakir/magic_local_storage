import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';
import 'package:sqlite3/sqlite3.dart';

/// A test model for unit testing the Eloquent ORM.
class TestUser extends Model with HasTimestamps, InteractsWithPersistence {
  @override
  String get table => 'test_users';

  @override
  String get resource => 'test_users';

  @override
  List<String> get fillable => ['name', 'email', 'born_at', 'settings'];

  @override
  Map<String, String> get casts => {'born_at': 'datetime', 'settings': 'json'};

  // Enable local, disable remote for tests
  @override
  bool get useLocal => true;

  @override
  bool get useRemote => false;

  // Typed accessors
  String? get name => getAttribute('name') as String?;
  set name(String? value) => setAttribute('name', value);

  String? get email => getAttribute('email') as String?;
  set email(String? value) => setAttribute('email', value);

  Carbon? get bornAt => getAttribute('born_at') as Carbon?;
  set bornAt(dynamic value) => setAttribute('born_at', value);

  Map<String, dynamic>? get settings =>
      getAttribute('settings') as Map<String, dynamic>?;
  set settings(Map<String, dynamic>? value) => setAttribute('settings', value);

  // Static helpers
  static Future<TestUser?> find(dynamic id) =>
      InteractsWithPersistence.findById<TestUser>(id, TestUser.new);

  static Future<List<TestUser>> all() =>
      InteractsWithPersistence.allModels<TestUser>(TestUser.new);
}

/// A model whose table no migration has created yet.
class PendingNote extends Model with InteractsWithPersistence {
  @override
  String get table => 'pending_notes';

  @override
  String get resource => 'pending_notes';

  @override
  List<String> get fillable => ['title'];

  @override
  bool get useLocal => true;

  @override
  bool get useRemote => false;
}

void main() {
  group('InteractsWithPersistence', () {
    late Database db;

    setUp(() {
      MagicApp.reset();
      Magic.flush();

      // Use in-memory database for testing
      db = sqlite3.openInMemory();
      DatabaseManager().setConnection(db);
      MagicApp.instance.singleton('local_model_store', () => QueryModelStore());

      // Create test table
      db.execute('''
        CREATE TABLE test_users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT,
          born_at TEXT,
          settings TEXT,
          created_at TEXT,
          updated_at TEXT
        )
      ''');
    });

    tearDown(() {
      DatabaseManager().dispose();
    });

    test('save inserts new model', () async {
      final user = TestUser()
        ..fill({'name': 'New User', 'email': 'new@example.com'});

      final result = await user.save();

      expect(result, isTrue);
      expect(user.exists, isTrue);
      expect(user.id, isNotNull);
    });

    test('save updates existing model', () async {
      // Insert directly
      db.execute(
        "INSERT INTO test_users (name, email) VALUES ('Original', 'orig@test.com')",
      );

      final user = await TestUser.find(1);
      expect(user, isNotNull);
      expect(user!.name, 'Original');

      user.name = 'Updated';
      await user.save();

      // Verify update
      final updated = await TestUser.find(1);
      expect(updated!.name, 'Updated');
    });

    test('find returns model by id', () async {
      db.execute(
        "INSERT INTO test_users (name, email) VALUES ('Test', 'test@example.com')",
      );

      final user = await TestUser.find(1);

      expect(user, isNotNull);
      expect(user!.name, 'Test');
      expect(user.email, 'test@example.com');
      expect(user.exists, isTrue);
    });

    test('find returns null for non-existent id', () async {
      final user = await TestUser.find(999);
      expect(user, isNull);
    });

    test('all returns all models', () async {
      db.execute(
        "INSERT INTO test_users (name, email) VALUES ('User 1', 'u1@test.com')",
      );
      db.execute(
        "INSERT INTO test_users (name, email) VALUES ('User 2', 'u2@test.com')",
      );

      final users = await TestUser.all();

      expect(users.length, 2);
      expect(users[0].name, 'User 1');
      expect(users[1].name, 'User 2');
    });

    test('delete removes model', () async {
      db.execute(
        "INSERT INTO test_users (name, email) VALUES ('ToDelete', 'del@test.com')",
      );

      final user = await TestUser.find(1);
      expect(user, isNotNull);

      final result = await user!.delete();
      expect(result, isTrue);
      expect(user.exists, isFalse);

      // Verify deletion
      final deleted = await TestUser.find(1);
      expect(deleted, isNull);
    });

    test('refresh reloads model from database', () async {
      db.execute(
        "INSERT INTO test_users (name, email) VALUES ('Original', 'orig@test.com')",
      );

      final user = await TestUser.find(1);
      expect(user!.name, 'Original');

      // Update directly in DB
      db.execute("UPDATE test_users SET name = 'Updated' WHERE id = 1");

      // Refresh
      await user.refresh();
      expect(user.name, 'Updated');
    });

    test(
      'save before the migration ran fails, and succeeds after it',
      () async {
        final early = PendingNote()..fill({'title': 'Too early'});

        expect(await early.save(), isFalse);
        expect(early.exists, isFalse);
        expect(early.id, isNull);

        // A raw CREATE TABLE does not clear the schema cache, so this also
        // proves the failed save left no empty column list cached.
        db.execute(
          'CREATE TABLE pending_notes (id INTEGER PRIMARY KEY, title TEXT)',
        );
        final note = PendingNote()..fill({'title': 'After the migration'});

        expect(await note.save(), isTrue);
        expect(note.id, 1);
        expect(
          db.select('SELECT title FROM pending_notes').first['title'],
          'After the migration',
        );
      },
    );
  });
}
