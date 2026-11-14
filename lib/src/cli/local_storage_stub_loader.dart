import 'dart:convert';
import 'dart:io';

/// Locates this package on disk and reads the `.stub` files it ships in
/// `assets/stubs/`.
///
/// Core's stub loader resolves `magic`'s own root, and the dowel default
/// search paths point at the dowel package, so neither reaches these stubs.
/// The root is read out of the consumer's `.dart_tool/package_config.json`,
/// the same source the manifest installer uses: `Isolate.resolvePackageUri`
/// is unsupported under `flutter test`, so it would leave the path untestable.
abstract final class LocalStorageStubLoader {
  static const String _packageName = 'magic_local_storage';

  /// The root directory of [package] (this package by default) as seen from
  /// the project at [projectDir], or `null` when that project has no package
  /// config (pub get has not run) or does not resolve [package].
  static Directory? packageRoot(
    String projectDir, {
    String package = _packageName,
  }) {
    final Uri toolDir = Directory(projectDir).absolute.uri
        .resolve('.dart_tool/');
    final File config = File.fromUri(toolDir.resolve('package_config.json'));
    if (!config.existsSync()) return null;

    final Object? decoded = jsonDecode(config.readAsStringSync());
    if (decoded is! Map<String, dynamic>) return null;
    final Object? packages = decoded['packages'];
    if (packages is! List) return null;

    for (final Object? entry in packages) {
      if (entry is! Map || entry['name'] != package) continue;
      final Object? rootUri = entry['rootUri'];
      if (rootUri is! String) return null;
      // A relative rootUri resolves against the directory holding the config.
      final String withSlash = rootUri.endsWith('/') ? rootUri : '$rootUri/';
      return Directory.fromUri(toolDir.resolve(withSlash));
    }
    return null;
  }

  /// Raw content of `assets/stubs/<name>.stub`, resolved from the working
  /// directory's package config (the consumer project running dowel).
  ///
  /// Throws [StateError] when the package cannot be resolved or the stub file
  /// is missing, naming the fix.
  static String load(String name) {
    final Directory? root = packageRoot(Directory.current.path);
    if (root == null) {
      throw StateError(
        'Could not resolve $_packageName from .dart_tool/package_config.json. '
        'Run `flutter pub get` in a project that depends on $_packageName.',
      );
    }
    final File stub = File.fromUri(root.uri.resolve('assets/stubs/$name.stub'));
    if (!stub.existsSync()) {
      throw StateError('Stub file not found: $name.stub at ${stub.path}.');
    }
    return stub.readAsStringSync();
  }
}
