// ignore: unnecessary_const
// ignore_for_file: always_declare_return_types

@Tags(["cli"])
import 'dart:async';
import 'dart:io';

import 'package:conduit/conduit.dart';
import 'package:conduit/src/cli/command.dart';
import 'package:conduit/src/cli/mixins/database_managing.dart';
import 'package:conduit/src/cli/mixins/project.dart';
import 'package:conduit_common_test/conduit_common_test.dart';
import 'package:test/test.dart';

void main() {
  group("Cooperation", () {
    late PersistentStore store;

    setUp(() {
      store = PostgresTestConfig().persistentStore();
    });

    tearDown(() async {
      await store.close();
    });

    test(
        "Migration subclasses can be executed and commands are generated and executed on the DB, schema is udpated",
        () async {
      // Note that the permutations of operations are covered in different tests, this is just to ensure that
      // executing a migration/upgrade all work together.
      final schema = Schema([
        SchemaTable("tableToKeep", [
          SchemaColumn("columnToEdit", ManagedPropertyType.string),
          SchemaColumn("columnToDelete", ManagedPropertyType.integer)
        ]),
        SchemaTable(
          "tableToDelete",
          [SchemaColumn("whocares", ManagedPropertyType.integer)],
        ),
        SchemaTable(
          "tableToRename",
          [SchemaColumn("whocares", ManagedPropertyType.integer)],
        )
      ]);

      final initialBuilder =
          SchemaBuilder.toSchema(store, schema, isTemporary: true);
      for (final cmd in initialBuilder.commands) {
        await store.execute(cmd);
      }

      final mig = Migration1();
      mig.version = 1;
      // ignore: unnecessary_cast
      final outSchema = await (store.upgrade(schema, [mig], temporary: true)
          as FutureOr<Schema?>);

      expect(outSchema, isNotNull);

      // 'Sync up' that schema to compare it
      final tableToKeep = schema.tableForName("tableToKeep")!;
      tableToKeep.addColumn(
        SchemaColumn(
          "addedColumn",
          ManagedPropertyType.integer,
          defaultValue: "2",
        ),
      );
      tableToKeep.removeColumn(tableToKeep.columnForName("columnToDelete")!);
      tableToKeep.columnForName("columnToEdit")!.defaultValue = "'foo'";

      schema.removeTable(schema.tableForName("tableToDelete")!);

      schema.addTable(
        SchemaTable("foo", [
          SchemaColumn("foobar", ManagedPropertyType.integer, isIndexed: true)
        ]),
      );

      expect(outSchema!.differenceFrom(schema).hasDifferences, false);

      final insertResults = await store.execute(
        "INSERT INTO tableToKeep (columnToEdit) VALUES ('1') RETURNING columnToEdit, addedColumn",
      );
      expect(insertResults, [
        ['1', 2]
      ]);
    });
  });

  group("Scanning for migration files", () {
    final temporaryDirectory = Directory("migration_tmp");
    final migrationsDirectory =
        Directory.fromUri(temporaryDirectory.uri.resolve("migrations"));
    addFiles(List<String> filenames) {
      for (final name in filenames) {
        File.fromUri(migrationsDirectory.uri.resolve(name))
            .writeAsStringSync(" ");
      }
    }

    addValidMigrationFile(List<String> filenames) {
      for (final name in filenames) {
        File.fromUri(migrationsDirectory.uri.resolve(name))
            .writeAsStringSync("""
class Migration1 extends Migration { @override Future upgrade() async {} @override Future downgrade() async {} @override Future seed() async {} }
        """);
      }
    }

    setUp(() {
      temporaryDirectory.createSync();
      migrationsDirectory.createSync();
    });

    tearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });

    test("Ignores not .migration.dart files", () async {
      addValidMigrationFile(
        ["00000001.migration.dart", "a_foo.migration.dart"],
      );
      addFiles(["foobar.txt", ".DS_Store", "a.dart", "migration.dart"]);
      expect(migrationsDirectory.listSync().length, 6);

      final mock = MockMigratable(temporaryDirectory);
      final files = mock.projectMigrations;
      expect(files.length, 1);
      expect(
        Uri.parse(files.first.uri!).pathSegments.last,
        "00000001.migration.dart",
      );
    });

    test("Migration files are ordered correctly", () async {
      addValidMigrationFile([
        "00000001.migration.dart",
        "2.migration.dart",
        "03_Foo.migration.dart",
        "10001_.migration.dart",
        "000001001.migration.dart"
      ]);
      expect(migrationsDirectory.listSync().length, 5);

      final mock = MockMigratable(temporaryDirectory);
      final files = mock.projectMigrations;
      expect(files.length, 5);
      expect(
        Uri.parse(files[0].uri!).pathSegments.last,
        "00000001.migration.dart",
      );
      expect(Uri.parse(files[1].uri!).pathSegments.last, "2.migration.dart");
      expect(
        Uri.parse(files[2].uri!).pathSegments.last,
        "03_Foo.migration.dart",
      );
      expect(
        Uri.parse(files[3].uri!).pathSegments.last,
        "000001001.migration.dart",
      );
      expect(
        Uri.parse(files[4].uri!).pathSegments.last,
        "10001_.migration.dart",
      );
    });
  });
}

class Migration1 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(
      SchemaTable("foo", [
        SchemaColumn("foobar", ManagedPropertyType.integer, isIndexed: true)
      ]),
    );

    //database.renameTable(currentSchema["tableToRename"], "renamedTable");
    database.deleteTable("tableToDelete");

    database.addColumn(
      "tableToKeep",
      SchemaColumn(
        "addedColumn",
        ManagedPropertyType.integer,
        defaultValue: "2",
      ),
    );
    database.deleteColumn("tableToKeep", "columnToDelete");
    //database.renameColumn()
    database.alterColumn("tableToKeep", "columnToEdit", (col) {
      col.defaultValue = "'foo'";
    });
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class MockMigratable extends CLICommand
    with CLIDatabaseManagingCommand, CLIProject {
  MockMigratable(this.projectDirectory) {
    migrationDirectory =
        Directory.fromUri(projectDirectory.uri.resolve("migrations"));
  }

  @override
  Directory? migrationDirectory;

  @override
  Directory projectDirectory;

  @override
  Future<int> handle() async => 0;

  @override
  String get description => "";

  @override
  String get name => "";
}
