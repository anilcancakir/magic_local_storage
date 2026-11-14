@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dowel/dowel.dart';
import 'package:magic_local_storage/src/cli/commands/make_factory_command.dart';
import 'package:magic_local_storage/src/cli/commands/make_migration_command.dart';
import 'package:magic_local_storage/src/cli/commands/make_seeder_command.dart';
import 'package:path/path.dart' as p;

import '../commands/_harness.dart';

/// `flutter test` runs with the package root as the working directory, which
/// is also where the stub loader resolves `assets/stubs/` from through the
/// self-referencing `magic_local_storage` entry of
/// `.dart_tool/package_config.json`. Only the generators' OUTPUT path is
/// redirected into the probe through each command's `testRoot`.
String get _pluginRoot => Directory.current.path;

/// Core's checkout, read from this package's own resolution so the probe
/// builds against the same `magic` the plugin's tests do.
String get _magicRoot {
  final config = File(p.join(_pluginRoot, '.dart_tool', 'package_config.json'))
      .readAsStringSync();
  final match = RegExp(r'"name":\s*"magic",\s*"rootUri":\s*"([^"]+)"')
      .firstMatch(config);
  final rootUri = match!.group(1)!;
  return rootUri.startsWith('file://')
      ? Uri.parse(rootUri).toFilePath()
      : p.normalize(p.join(_pluginRoot, '.dart_tool', rootUri));
}

Future<void> _run(DowelCommand command, List<String> args) async {
  final int code = await command.handle(buildCommandContext(command, args));
  expect(
    code,
    0,
    reason: 'dowel ${command.name} ${args.join(' ')} exited $code',
  );
}

void main() {
  late Directory probeRoot;

  setUpAll(() async {
    // 1. A throwaway Flutter package wired to this plugin and to core by
    //    ABSOLUTE path, the way a consumer's pubspec_overrides.yaml would.
    probeRoot = Directory.systemTemp.createTempSync('local_storage_probe_');
    FileHelper.writeFile(p.join(probeRoot.path, 'pubspec.yaml'), '''
name: local_storage_probe
description: Throwaway probe proving the database generators' output analyzes clean.
publish_to: none
version: 0.0.1

environment:
  sdk: ">=3.13.0 <4.0.0"
  flutter: ">=3.47.0"

dependencies:
  flutter:
    sdk: flutter
  magic:
    path: $_magicRoot
  magic_local_storage:
    path: $_pluginRoot

dev_dependencies:
  flutter_lints: ^6.0.0

# The plugin asks for magic from the registry; the override keeps one magic,
# the checkout, in the graph.
dependency_overrides:
  magic:
    path: $_magicRoot
''');
    FileHelper.writeFile(
      p.join(probeRoot.path, 'analysis_options.yaml'),
      'include: package:flutter_lints/flutter.yaml\n',
    );

    // 2. Every generator this package owns, both migration stubs included.
    final root = probeRoot.path;
    await _run(MakeMigrationCommand(testRoot: root), <String>[
      'create_probes_table',
      '--create=probes',
    ]);
    await _run(MakeMigrationCommand(testRoot: root), <String>[
      'add_region_to_probes',
      '--table=probes',
    ]);
    await _run(MakeSeederCommand(testRoot: root), <String>['Probe']);
    await _run(MakeFactoryCommand(testRoot: root), <String>['Probe']);

    // 3. Resolve offline first; fall back online on a cold cache.
    final offline = await Process.run('flutter', <String>[
      'pub',
      'get',
      '--offline',
    ], workingDirectory: root);
    if (offline.exitCode == 0) return;
    final online = await Process.run('flutter', <String>[
      'pub',
      'get',
    ], workingDirectory: root);
    expect(online.exitCode, 0, reason: '${online.stdout}${online.stderr}');
  });

  tearDownAll(() {
    if (probeRoot.existsSync()) probeRoot.deleteSync(recursive: true);
  });

  test('every database generator output analyzes with flutter_lints, zero '
      'issues', () async {
    final result = await Process.run('flutter', <String>[
      'analyze',
    ], workingDirectory: probeRoot.path);
    final output = '${result.stdout}${result.stderr}';

    expect(output, contains('No issues found!'), reason: output);
  });
}
