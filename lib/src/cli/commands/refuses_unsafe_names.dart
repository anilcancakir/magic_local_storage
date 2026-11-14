import 'package:dowel/dowel.dart';

/// Keeps a generator's output inside its default directory.
///
/// A nested name such as `admin/Monitor` stays allowed. A name with a `..` or
/// `.` segment, an empty segment (a leading, trailing or doubled `/`), a
/// backslash or a drive colon is refused with exit code `1` before anything
/// is written, because the generator joins the name onto its output path and
/// such a name would write outside `lib/database/`.
mixin RefusesUnsafeNames on DowelGeneratorCommand {
  @override
  Future<int> handle(DowelContext ctx) async {
    final String? name = ctx.input.argument(0);
    if (name != null && name.isNotEmpty && !_isSafe(name)) {
      ctx.output.error(
        'The name "$name" may not contain "..", ".", an empty path segment, '
        'a backslash or a colon. Use a relative name such as admin/Monitor.',
      );
      return 1;
    }

    return super.handle(ctx);
  }

  bool _isSafe(String name) {
    if (name.contains(r'\') || name.contains(':')) return false;

    return name
        .split('/')
        .every(
          (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
        );
  }
}
