import 'dart:async';

import 'package:conduit/src/cli/command.dart';
import 'package:conduit/src/cli/commands/auth.dart';
import 'package:conduit/src/cli/commands/build.dart';
import 'package:conduit/src/cli/commands/create.dart';
import 'package:conduit/src/cli/commands/db.dart';
import 'package:conduit/src/cli/commands/document.dart';
import 'package:conduit/src/cli/commands/serve.dart';
import 'package:conduit/src/cli/commands/setup.dart';

class Runner extends CLICommand {
  Runner() {
    registerCommand(CLITemplateCreator());
    registerCommand(CLIDatabase());
    registerCommand(CLIServer());
    registerCommand(CLISetup());
    registerCommand(CLIAuth());
    registerCommand(CLIDocument());
    registerCommand(CLIBuild());
  }

  @override
  Future<int> handle() async {
    printHelp();
    return 0;
  }

  @override
  String get name {
    return "conduit";
  }

  @override
  String get description {
    return "Conduit is a tool for managing Conduit applications.";
  }
}
