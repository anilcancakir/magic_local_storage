import 'dart:io';
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:dowel/dowel.dart';

import '../local_storage_stub_loader.dart';

/// `local_storage:install`: registers the database layer and readies a web
/// project for SQLite.
///
/// Hybrid: the bundled `install.yaml` carries the static slice (the
/// `DatabaseServiceProvider` entry and the `databaseConfig` factory, both
/// imported from the package barrel), and this command adds the one step the
/// v1 schema cannot express, downloading `web/sqlite3.wasm`. The manifest's
/// `bootstrap_command` chains this command after `plugin:install`; both
/// injections skip when their code is already present, so that second pass
/// over the manifest converges rather than duplicating.
///
/// ```bash
/// dart run magic:dowel local_storage:install
/// dart run magic:dowel local_storage:install --dry-run
/// ```
class InstallCommand extends DowelInstallCommand {
  /// [wasmUrl] replaces the GitHub release download, so a test can serve the
  /// file from a loopback server.
  InstallCommand({Uri? wasmUrl}) : _wasmUrl = wasmUrl ?? sqliteWasmUrl;

  /// The sqlite3.dart release whose `sqlite3.wasm` is downloaded.
  ///
  /// Tracks this package's `sqlite3: ^3.9.0` constraint in `pubspec.yaml`;
  /// bump the two together. simolus3 ships one wasm per package release, and
  /// a wasm from another release than the Dart bindings is documented to
  /// corrupt data at runtime.
  static const String sqliteWasmRelease = '3.9.1';

  /// Where [sqliteWasmRelease]'s wasm is published.
  static final Uri sqliteWasmUrl = Uri.parse(
    'https://github.com/simolus3/sqlite3.dart/releases/download/'
    'sqlite3-$sqliteWasmRelease/sqlite3.wasm',
  );

  final Uri _wasmUrl;

  @override
  String get signature => 'local_storage:install $baseFlags';

  @override
  String get description =>
      'Install Magic Local Storage: register the provider, wire the config '
      'factory and download web/sqlite3.wasm.';

  @override
  String pluginName(DowelContext ctx) => 'magic_local_storage';

  /// Absolute path to the consumer's project root, resolved on access.
  String get projectRoot => getProjectRoot();

  /// Resolves the consumer's project root. Overridable so a test can point the
  /// whole install at a temp fixture.
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Targets [projectRoot] rather than the process's working directory.
  @override
  InstallContext buildContext(DowelContext ctx) =>
      InstallContext.real(ctx, projectRoot: projectRoot);

  /// Absolute path of this package's bundled `install.yaml`, or `null` when
  /// the consumer's package config does not resolve this package.
  String? resolveManifestPath() {
    final Directory? root = LocalStorageStubLoader.packageRoot(projectRoot);
    if (root == null) return null;
    final File manifest = File.fromUri(root.uri.resolve('install.yaml'));
    return manifest.existsSync() ? manifest.path : null;
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    ctx.output.info(ConsoleStyle.header('Magic Local Storage'));

    // 1. Locate the manifest. A null almost always means pub get has not run.
    final String? manifestPath = resolveManifestPath();
    if (manifestPath == null) {
      ctx.output.error(
        'magic_local_storage install.yaml could not be resolved through '
        '.dart_tool/package_config.json. Run `flutter pub get` first.',
      );
      return 1;
    }

    // 2. Parse it. A malformed manifest is a bug in this package.
    final InstallManifest manifest;
    try {
      manifest = ManifestParser.parseFile(manifestPath);
    } on FormatException catch (e) {
      ctx.output.error('install.yaml at $manifestPath: $e');
      return 1;
    } on ManifestValidationException catch (e) {
      ctx.output.error('install.yaml at $manifestPath: ${e.message}');
      return 1;
    }

    // 3. Run the static slice. ManifestInstaller echoes the post-install
    //    message itself on Success.
    final TransactionResult result =
        await ManifestInstaller(buildContext(ctx), manifest).install(
          dryRun: isDryRun(ctx),
          force: isForce(ctx),
          nonInteractive: isNonInteractive(ctx),
        );

    // 4. WasmSqlite3.loadFromUrl needs web/sqlite3.wasm at runtime; without
    //    it the first web boot fails with a WebAssembly TypeError.
    if (result is Success && !isDryRun(ctx)) {
      await _maybeFetchSqliteWasm(ctx);
    }

    return _renderResult(ctx, result);
  }

  /// Downloads `sqlite3.wasm` into `<projectRoot>/web/`.
  ///
  /// Skips a project without `web/` (native targets use FFI) and keeps a wasm
  /// already present. A failed download is reported with the manual `curl`
  /// fix and does not fail the install: the provider and factory are wired.
  Future<void> _maybeFetchSqliteWasm(DowelContext ctx) async {
    final Directory webDir = Directory('$projectRoot/web');
    if (!webDir.existsSync()) return;

    final File wasmFile = File('${webDir.path}/sqlite3.wasm');
    if (wasmFile.existsSync()) {
      ctx.output.info('web/sqlite3.wasm already present; skipping download.');
      return;
    }

    ctx.output.info(
      'Downloading sqlite3.wasm ($sqliteWasmRelease) into web/ ...',
    );
    final HttpClient client = HttpClient();
    try {
      // GitHub answers with a redirect to its asset host; getUrl follows it.
      final HttpClientRequest request = await client.getUrl(_wasmUrl);
      final HttpClientResponse response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        ctx.output.error(
          'sqlite3.wasm download FAILED (HTTP ${response.statusCode}). '
          'Fix manually: curl -L "$_wasmUrl" -o web/sqlite3.wasm',
        );
        return;
      }

      final BytesBuilder builder = BytesBuilder(copy: false);
      await for (final List<int> chunk in response) {
        builder.add(chunk);
      }
      final Uint8List bytes = builder.takeBytes();
      wasmFile.writeAsBytesSync(bytes);

      final String sizeKb = (bytes.length / 1024).toStringAsFixed(1);
      ctx.output.info(
        'web/sqlite3.wasm written ($sizeKb KB). Web target ready for sqlite3.',
      );
    } on Exception catch (e) {
      ctx.output.error(
        'sqlite3.wasm download FAILED: $e. '
        'Fix manually: curl -L "$_wasmUrl" -o web/sqlite3.wasm',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Turns a [TransactionResult] into a process exit code.
  int _renderResult(DowelContext ctx, TransactionResult result) {
    switch (result) {
      case Success():
        ctx.output.success('Magic Local Storage installed.');
        return 0;
      case DryRun(opCount: final count):
        ctx.output.info('Dry-run: $count op(s) staged; nothing was written.');
        return 0;
      case Conflict(conflicts: final conflicts):
        ctx.output.error(
          'Refused: ${conflicts.length} file(s) differ from what this plugin '
          'last wrote. Re-run with --force to overwrite anyway.',
        );
        for (final conflict in conflicts) {
          ctx.output.warning('  ${conflict.absPath} (${conflict.reason})');
        }
        return 1;
      case Error(error: final message, rolledBack: final rolledBack):
        ctx.output.error('Install failed: $message');
        if (!rolledBack) {
          ctx.output.warning(
            'The transaction was NOT rolled back. Inspect lib/config/app.dart '
            'and lib/main.dart before re-running.',
          );
        }
        return 1;
    }
  }
}
