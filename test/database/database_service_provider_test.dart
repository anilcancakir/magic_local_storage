import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';
import 'package:sqlite3/sqlite3.dart';

class _Note extends Model with InteractsWithPersistence {
  @override
  String get table => 'notes';

  @override
  String get resource => 'notes';

  @override
  List<String> get fillable => ['title'];

  @override
  bool get useLocal => true;

  @override
  bool get useRemote => false;

  String? get title => getAttribute('title') as String?;

  static Future<_Note?> find(dynamic id) =>
      InteractsWithPersistence.findById<_Note>(id, _Note.new);
}

void main() {
  setUp(() {
    MagicApp.reset();
    Magic.flush();
    Log.fake();
  });

  tearDown(() {
    DatabaseManager().dispose();
  });

  group('DatabaseServiceProvider.register', () {
    test('binds the database manager under "db"', () {
      final MagicApp app = MagicApp.instance;

      DatabaseServiceProvider(app).register();

      expect(app.make<DatabaseManager>('db'), same(DatabaseManager()));
    });

    test('binds the query model store under "local_model_store"', () {
      final MagicApp app = MagicApp.instance;

      DatabaseServiceProvider(app).register();

      expect(
        app.make<LocalModelStore>('local_model_store'),
        isA<QueryModelStore>(),
      );
    });
  });

  group('DatabaseServiceProvider.boot', () {
    test('a useLocal model saves and reads back through the store', () async {
      final MagicApp app = MagicApp.instance;
      final Database db = sqlite3.openInMemory();
      db.execute(
        'CREATE TABLE notes (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT)',
      );
      DatabaseManager().setConnection(db);

      final DatabaseServiceProvider provider = DatabaseServiceProvider(app);
      provider.register();
      await provider.boot();

      final _Note note = _Note()..fill({'title': 'Buy milk'});
      expect(await note.save(), isTrue);

      final _Note? found = await _Note.find(note.id);
      expect(found, isNotNull);
      expect(found!.title, 'Buy milk');
    });
  });

  group('databaseConfig', () {
    test('defaults to the sqlite connection on magic_app.db', () {
      final Map<String, dynamic> database =
          databaseConfig['database'] as Map<String, dynamic>;

      expect(database['default'], 'sqlite');
      expect((database['connections'] as Map<String, dynamic>)['sqlite'], {
        'driver': 'sqlite',
        'database': 'magic_app.db',
        'prefix': '',
      });
    });
  });
}
