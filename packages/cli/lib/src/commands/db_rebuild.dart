import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit/src/command.dart';
import 'package:conduit/src/commands/db_generate.dart';
import 'package:conduit/src/commands/db_upgrade.dart';
import 'package:conduit/src/metadata.dart';
import 'package:conduit/src/mixins/database_connecting.dart';
import 'package:conduit/src/mixins/database_managing.dart';
import 'package:conduit/src/mixins/project.dart';
import 'package:conduit_postgresql/conduit_postgresql.dart';

/// Drops all tables, removes migration files, regenerates the initial
/// migration, and re-applies it to the database. Optionally runs a seed
/// script.
///
/// This is destructive and requires confirmation via `--yes` or by typing the
/// database name back at an interactive prompt.
class CLIDatabaseRebuild extends CLICommand
    with CLIDatabaseConnectingCommand, CLIDatabaseManagingCommand, CLIProject {
  @Flag(
    "yes",
    abbr: "y",
    help:
        "Skip the interactive confirmation prompt. Required for non-interactive use.",
    defaultsTo: false,
    negatable: false,
  )
  bool get skipConfirmation => decode<bool>("yes");

  @Option(
    "name",
    help:
        "Name of the regenerated migration. Automatically lower- and snake-cased.",
    defaultsTo: "initial",
  )
  String get migrationName => decode<String>("name");

  @Option(
    "seed",
    help:
        "Path to a Dart script invoked via `dart run` after upgrade completes.",
  )
  String? get seedScript => decodeOptional<String>("seed");

  /// Hook for tests: a callable that reads a single line from stdin.
  /// Defaults to [stdin.readLineSync] but can be replaced in tests.
  String? Function() promptReader = () => stdin.readLineSync();

  @override
  Future<int> handle() async {
    final dbName = connectedDatabase.databaseName;

    if (!await _confirmDestructive(dbName)) {
      displayError("Aborted: confirmation was not provided.");
      displayProgress(
        "Re-run with --yes to skip the prompt, or type the database "
        "name when prompted.",
      );
      return 1;
    }

    // 1. Drop tables (best-effort).
    await _dropAllTables();

    // 2. Remove existing migration files.
    final removed = _removeMigrationFiles();
    displayInfo("Removed $removed migration file(s).");

    // 3. Re-run `db generate` to produce a fresh initial migration.
    final genArgs = <String>[
      "--directory",
      projectDirectory!.path,
      "--migration-directory",
      migrationDirectory!.path,
      "--name",
      migrationName,
    ];
    final generate = CLIDatabaseGenerate()..outputSink = outputSink;
    final genResult = await generate.process(generate.options.parse(genArgs));
    if (genResult != 0) {
      displayError("`db generate` failed during rebuild.");
      return genResult;
    }

    // 4. Re-run `db upgrade` against the now-empty database.
    final upgradeArgs = <String>[
      "--directory",
      projectDirectory!.path,
      "--migration-directory",
      migrationDirectory!.path,
      "--flavor",
      databaseFlavor,
      "--ssl-mode",
      sslMode,
    ];
    if (databaseConnectionString != null) {
      upgradeArgs.addAll(["--connect", databaseConnectionString!]);
    } else {
      upgradeArgs.addAll([
        "--database-config",
        databaseConfigurationFile.path,
      ]);
    }
    final upgrade = CLIDatabaseUpgrade()..outputSink = outputSink;
    final upgradeResult =
        await upgrade.process(upgrade.options.parse(upgradeArgs));
    if (upgradeResult != 0) {
      displayError("`db upgrade` failed during rebuild.");
      return upgradeResult;
    }

    // 5. Optionally re-run user seed code.
    if (seedScript != null) {
      final seedExit = await _runSeed(seedScript!);
      if (seedExit != 0) {
        displayError("Seed script exited with code $seedExit.");
        return seedExit;
      }
    }

    displayInfo(
      "Rebuild complete: '$dbName' is freshly migrated.",
      color: CLIColor.boldGreen,
    );
    return 0;
  }

  Future<bool> _confirmDestructive(String dbName) async {
    if (skipConfirmation) {
      return true;
    }

    if (!stdin.hasTerminal) {
      // Don't proceed silently when there's no human to confirm.
      return false;
    }

    displayError(
      "This will DROP all tables in '$dbName' and remove migration files.",
    );
    outputSink.writeln(
      "    Type the database name to confirm (or anything else to abort):",
    );
    final response = promptReader();
    return response != null && response.trim() == dbName;
  }

  /// Drops every table the project knows about: tables produced by replaying
  /// existing migration files plus the persistent store's own version table.
  /// Uses `DROP TABLE IF EXISTS ... CASCADE` against the active
  /// [persistentStore] so this stays at the abstraction's level — only the
  /// store's `execute` is touched.
  Future<void> _dropAllTables() async {
    final tableNames = await _resolveTablesToDrop();
    if (tableNames.isEmpty) {
      displayInfo("No known tables to drop.");
      return;
    }

    displayInfo("Dropping ${tableNames.length} table(s)...");
    for (final name in tableNames) {
      try {
        await persistentStore.execute('DROP TABLE IF EXISTS "$name" CASCADE');
        displayProgress("Dropped $name");
      } on Object catch (e) {
        // Best-effort: log and continue. A fresh DB is the goal, and a
        // missing table just means there is less to clean up.
        displayProgress("Skipped $name ($e)");
      }
    }
  }

  Future<List<String>> _resolveTablesToDrop() async {
    final names = <String>{};

    final migrations = projectMigrations;
    if (migrations.isNotEmpty) {
      try {
        final schema = await schemaByApplyingMigrationSources(migrations);
        for (final t in schema.tables) {
          if (t.name != null) {
            names.add(t.name!);
          }
        }
      } on CLIException catch (e) {
        // Replay can fail if migration files reference removed model classes.
        // That's fine for a destructive rebuild — fall back to the version
        // table only.
        displayProgress(
          "Could not replay migrations to determine tables: ${e.message}",
        );
      }
    }

    // The store's version table (e.g. _conduit_version_pgsql) is not part of
    // any migration but must be dropped for a clean rebuild.
    final s = persistentStore;
    if (s is PostgreSQLPersistentStore) {
      names.add(s.versionTable.name!);
    }

    return names.toList();
  }

  int _removeMigrationFiles() {
    final dir = migrationDirectory!;
    if (!dir.existsSync()) {
      return 0;
    }
    final pattern = RegExp(r"^[0-9]+[_a-zA-Z0-9]*\.migration\.dart$");
    var count = 0;
    for (final entity in dir.listSync()) {
      if (entity is File && pattern.hasMatch(entity.uri.pathSegments.last)) {
        entity.deleteSync();
        count++;
      }
    }
    return count;
  }

  Future<int> _runSeed(String scriptPath) async {
    final scriptFile = fileInProjectDirectory(scriptPath);
    if (!scriptFile.existsSync()) {
      displayError("Seed script not found: ${scriptFile.path}");
      return 1;
    }

    displayInfo("Running seed script: ${scriptFile.path}");
    final result = await Process.run(
      "dart",
      ["run", scriptFile.path],
      workingDirectory: projectDirectory!.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.stdout.toString().isNotEmpty) {
      result.stdout.toString().split("\n").forEach(displayProgress);
    }
    if (result.stderr.toString().isNotEmpty) {
      result.stderr.toString().split("\n").forEach(displayProgress);
    }
    return result.exitCode;
  }

  @override
  String get name => "rebuild";

  @override
  String get description =>
      "Drops all tables, regenerates an initial migration and re-applies it.";

  @override
  String get detailedDescription =>
      "Destructive. Intended for development loops where the schema diverges "
      "and a clean slate is faster than chained migrations. Requires --yes "
      "or that you type the database name back at the confirmation prompt.";
}
