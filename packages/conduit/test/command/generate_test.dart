// ignore: unnecessary_const
@Tags(["cli"])
import 'dart:io';
import 'package:fs_test_agent/dart_project_agent.dart';
import 'package:fs_test_agent/working_directory_agent.dart';
import 'package:test/test.dart';
import '../not_tests/cli_helpers.dart';

void main() {
  late CLIClient templateCli;
  late CLIClient projectUnderTestCli;

  setUpAll(() async {
    templateCli = await CLIClient(
      WorkingDirectoryAgent(DartProjectAgent.projectsDirectory),
    ).createTestProject();
    await templateCli.agent.getDependencies();
  });

  tearDownAll(DartProjectAgent.tearDownAll);

  setUp(() async {
    projectUnderTestCli = templateCli.replicate(Uri.parse("replica/"));
    projectUnderTestCli.projectAgent.addLibraryFile("application_test", """
import 'package:conduit/conduit.dart';

class TestObject extends ManagedObject<_TestObject> {}

class _TestObject {
  @primaryKey
  int? id;

  String? foo;
}
      """);
  });

  tearDown(() {
    projectUnderTestCli.delete();
  });

  test("Run without pub get yields error", () async {
    File.fromUri(
      projectUnderTestCli.agent.workingDirectory.uri.resolve("pubspec.lock"),
    ).deleteSync();
    File.fromUri(
      projectUnderTestCli.agent.workingDirectory.uri
          .resolve(".dart_tool/package_config.json"),
    ).deleteSync();

    final res = await projectUnderTestCli.run("db", ["generate"]);
    expect(res, isNot(0));
  });

  test("Ensure migration directory will get created on generation", () async {
    expect(projectUnderTestCli.defaultMigrationDirectory.existsSync(), false);
    final res = await projectUnderTestCli.run("db", ["generate"]);
    expect(res, isZero);
    expect(projectUnderTestCli.defaultMigrationDirectory.existsSync(), true);
  });

  test(
      "If there are no migration files, create an initial one that validates to schema",
      () async {
    // Putting a non-migration file in there to ensure that this doesn't prevent from being ugpraded
    projectUnderTestCli.defaultMigrationDirectory.createSync();
    projectUnderTestCli.agent
        .addOrReplaceFile("migrations/notmigration.dart", " ");

    var res = await projectUnderTestCli.run("db", ["generate"]);
    expect(res, isZero);
    projectUnderTestCli.clearOutput();

    res = await projectUnderTestCli.run("db", ["validate"]);
    expect(res, isZero);
  });

  test(
      "If there is already a migration file, create an upgrade file with changes",
      () async {
    var res = await projectUnderTestCli.run("db", ["generate"]);
    expect(res, isZero);
    projectUnderTestCli.clearOutput();

    // Let's add an index
    projectUnderTestCli.agent.modifyFile("lib/application_test.dart", (prev) {
      return prev.replaceFirst(
        "String? foo;",
        "@Column(indexed: true) String? foo;",
      );
    });

    res = await projectUnderTestCli.run("db", ["generate"]);
    expect(res, isZero);
    projectUnderTestCli.clearOutput();

    expect(
      projectUnderTestCli.defaultMigrationDirectory
          .listSync()
          .where((fse) => !fse.uri.pathSegments.last.startsWith(".")),
      hasLength(2),
    );
    expect(
      File.fromUri(
        projectUnderTestCli.defaultMigrationDirectory.uri
            .resolve("00000001_initial.migration.dart"),
      ).existsSync(),
      isTrue,
    );
    expect(
      File.fromUri(
        projectUnderTestCli.defaultMigrationDirectory.uri
            .resolve("00000002_unnamed.migration.dart"),
      ).existsSync(),
      isTrue,
    );

    res = await projectUnderTestCli.run("db", ["validate"]);
    expect(res, isZero);
  });

  test("Can specify migration name other than default", () async {
    var res = await projectUnderTestCli
        .run("db", ["generate", "--name", "InitializeDatabase"]);

    expect(res, isZero);
    projectUnderTestCli.clearOutput();

    // Let's add an index
    projectUnderTestCli.agent.modifyFile(
      "lib/application_test.dart",
      (prev) {
        return prev.replaceFirst(
          "String? foo;",
          "@Column(indexed: true) String? foo;",
        );
      },
    );

    res = await projectUnderTestCli
        .run("db", ["generate", "--name", "add_index"]);
    expect(res, isZero);
    projectUnderTestCli.clearOutput();

    expect(
      projectUnderTestCli.defaultMigrationDirectory
          .listSync()
          .where((fse) => !fse.uri.pathSegments.last.startsWith(".")),
      hasLength(2),
    );
    expect(
      File.fromUri(
        projectUnderTestCli.defaultMigrationDirectory.uri
            .resolve("00000001_initialize_database.migration.dart"),
      ).existsSync(),
      isTrue,
    );
    expect(
      File.fromUri(
        projectUnderTestCli.defaultMigrationDirectory.uri
            .resolve("00000002_add_index.migration.dart"),
      ).existsSync(),
      isTrue,
    );

    res = await projectUnderTestCli.run("db", ["validate"]);
    expect(res, isZero);
  });

  test(
    "Can specify migration directory other than default, relative path",
    () async {
      final res = await projectUnderTestCli
          .run("db", ["generate", "--migration-directory", "foobar"]);
      expect(res, isZero);

      final migDir = Directory.fromUri(
        projectUnderTestCli.agent.workingDirectory.uri.resolve("foobar/"),
      );
      final files = migDir.listSync();
      expect(
        files.any((fse) => fse is File && fse.path.endsWith("migration.dart")),
        isTrue,
      );
    },
  );

  test("Can specify migration directory other than default, absolute path",
      () async {
    final migDir = Directory.fromUri(
      projectUnderTestCli.agent.workingDirectory.uri.resolve("foobar/"),
    );
    final res = await projectUnderTestCli.run(
      "db",
      [
        "generate",
        "--migration-directory",
        migDir.uri.toFilePath(windows: Platform.isWindows)
      ],
    );
    expect(res, isZero);

    final files = migDir.listSync();
    expect(
      files.any((fse) => fse is File && fse.path.endsWith("migration.dart")),
      isTrue,
    );
  });

  test(
    "If migration file requires additional input, send message to user",
    () async {
      var res = await projectUnderTestCli.run("db", ["generate"]);
      expect(res, isZero);
      projectUnderTestCli.clearOutput();

      projectUnderTestCli.agent.modifyFile(
        "lib/application_test.dart",
        (prev) {
          return prev.replaceFirst(
            "String? foo;",
            "String? foo;\nString? bar;",
          );
        },
      );
      res = await projectUnderTestCli.run("db", ["generate"]);
      expect(res, isZero);

      expect(projectUnderTestCli.output, contains("may fail"));
      expect(projectUnderTestCli.output, contains('"_TestObject"'));
      expect(projectUnderTestCli.output, contains('"bar"'));
    },
  );
}
