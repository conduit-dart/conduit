import 'dart:async';

import 'package:conduit/src/command.dart';
import 'package:conduit/src/commands/auth.dart';
import 'package:conduit/src/commands/build.dart';
import 'package:conduit/src/commands/create.dart';
import 'package:conduit/src/commands/db.dart';
import 'package:conduit/src/commands/document.dart';
import 'package:conduit/src/commands/serve.dart';
import 'package:conduit/src/commands/setup.dart';

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
