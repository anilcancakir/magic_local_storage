import 'package:dowel/dowel.dart';

import '../local_storage_stub_loader.dart';
import 'refuses_unsafe_names.dart';

/// The Make Migration Command.
///
/// Scaffolds a new timestamped migration file inside `lib/database/migrations/`
/// using the `migration.create` stub (when `--create` is passed) or the plain
/// `migration` stub otherwise.
///
/// ## Usage
///
/// ```bash
/// dowel make:migration create_users_table
/// dowel make:migration create_users_table --create=users
/// dowel make:migration add_email_to_users --table=users
/// ```
///
/// ## Output
///
/// Creates a file named `m_YYYYMMDDHHMMSS_{name}.dart` in
/// `lib/database/migrations/`.
class MakeMigrationCommand extends DowelGeneratorCommand
    with RefusesUnsafeNames {
  final String? _testRoot;

  /// Captures `--create` parsed at [handle] time so [getStub] and
  /// [getReplacements] can read it without an [DowelContext].
  String? _createOption;

  /// Captures `--table` parsed at [handle] time.
  String? _tableOption;

  MakeMigrationCommand({this._testRoot});

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  String getProjectRoot() => _testRoot ?? super.getProjectRoot();

  @override
  String get name => 'make:migration';

  @override
  String get description => 'Create a new migration file';

  @override
  String getDefaultNamespace() => 'lib/database/migrations';

  /// Adds the `--create` and `--table` options on top of the inherited
  /// `--force` flag registered by [DowelGeneratorCommand.configure].
  @override
  void configure(ArgParser parser) {
    super.configure(parser);
    parser.addOption(
      'create',
      abbr: 'c',
      help: 'The table to be created (selects the create stub)',
    );
    parser.addOption('table', abbr: 't', help: 'The table to migrate');
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    // 1. Capture options BEFORE delegating to the generic handler so that
    //    [getStub] and [getReplacements] (called downstream) see them.
    _createOption = ctx.input.option('create') as String?;
    _tableOption = ctx.input.option('table') as String?;
    return super.handle(ctx);
  }

  /// Selects the create stub when `--create` is supplied, plain stub otherwise.
  @override
  String getStub() => LocalStorageStubLoader.load(
    _createOption != null ? 'migration.create' : 'migration',
  );

  /// Migration filenames carry a timestamp prefix: `m_YYYYMMDDHHMMSS_{name}.dart`.
  /// This overrides [DowelGeneratorCommand.getPath] to inject that prefix.
  @override
  String getPath(String name) {
    final parsed = StringHelper.parseName(name);
    final projectRoot = getProjectRoot();
    final namespace = getDefaultNamespace();

    // 1. Build the timestamp-prefixed filename.
    final timestamp = _buildTimestamp();
    final snakeName = StringHelper.toSnakeCase(parsed.className);
    final fileName = 'm_${timestamp}_$snakeName.dart';

    // 2. Respect nested directory if the user passed a slash-separated path.
    return <String>[
      projectRoot,
      namespace,
      if (parsed.directory.isNotEmpty) parsed.directory,
      fileName,
    ].join('/');
  }

  /// Override the stub build so the parent's `_replaceClass` does not write
  /// the raw user-supplied name into `{{ className }}`. The migration's
  /// timestamped, PascalCased class identifier is supplied via
  /// [getReplacements].
  ///
  /// Strategy: pre-PascalCase the name segment so the parent's internal
  /// substitution writes a valid Dart identifier even when [getReplacements]
  /// is not consulted (defensive: `{{ className }}` is replaced again here).
  @override
  String buildClass(String name) {
    final parsed = StringHelper.parseName(name);
    final pascalSnake = StringHelper.toPascalCase(
      StringHelper.toSnakeCase(parsed.className),
    );
    final transformed = parsed.directory.isEmpty
        ? pascalSnake
        : '${parsed.directory}/$pascalSnake';
    return super.buildClass(transformed);
  }

  /// Provides placeholder replacements for the migration stub.
  ///
  /// - `{{ className }}`: timestamped PascalCase class identifier.
  /// - `{{ fullName }}`: snake_case timestamp+name (used as migration `name`).
  /// - `{{ tableName }}`: the target table name (from `--create`, `--table`,
  ///   or derived from the migration name).
  @override
  Map<String, String> getReplacements(String name) {
    final timestamp = _buildTimestamp();
    final snakeName = StringHelper.toSnakeCase(
      StringHelper.parseName(name).className,
    );
    final fullName = '${timestamp}_$snakeName';

    // Derive table name: --create > --table > snake_name.
    final tableName = _createOption ?? _tableOption ?? snakeName;

    // PascalCase class name: uses only the migration name part (no timestamp)
    // to produce a valid Dart class identifier.
    final className = StringHelper.toPascalCase(snakeName);

    return {
      '{{ className }}': className,
      '{{ fullName }}': fullName,
      '{{ tableName }}': tableName,
    };
  }

  /// Produces a compact 14-digit timestamp string `YYYYMMDDHHmmss`.
  String _buildTimestamp() {
    final now = DateTime.now();
    return '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
  }
}
