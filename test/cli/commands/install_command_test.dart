import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dowel/dowel.dart';
import 'package:magic_local_storage/src/cli/commands/install_command.dart';

/// Test subclass pinning the project root at a temp fixture.
///
/// `injectProvider` and `injectConfigFactory` are helper-backed ops that
/// write through `dart:io` directly rather than through the context's
/// [VirtualFs], so the fixture has to be a REAL directory.
class _PinnedInstallCommand extends InstallCommand {
  _PinnedInstallCommand(this._root, {super.wasmUrl});

  final String _root;

  @override
  String getProjectRoot() => _root;
}

DowelContext _ctx(
  InstallCommand command, [
  Map<String, dynamic> overrides = const <String, dynamic>{},
]) {
  return DowelContext.bare(
    MapInput(<String, dynamic>{
      'force': false,
      'dry-run': false,
      'non-interactive': true,
      'no-bootstrap': false,
      ...overrides,
    }, signature: command.parsedSignature),
    BufferedOutput(),
  );
}

String _output(DowelContext ctx) => (ctx.output as BufferedOutput).content;

/// A loopback server standing in for the GitHub release download, so the
/// wasm step runs for real without touching the network.
class _WasmServer {
  _WasmServer._(this._server, this.statusCode);

  final HttpServer _server;
  final int statusCode;
  int hits = 0;

  static final List<int> body = List<int>.generate(2048, (i) => i % 256);

  static Future<_WasmServer> start({int statusCode = 200}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final wasm = _WasmServer._(server, statusCode);
    server.listen((request) {
      wasm.hits++;
      request.response.statusCode = statusCode;
      if (statusCode == 200) request.response.add(body);
      request.response.close();
    });
    return wasm;
  }

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/sqlite3.wasm');

  Future<void> close() => _server.close(force: true);
}

void main() {
  late Directory temp;

  String at(String relative) => '${temp.path}/$relative';

  setUp(() {
    temp = Directory.systemTemp.createTempSync('magic_local_storage_install_');

    File(at('pubspec.yaml')).writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
  magic_local_storage: ^0.0.1
''');

    Directory(at('.dart_tool')).createSync(recursive: true);
    File(at('.dart_tool/package_config.json')).writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "magic_local_storage",
      "rootUri": "${Directory.current.uri}",
      "packageUri": "lib/",
      "languageVersion": "3.11"
    }
  ]
}
''');

    Directory(at('lib/config')).createSync(recursive: true);
    File(at('lib/config/app.dart')).writeAsStringSync('''
import 'package:magic/magic.dart';

final appConfig = {
  'providers': [
    (app) => RouteServiceProvider(app),
  ],
};
''');

    File(at('lib/main.dart')).writeAsStringSync('''
import 'package:magic/magic.dart';
import 'config/app.dart';

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
    ],
  );
}
''');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('InstallCommand surface', () {
    test('is an install command named local_storage:install', () {
      final command = InstallCommand();

      expect(command, isA<DowelInstallCommand>());
      expect(command.name, 'local_storage:install');
      expect(command.signature, contains('--force'));
      expect(command.signature, contains('--dry-run'));
      expect(command.signature, contains('--non-interactive'));
    });

    test('writes its install record under the package name', () {
      final command = InstallCommand();
      expect(command.pluginName(_ctx(command)), 'magic_local_storage');
    });

    test('downloads the wasm release matching the sqlite3 constraint', () {
      expect(
        InstallCommand.sqliteWasmUrl.toString(),
        'https://github.com/simolus3/sqlite3.dart/releases/download/'
        'sqlite3-3.9.1/sqlite3.wasm',
      );
    });

    test('resolves the bundled install.yaml off the package root', () {
      final path = _PinnedInstallCommand(temp.path).resolveManifestPath();

      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
    });

    test('reports rather than throws when pub get has not run', () async {
      File(at('.dart_tool/package_config.json')).deleteSync();
      final command = _PinnedInstallCommand(temp.path);
      final ctx = _ctx(command);

      expect(await command.handle(ctx), 1);
      expect(_output(ctx), contains('flutter pub get'));
    });
  });

  group('InstallCommand.handle() wiring', () {
    test('registers the provider and the barrel databaseConfig factory, '
        'publishing nothing', () async {
      final command = _PinnedInstallCommand(temp.path);
      final ctx = _ctx(command);

      expect(await command.handle(ctx), 0, reason: _output(ctx));

      final app = File(at('lib/config/app.dart')).readAsStringSync();
      final main = File(at('lib/main.dart')).readAsStringSync();
      const barrel =
          "import 'package:magic_local_storage/magic_local_storage.dart';";
      expect(app, contains(barrel));
      expect(app, contains('(app) => DatabaseServiceProvider(app),'));
      expect(main, contains(barrel));
      expect(main, contains('() => databaseConfig,'));
      expect(File(at('lib/config/database.dart')).existsSync(), isFalse);
    });

    test('a second run converges instead of duplicating', () async {
      final command = _PinnedInstallCommand(temp.path);
      await command.handle(_ctx(command));
      final ctx = _ctx(command);

      expect(await command.handle(ctx), 0, reason: _output(ctx));

      final app = File(at('lib/config/app.dart')).readAsStringSync();
      final main = File(at('lib/main.dart')).readAsStringSync();
      expect('DatabaseServiceProvider('.allMatches(app), hasLength(1));
      expect('() => databaseConfig'.allMatches(main), hasLength(1));
    });
  });

  group('InstallCommand.handle() sqlite3.wasm', () {
    late _WasmServer server;

    tearDown(() => server.close());

    test('skips the download when the project has no web/ directory', () async {
      server = await _WasmServer.start();
      final command = _PinnedInstallCommand(temp.path, wasmUrl: server.url);

      expect(await command.handle(_ctx(command)), 0);
      expect(server.hits, 0);
      expect(File(at('web/sqlite3.wasm')).existsSync(), isFalse);
    });

    test('writes web/sqlite3.wasm for a web project', () async {
      server = await _WasmServer.start();
      Directory(at('web')).createSync();
      final command = _PinnedInstallCommand(temp.path, wasmUrl: server.url);
      final ctx = _ctx(command);

      expect(await command.handle(ctx), 0, reason: _output(ctx));
      expect(server.hits, 1);
      expect(File(at('web/sqlite3.wasm')).readAsBytesSync(), _WasmServer.body);
      expect(_output(ctx), contains('web/sqlite3.wasm written (2.0 KB)'));
    });

    test('keeps an existing web/sqlite3.wasm', () async {
      server = await _WasmServer.start();
      Directory(at('web')).createSync();
      File(at('web/sqlite3.wasm')).writeAsStringSync('existing');
      final command = _PinnedInstallCommand(temp.path, wasmUrl: server.url);
      final ctx = _ctx(command);

      expect(await command.handle(ctx), 0);
      expect(server.hits, 0);
      expect(File(at('web/sqlite3.wasm')).readAsStringSync(), 'existing');
      expect(_output(ctx), contains('already present; skipping download'));
    });

    test('a dry run downloads nothing', () async {
      server = await _WasmServer.start();
      Directory(at('web')).createSync();
      final command = _PinnedInstallCommand(temp.path, wasmUrl: server.url);

      expect(await command.handle(_ctx(command, {'dry-run': true})), 0);
      expect(server.hits, 0);
      expect(File(at('web/sqlite3.wasm')).existsSync(), isFalse);
    });

    test('reports an HTTP failure with the manual curl fix', () async {
      server = await _WasmServer.start(statusCode: 404);
      Directory(at('web')).createSync();
      final command = _PinnedInstallCommand(temp.path, wasmUrl: server.url);
      final ctx = _ctx(command);

      await command.handle(ctx);

      expect(File(at('web/sqlite3.wasm')).existsSync(), isFalse);
      expect(_output(ctx), contains('sqlite3.wasm download FAILED (HTTP 404)'));
      expect(_output(ctx), contains('curl -L "${server.url}"'));
    });

    test('reports a network failure with the manual curl fix', () async {
      server = await _WasmServer.start();
      final unreachable = server.url;
      await server.close();
      Directory(at('web')).createSync();
      final command = _PinnedInstallCommand(temp.path, wasmUrl: unreachable);
      final ctx = _ctx(command);

      await command.handle(ctx);

      expect(File(at('web/sqlite3.wasm')).existsSync(), isFalse);
      expect(_output(ctx), contains('sqlite3.wasm download FAILED: '));
      expect(_output(ctx), contains('curl -L "$unreachable"'));
    });
  });
}
