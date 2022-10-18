// ignore: unnecessary_const
@Tags(["cli"])
import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:conduit/conduit.dart';
import 'package:conduit/src/cli/migration_source.dart';
import 'package:conduit_common_test/conduit_common_test.dart';
import 'package:conduit_runtime/src/analyzer.dart';
import 'package:fs_test_agent/dart_project_agent.dart';
import 'package:fs_test_agent/working_directory_agent.dart';
import 'package:test/test.dart';

import '../not_tests/cli_helpers.dart';

late CLIClient cli;
DatabaseConfiguration connectInfo =
    PostgresTestConfig().databaseConfiguration();
String connectString =
    "postgres://${connectInfo.username}:${connectInfo.password}@${connectInfo.host}:${connectInfo.port}/${connectInfo.databaseName}";

void main() {
  late PostgreSQLPersistentStore store;

  setUpAll(() async {
    final t =
        CLIClient(WorkingDirectoryAgent(DartProjectAgent.projectsDirectory));
    cli = await t.createTestProject();
    await cli.agent.getDependencies(offline: true);
  });

  setUp(() async {
    // create a working directory to store migrations in, inside terminal temporary directory
    store = PostgreSQLPersistentStore(
        connectInfo.username,
        connectInfo.password,
        connectInfo.host,
        connectInfo.port,
        connectInfo.databaseName);

    if (cli.defaultMigrationDirectory.existsSync()) {
      cli.defaultMigrationDirectory.deleteSync(recursive: true);
    }
    cli.defaultMigrationDirectory.createSync();
  });

  tearDown(() async {
    var tables = [
      "_conduit_version_pgsql",
      "_foo",
      "_testobject",
    ];

    await Future.wait(tables.map((t) {
      return store.execute("DROP TABLE IF EXISTS $t");
    }));
    await store.close();
  });

  tearDownAll(DartProjectAgent.tearDownAll);

  test("Upgrade with no migration files returns 0 exit code", () async {
    expect(await runMigrationCases([]), isZero);
    expect(cli.output, contains("No migration files"));
  });

  test("Generate and execute initial schema makes workable DB", () async {
    expect(await runMigrationCases(["Case1"]), isZero);
    var version =
        await store.execute("SELECT versionNumber FROM _conduit_version_pgsql");
    expect(version, [
      [1]
    ]);
    expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
  });

  test(
    "Database already up to date returns 0 status code, does not change version",
    () async {
      expect(await runMigrationCases(["Case2"]), isZero);

      var versionRow = await store.execute(
        "SELECT versionNumber, dateOfUpgrade FROM _conduit_version_pgsql",
      ) as List<List<dynamic>>;
      expect(versionRow.first.first, 1);
      var updateDate = versionRow.first.last;

      cli.clearOutput();
      expect(await runMigrationCases(["Case2"]), isZero);
      versionRow = await store.execute(
        "SELECT versionNumber, dateOfUpgrade FROM _conduit_version_pgsql",
      ) as List<List>;
      expect(versionRow.length, 1);
      expect(versionRow.first.last, equals(updateDate));
      expect(cli.output, contains("already current (version: 1)"));
    },
  );

  test("Multiple migration files are ran", () async {
    expect(await runMigrationCases(["Case31", "Case32"]), isZero);

    var version =
        await store.execute("SELECT versionNumber FROM _conduit_version_pgsql");
    expect(version, [
      [1],
      [2]
    ]);
    expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
    expect(await columnsOfTable(store, "_foo"), ["id", "testobject_id"]);
  });

  test("Only later migration files are ran if already at a version", () async {
    expect(await runMigrationCases(["Case41"]), isZero);
    var version =
        await store.execute("SELECT versionNumber FROM _conduit_version_pgsql");
    expect(version, [
      [1]
    ]);
    cli.clearOutput();

    expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
    expect(await tableExists(store, "_foo"), isFalse);

    expect(await runMigrationCases(["Case42"], fromVersion: 1), isZero);
    version =
        await store.execute("SELECT versionNumber FROM _conduit_version_pgsql");
    expect(version, [
      [1],
      [2]
    ]);

    expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
    expect(await columnsOfTable(store, "_foo"), ["id", "testobject_id"]);
  });

  test("If migration throws exception, rollback any changes", () async {
    expect(await runMigrationCases(["Case5"]), isNonZero);

    expect(await tableExists(store, store.versionTable.name), isFalse);
    expect(await tableExists(store, "_testobject"), isFalse);
  });

  test(
    "Ensure that the following tests would succeed if the invalid migration were not applied",
    () async {
      expect(await runMigrationCases(["Case61", "Case63"]), isZero);
    },
  );

  test(
    "If migration fails and more migrations are pending, the pending migrations are cancelled",
    () async {
      expect(
        await runMigrationCases(["Case61", "Case62", "Case63"]),
        isNonZero,
      );

      expect(
        cli.output.contains("Applied schema version 1 successfully"),
        isTrue,
      );
      expect(cli.output, contains("relation \"_unknowntable\" does not exist"));

      expect(await tableExists(store, store.versionTable.name), isFalse);
      expect(await tableExists(store, "_testobject"), isFalse);
      expect(await tableExists(store, "_foo"), isFalse);
    },
  );

  test(
    "If migrations have already been applied, and new migrations occur where the first fails, those pending migrations are cancelled",
    () async {
      expect(await runMigrationCases(["Case61"]), isZero);
      expect(
        cli.output.contains("Applied schema version 1 successfully"),
        isTrue,
      );
      cli.clearOutput();

      expect(
        await runMigrationCases(["Case62", "Case63"], fromVersion: 1),
        isNonZero,
      );

      expect(cli.output, contains("relation \"_unknowntable\" does not exist"));

      final version = await store
          .execute("SELECT versionNumber FROM _conduit_version_pgsql");
      expect(version, [
        [1],
      ]);

      expect(await tableExists(store, store.versionTable.name), isTrue);
      expect(await tableExists(store, "_testobject"), isTrue);
      expect(await tableExists(store, "_foo"), isFalse);
    },
  );

  test("If seed fails, all schema changes are rolled back", () async {
    expect(await runMigrationCases(["Case7"]), isNonZero);

    expect(await tableExists(store, store.versionTable.name), isFalse);
    expect(await tableExists(store, "_testobject"), isFalse);
  });

  test(
    "If migration fails because adding a new non-nullable column to an table, a friendly error is emitted",
    () async {
      StringBuffer buf = StringBuffer();
      expect(
          await runMigrationCases(["Case81", "Case82"], log: buf), isNonZero);
      expect(buf.toString(), contains("adding or altering"));
      expect(buf.toString(), contains("_testobject.name"));
      expect(buf.toString(), contains("unencodedInitialValue"));
    },
  );
}

Future<List<String>> columnsOfTable(
  PersistentStore persistentStore,
  String tableName,
) async {
  final results = await persistentStore.execute(
    "select column_name from information_schema.columns "
    "where table_name='$tableName'",
  ) as List<List<dynamic>>;

  return results.map((rows) => rows.first as String).toList();
}

Future<bool> tableExists(PersistentStore store, String? tableName) async {
  final exists = await store.execute(
    "SELECT to_regclass(@tableName:text)",
    substitutionValues: {"tableName": tableName},
  ) as List<List<dynamic>>;

  return exists.first.first != null;
}

MigrationSource migrationSourceFromClassDeclaration(ClassDeclaration cu) {
  final code = cu.toSource();
  final offset = cu.name.offset - cu.offset;

  // uri is temporary
  return MigrationSource(
    code,
    Uri.parse("1.migration.dart"),
    offset,
    offset + cu.name.length,
  );
}

List<MigrationSource> getOrderedTestMigrations(
  List<String?> names, {
  int fromVersion = 0,
}) {
  final uri = Directory.current.uri
      .resolve("test/")
      .resolve("command/")
      .resolve("migration_execution_test.dart");

  final analyzer = CodeAnalyzer(uri);
  final migrations = analyzer
      .getSubclassesFromFile("Migration", analyzer.uri)
      .where((cu) => names.contains(cu.name.value()))
      .map(migrationSourceFromClassDeclaration)
      .toList();

  migrations.forEach((ms) {
    final index = names.indexOf(ms.originalName) + 1 + fromVersion;
    ms.uri = Uri.parse("$index.migration.dart");
  });

  return migrations;
}

Future runMigrationCases(List<String?> migrationNames,
    {int fromVersion = 0, StringSink? log}) async {
  final migs =
      getOrderedTestMigrations(migrationNames, fromVersion: fromVersion);

  for (var mig in migs) {
    final file = File.fromUri(cli.defaultMigrationDirectory.uri
        .resolve("${mig.versionNumber}_name.migration.dart"));
    file.writeAsStringSync(
      "import 'dart:async';\nimport 'package:conduit/conduit.dart';\n${mig.source}",
    );
  }

  String useSsl = Platform.environment["USE_SSL"] ?? "";

  final res =
      await cli.run("db", ["upgrade", useSsl, "--connect", connectString]);

  log?.write(cli.output);

  return res;
}

class Case1 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(SchemaTable(
      "_TestObject",
      [
        SchemaColumn(
          "id",
          ManagedPropertyType.bigInteger,
          isPrimaryKey: true,
          autoincrement: true,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
        SchemaColumn(
          "foo",
          ManagedPropertyType.string,
          isPrimaryKey: false,
          autoincrement: false,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case2 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(SchemaTable(
      "_TestObject",
      [
        SchemaColumn(
          "id",
          ManagedPropertyType.bigInteger,
          isPrimaryKey: true,
          autoincrement: true,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
        SchemaColumn(
          "foo",
          ManagedPropertyType.string,
          isPrimaryKey: false,
          autoincrement: false,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case31 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(SchemaTable(
      "_TestObject",
      [
        SchemaColumn(
          "id",
          ManagedPropertyType.bigInteger,
          isPrimaryKey: true,
          autoincrement: true,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
        SchemaColumn(
          "foo",
          ManagedPropertyType.string,
          isPrimaryKey: false,
          autoincrement: false,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case32 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(SchemaTable(
      "_Foo",
      [
        SchemaColumn(
          "id",
          ManagedPropertyType.bigInteger,
          isPrimaryKey: true,
          autoincrement: true,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
        SchemaColumn.relationship(
          "testObject",
          ManagedPropertyType.bigInteger,
          relatedTableName: "_TestObject",
          relatedColumnName: "id",
          rule: DeleteRule.nullify,
          isNullable: true,
          isUnique: true,
        ),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case41 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(SchemaTable(
      "_TestObject",
      [
        SchemaColumn(
          "id",
          ManagedPropertyType.bigInteger,
          isPrimaryKey: true,
          autoincrement: true,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
        SchemaColumn(
          "foo",
          ManagedPropertyType.string,
          isPrimaryKey: false,
          autoincrement: false,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case42 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(SchemaTable(
      "_Foo",
      [
        SchemaColumn(
          "id",
          ManagedPropertyType.bigInteger,
          isPrimaryKey: true,
          autoincrement: true,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
        SchemaColumn.relationship("testObject", ManagedPropertyType.bigInteger,
            relatedTableName: "_TestObject",
            relatedColumnName: "id",
            rule: DeleteRule.nullify,
            isNullable: true,
            isUnique: true),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case5 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(SchemaTable(
      "_TestObject",
      [
        SchemaColumn(
          "id",
          ManagedPropertyType.bigInteger,
          isPrimaryKey: true,
          autoincrement: true,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
        SchemaColumn(
          "foo",
          ManagedPropertyType.string,
          isPrimaryKey: false,
          autoincrement: false,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
      ],
    ));
    database.deleteTable("_Foo");
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case61 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(SchemaTable(
      "_TestObject",
      [
        SchemaColumn(
          "id",
          ManagedPropertyType.bigInteger,
          isPrimaryKey: true,
          autoincrement: true,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
        SchemaColumn(
          "foo",
          ManagedPropertyType.string,
          isPrimaryKey: false,
          autoincrement: false,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case62 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(SchemaTable(
      "_Foo",
      [
        SchemaColumn(
          "id",
          ManagedPropertyType.bigInteger,
          isPrimaryKey: true,
          autoincrement: true,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
        SchemaColumn.relationship("testObject", ManagedPropertyType.bigInteger,
            relatedTableName: "_UnknownTable",
            relatedColumnName: "id",
            rule: DeleteRule.nullify,
            isNullable: true,
            isUnique: true),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case63 extends Migration {
  @override
  Future upgrade() async {
    database.addColumn(
        "_TestObject",
        SchemaColumn(
          "name",
          ManagedPropertyType.string,
          isPrimaryKey: false,
          autoincrement: false,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
        unencodedInitialValue: "0");
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case7 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(SchemaTable(
      "_TestObject",
      [
        SchemaColumn(
          "id",
          ManagedPropertyType.bigInteger,
          isPrimaryKey: true,
          autoincrement: true,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
        SchemaColumn(
          "foo",
          ManagedPropertyType.string,
          isPrimaryKey: false,
          autoincrement: false,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {
    await database.store!
        .execute("INSERT INTO InvalidTable (foo) VALUES ('foo')");
  }
}

class Case81 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(SchemaTable(
      "_TestObject",
      [
        SchemaColumn(
          "id",
          ManagedPropertyType.bigInteger,
          isPrimaryKey: true,
          autoincrement: true,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {
    await store!.execute("INSERT INTO _TestObject VALUES (default)");
  }
}

class Case82 extends Migration {
  @override
  Future upgrade() async {
    database.addColumn(
        "_TestObject",
        SchemaColumn(
          "name",
          ManagedPropertyType.string,
          isPrimaryKey: false,
          autoincrement: false,
          isIndexed: false,
          isNullable: false,
          isUnique: false,
        ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}
