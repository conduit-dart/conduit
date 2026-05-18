import 'dart:io';

import 'package:conduit_postgresql/conduit_postgresql.dart';
import 'package:fs_test_agent/dart_project_agent.dart';
import 'package:fs_test_agent/working_directory_agent.dart';
import 'package:test/test.dart';

import 'not_tests/cli_helpers.dart';
import 'not_tests/postgres_test_config.dart';

void main() {
  late CLIClient templateCli;
  late CLIClient projectUnderTestCli;
  PostgreSQLPersistentStore? store;

  final connectInfo = PostgresTestConfig().databaseConfiguration();
  final connectString =
      "postgres://${connectInfo.username}:${connectInfo.password}@${connectInfo.host}:${connectInfo.port}/${connectInfo.databaseName}";

  setUpAll(() async {
    templateCli = await CLIClient(
      WorkingDirectoryAgent(DartProjectAgent.projectsDirectory),
    ).createTestProject();
    await templateCli.agent.getDependencies();
  });

  tearDownAll(DartProjectAgent.tearDownAll);

  setUp(() async {
    projectUnderTestCli = templateCli.replicate(Uri.parse("rebuild_replica/"));
    projectUnderTestCli.projectAgent.addLibraryFile("application_test", """
import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_postgresql/conduit_postgresql.dart';

class TestObject extends ManagedObject<_TestObject> {}

class _TestObject {
  @primaryKey
  int? id;

  String? foo;
}
""");

    store = PostgresTestConfig().persistentStore();

    final tables = ["_conduit_version_pgsql", "_testobject", "_stale_table"];
    await Future.wait(
      tables.map((t) {
        return store?.execute("DROP TABLE IF EXISTS $t CASCADE");
      }).whereType<Future>(),
    );
  });

  tearDown(() async {
    final tables = ["_conduit_version_pgsql", "_testobject", "_stale_table"];
    await Future.wait(
      tables.map((t) {
        return store?.execute("DROP TABLE IF EXISTS $t CASCADE");
      }).whereType<Future>(),
    );
    await store?.close();
    projectUnderTestCli.delete();
  });

  test(
    "Without --yes and no terminal, db rebuild refuses to run and exits non-zero",
    () async {
      // First produce a baseline migration so the command isn't a no-op for
      // unrelated reasons.
      var res = await projectUnderTestCli.run("db", ["generate"]);
      expect(res, 0);

      res = await projectUnderTestCli.run("db", [
        "rebuild",
        "--connect",
        connectString,
      ]);
      expect(res, isNonZero);
      expect(projectUnderTestCli.output, contains("Aborted"));

      // Migration files must be untouched.
      final remaining = projectUnderTestCli.defaultMigrationDirectory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith(".migration.dart"))
          .toList();
      expect(remaining, isNotEmpty);
    },
  );

  test(
    "With --yes, db rebuild drops tables, regenerates and re-applies migrations",
    () async {
      // Seed a stale table that is not part of the project schema. After
      // rebuild it should still be gone (dropped explicitly via the tracked
      // schema set, OR untouched because it isn't tracked — this test
      // documents that the version table + tracked tables go away).
      await store!
          .execute("CREATE TABLE IF NOT EXISTS _stale_table (id integer)");

      // Baseline: generate + upgrade once to land schema in DB.
      var res = await projectUnderTestCli.run("db", ["generate"]);
      expect(res, 0);
      res = await projectUnderTestCli.run("db", [
        "upgrade",
        "--connect",
        connectString,
      ]);
      expect(res, 0);

      // Both the version table and the _testobject table now exist.
      expect(await _tableExists(store!, "_conduit_version_pgsql"), isTrue);
      expect(await _tableExists(store!, "_testobject"), isTrue);

      // Now rebuild.
      projectUnderTestCli.clearOutput();
      res = await projectUnderTestCli.run("db", [
        "rebuild",
        "--yes",
        "--connect",
        connectString,
      ]);
      expect(res, 0);
      expect(projectUnderTestCli.output, contains("Rebuild complete"));

      // The DB ends in a freshly-migrated state: version table exists and is
      // back at version 1, _testobject exists, no stray columns from older
      // schemas. The stale table is unrelated to the project schema and is
      // not tracked, so we don't assert anything about it here.
      expect(await _tableExists(store!, "_conduit_version_pgsql"), isTrue);
      expect(await _tableExists(store!, "_testobject"), isTrue);

      final version = await store!.execute(
        "SELECT versionNumber FROM _conduit_version_pgsql",
      );
      expect(version, [
        [1],
      ]);

      // A fresh migration file (and only one) should be on disk.
      final migrations = projectUnderTestCli.defaultMigrationDirectory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith(".migration.dart"))
          .toList();
      expect(migrations, hasLength(1));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    "With --yes, rebuild succeeds even when the previous schema diverges from migrations",
    () async {
      // Generate once, then mutate the model so the existing migration no
      // longer matches. `db upgrade` would normally complain — `db rebuild`
      // wipes and starts over.
      var res = await projectUnderTestCli.run("db", ["generate"]);
      expect(res, 0);
      res = await projectUnderTestCli.run("db", [
        "upgrade",
        "--connect",
        connectString,
      ]);
      expect(res, 0);

      // Mutate the model: add a `bar` column.
      projectUnderTestCli.projectAgent.addLibraryFile("application_test", """
import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_postgresql/conduit_postgresql.dart';

class TestObject extends ManagedObject<_TestObject> {}

class _TestObject {
  @primaryKey
  int? id;

  String? foo;

  String? bar;
}
""");

      projectUnderTestCli.clearOutput();
      res = await projectUnderTestCli.run("db", [
        "rebuild",
        "--yes",
        "--connect",
        connectString,
      ]);
      expect(res, 0);

      // Resulting table should have id + foo + bar.
      final cols = await _columnsOfTable(store!, "_testobject");
      expect(cols.toSet(), containsAll(<String>{"id", "foo", "bar"}));

      // Only one migration file (the regenerated initial).
      final migrations = projectUnderTestCli.defaultMigrationDirectory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith(".migration.dart"))
          .toList();
      expect(migrations, hasLength(1));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<bool> _tableExists(PostgreSQLPersistentStore store, String name) async {
  final result = await store.execute(
    "SELECT to_regclass(@n:text)",
    substitutionValues: {"n": name},
  ) as List<List<dynamic>>;
  return result.first.first != null;
}

Future<List<String>> _columnsOfTable(
  PostgreSQLPersistentStore store,
  String tableName,
) async {
  final results = await store.execute(
    "SELECT column_name FROM information_schema.columns WHERE table_name=@n:text",
    substitutionValues: {"n": tableName},
  ) as List<List<dynamic>>;
  return results.map((r) => r.first as String).toList();
}
