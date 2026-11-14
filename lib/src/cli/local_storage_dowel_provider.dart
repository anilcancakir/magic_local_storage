import 'package:dowel/dowel.dart';

import 'commands/install_command.dart';
import 'commands/make_factory_command.dart';
import 'commands/make_migration_command.dart';
import 'commands/make_seeder_command.dart';

/// The dowel provider for Magic Local Storage.
///
/// The only registrar of `make:migration`, `make:seeder` and `make:factory`:
/// dowel exits on a command-name collision, so core must never register
/// them too. Core's `make:model -m/-f/-s` and `make:resource` find them in the
/// registry by name.
///
/// Named `<PascalCase package>DowelProvider` because that is the class the
/// dowel `plugin:install` command registers from
/// `package:magic_local_storage/cli.dart`.
class MagicLocalStorageDowelProvider extends DowelServiceProvider {
  @override
  String get providerName => 'magic_local_storage';

  @override
  List<DowelCommand> commands() => <DowelCommand>[
    MakeMigrationCommand(),
    MakeSeederCommand(),
    MakeFactoryCommand(),
    InstallCommand(),
  ];
}
