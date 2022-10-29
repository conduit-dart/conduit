import 'dart:async';

import 'package:conduit/src/cli/command.dart';
import 'package:conduit/src/cli/mixins/database_connecting.dart';
import 'package:conduit/src/cli/mixins/database_managing.dart';
import 'package:conduit/src/cli/mixins/project.dart';

class CLIDatabaseShowMigrations extends CLICommand
    with CLIDatabaseManagingCommand, CLIProject, CLIDatabaseConnectingCommand {
  @override
  Future<int> handle() async {
    final files = projectMigrations.map((mig) {
      final versionString = "${mig.versionNumber}".padLeft(8, "0");
      return " $versionString | ${mig.uri!.pathSegments.last}";
    }).join("\n");

    print(" Version  | Path");
    print("----------|-----------");
    print("$files");

    return 0;
  }

  @override
  String get name {
    return "list";
  }

  @override
  String get description {
    return "Show the path and version all migration files for this project.";
  }
}
