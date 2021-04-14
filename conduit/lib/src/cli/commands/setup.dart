import 'dart:async';
import 'dart:io';

import 'package:conduit/src/cli/command.dart';
import 'package:conduit/src/cli/metadata.dart';
import 'package:conduit/src/cli/mixins/project.dart';

class CLISetup extends CLICommand with CLIProject {
  bool get shouldSetupHeroku => herokuName != null;

  @Option("heroku",
      help:
          "DEPRECATED. Please see https://conduit.io/docs/deploy/deploy_heroku/.")
  String? get herokuName => decode("heroku");

  @Flag("tests",
      help:
          "Sets up a local database to run application tests. If no other option is on, the command defaults to this flag.",
      defaultsTo: true)
  bool get shouldSetupTests => decode("tests")!;

  @Flag("confirm",
      abbr: "c",
      negatable: false,
      help: "Confirms that you wish to carry out this setup.",
      defaultsTo: false)
  bool get confirm => decode("confirm")!;

  @Option("granting-user",
      abbr: "u",
      defaultsTo: "postgres",
      help:
          "The username of the PostgreSQL user that has privileges to create a new test user and test database.")
  String get grantingUser => decode("granting-user")!;

  @override
  Future<int> handle() async {
    if (shouldSetupHeroku) {
      displayInfo("This option has been deprecated.");
      displayProgress(
          "Please see https://conduit.io/docs/deploy/deploy_heroku/ for instructions.");
      return 0;
    } else /*if (shouldSetupTests*/ {
      return setupTestEnvironment();
    }
  }

  bool get hasPSQLCLI => isExecutableInShellPath("psql");

  Future<int> setupTestEnvironment() async {
    if (!hasPSQLCLI) {
      displayError(
          "The application 'psql' was not found in \$PATH.\n\nIf you do not have PostgreSQL installed locally, "
          "you must do so to run tests in an Conduit application. For macOS users, "
          "download Postgres.app from http://postgresapp.com. Once installed, open the "
          "application at least once and add the following line to ~/.bash_profile:\n\n"
          "\texport PATH=\$PATH:/Applications/Postgres.app/Contents/Versions/latest/bin\n\n"
          "You may have to reload the shell you ran this command from after installation. "
          "For non-macOS users, you must install a local version of PostgreSQL"
          "and ensure the command line executable 'psql' is in your PATH.");

      return -1;
    }

    var commands = [
      "create database conduit_test_db;",
      "create user conduit_test_user with createdb;",
      "alter user conduit_test_user with password 'conduit!';",
      "grant all on database conduit_test_db to dart;"
    ];

    if (!confirm) {
      displayInfo("Confirmation Needed");
      displayProgress(
          "This command will execute SQL to create a test database.");
      displayProgress(
          "As a security measure, you must add --confirm (or -c) to this command.");
      displayProgress("The commands that will be run upon confirmation:");
      commands.forEach((cmd) {
        displayProgress("\t* psql -c '$cmd' -U $grantingUser");
      });
      return -1;
    }

    displayInfo("Connecting to database...");
    for (var cmd in commands) {
      List<String> args = ["-c", cmd, "-U", grantingUser];

      final result = Process.runSync("psql", args, runInShell: true);
      final output = (result.stdout as String) + (result.stderr as String);
      if (output.contains("CREATE DATABASE")) {
        displayProgress("Successfully created database conduit_test_db.");
      } else if (output.contains("CREATE ROLE")) {
        displayProgress(
            "Successfully created role 'conduit_test_user' with createdb permissions.");
      } else if (output.contains("ALTER ROLE")) {
        displayProgress(
            "Successfully set user 'conduit_test_user' password to 'conduit!'.");
      } else if (output.contains("GRANT")) {
        displayProgress(
            "Successfully granted all privileges to database conduit_test_db to user 'conduit_test_user'.");
      }

      if (output.contains("database \"conduit_test_db\" already exists")) {
        displayProgress("Database conduit_test_db already exists, continuing.");
      } else if (output.contains("role \"conduit_test_user\" already exists")) {
        displayProgress("User 'conduit_test_user' already exists, continuing.");
      } else if (output.contains("could not connect to server")) {
        displayError(
            "Database is not accepting connections. Ensure that PostgreSQL is running locally.");

        return -1;
      } else if ((result.stderr as String).isNotEmpty) {
        displayError("Unknown error: ${result.stderr}");
        return -1;
      }
    }

    displayInfo(
        "Congratulations! Conduit applications can now be tested locally.");

    return 0;
  }

  @override
  String get name {
    return "setup";
  }

  @override
  String get description {
    return "A one-time setup command for your development environment.";
  }
}
