import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

import 'app/models/note.dart';
import 'database/migrations/m_20261114000000_create_notes_table.dart';

const Color _ink = Color(0xFF111827);
const Color _accent = Color(0xFF4F46E5);
const TextStyle _text = TextStyle(color: _ink, fontSize: 16);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    // `databaseConfig` opens `magic_app.db` on the `sqlite` connection.
    configFactories: [() => databaseConfig],
    configs: [
      {
        'app': {
          'providers': [(app) => DatabaseServiceProvider(app)],
        },
      },
    ],
  );

  // Migrations run after boot, once the connection is open. The migrator keeps
  // a ledger, so a second launch applies nothing.
  await Migrator().run([CreateNotesTable()]);

  runApp(const ExampleApp());
}

/// One local table, one model and a button that saves a row.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'magic_local_storage example',
      color: _accent,
      textStyle: _text,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) {
        return PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        );
      },
      home: const NotesPage(),
    );
  }
}

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  List<Note> _notes = <Note>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Note> notes = await Note.all();
    if (!mounted) return;

    setState(() => _notes = notes);
  }

  Future<void> _add() async {
    final Note note = Note()..fill({'title': 'Note ${_notes.length + 1}'});
    await note.save();

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_notes.length} note(s) in the local database',
              style: _text,
            ),
            const SizedBox(height: 16),
            Row(
              children: [_Button(label: 'Add note', onTap: _add)],
            ),
            const SizedBox(height: 16),
            Text(
              _notes.isEmpty
                  ? 'No notes yet.'
                  : _notes
                        .map((Note note) => '#${note.id} ${note.title}')
                        .join('\n'),
              style: _text,
            ),
          ],
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: _accent,
        child: Text(label, style: const TextStyle(color: Color(0xFFFFFFFF))),
      ),
    );
  }
}
