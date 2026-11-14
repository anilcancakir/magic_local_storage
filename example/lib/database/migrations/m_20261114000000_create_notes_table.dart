import 'package:magic_local_storage/magic_local_storage.dart';

/// Creates the `notes` table the [Note] model persists to.
class CreateNotesTable extends Migration {
  @override
  String get name => '20261114000000_create_notes_table';

  @override
  void up() {
    Schema.create('notes', (Blueprint table) {
      table.id();
      table.string('title');
      table.timestamps();
    });
  }

  @override
  void down() {
    Schema.dropIfExists('notes');
  }
}
