import 'package:dowel/dowel.dart';

/// Shared test harness for `make:*` generator command tests.
///
/// Builds a bare [DowelContext] driving [command] with [args]: parses
/// [args] against the command's own [ArgParser] (via [command.configure])
/// and wraps the result in an [ArgvInput], the same shape every
/// `make_*_command_test.dart` file hand-rolled as a local `_ctx` helper
/// (see `make_action_command_test.dart`).
DowelContext buildCommandContext(DowelCommand command, List<String> args) {
  final parser = ArgParser();
  command.configure(parser);
  final input = ArgvInput.parse(parser, args);
  return DowelContext.bare(input, BufferedOutput());
}
