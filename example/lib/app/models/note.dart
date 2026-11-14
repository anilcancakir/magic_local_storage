import 'package:magic/magic.dart';

/// A note stored in the local SQLite `notes` table.
///
/// `useLocal` routes every persistence call through the `LocalModelStore`
/// that `DatabaseServiceProvider` binds, and `useRemote` stays off, so no
/// HTTP call is made.
class Note extends Model with HasTimestamps, InteractsWithPersistence {
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

  static Future<List<Note>> all() =>
      InteractsWithPersistence.allModels<Note>(Note.new);
}
