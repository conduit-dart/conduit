// ignore: unnecessary_const
@Tags(const ["cli"])
import 'dart:io';

import 'package:path/path.dart' as path_lib;
import 'package:pub_semver/pub_semver.dart';
import 'package:fs_test_agent/dart_project_agent.dart';
import 'package:fs_test_agent/working_directory_agent.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../not_tests/cli_helpers.dart';

void main() {
  late CLIClient cli;

  setUpAll(() async {
    await CLIClient.activateCLI();
    final terminal = WorkingDirectoryAgent(DartProjectAgent.projectsDirectory);
    cli = CLIClient(terminal);
  });

  tearDown(() {
    DartProjectAgent.projectsDirectory.listSync().forEach((e) {
      e.deleteSync(recursive: true);
    });
    cli.clearOutput();
  });

  tearDownAll(() {
    DartProjectAgent.tearDownAll();
    CLIClient.deactivateCLI();
  });

  group("Project naming", () {
    test("Appropriately named project gets created correctly", () async {
      final res = await cli.run(
        "create",
        [
          "test_project",
          "--offline",
          "--stacktrace",
        ],
      );
      expect(res, 0);

      expect(
        Directory.fromUri(
          cli.agent.workingDirectory.uri.resolve("test_project/"),
        ).existsSync(),
        isTrue,
      );
    });

    test("Project name with bad characters fails immediately", () async {
      final res = await cli.run("create", ["!@", "--offline"]);
      expect(res, isNot(0));
      expect(cli.output, contains("Invalid project name"));
      expect(cli.output, contains("snake_case"));

      expect(DartProjectAgent.projectsDirectory.listSync().isEmpty, isTrue);
    });

    test("Project name with uppercase characters fails immediately", () async {
      final res = await cli.run("create", ["ANeatApp", "--offline"]);
      expect(res, isNot(0));
      expect(cli.output, contains("Invalid project name"));
      expect(cli.output, contains("snake_case"));

      expect(
        Directory.fromUri(
          cli.agent.workingDirectory.uri.resolve("test_project/"),
        ).existsSync(),
        isFalse,
      );
    });

    test("Project name with dashes fails immediately", () async {
      final res = await cli.run("create", ["a-neat-app", "--offline"]);
      expect(res, isNot(0));
      expect(cli.output, contains("Invalid project name"));
      expect(cli.output, contains("snake_case"));

      expect(
        Directory.fromUri(
          cli.agent.workingDirectory.uri.resolve("test_project/"),
        ).existsSync(),
        isFalse,
      );
    });

    test("Not providing name returns error", () async {
      final res = await cli.run("create");
      expect(res, isNot(0));
    });
  });

  group("Templates", () {
    test("Listed templates are accurate", () async {
      // This test will fail if you add or change the name of a template.
      // If you are adding a template, just add it to this list. If you are renaming/deleting a template,
      // make sure there is still a 'default' template.
      await cli.run("create", ["list-templates"]);
      var names = ["db", "db_and_auth", "default"];
      var lines = cli.output.split("\n");

      expect(lines.length, names.length + 4);
      for (var n in names) {
        expect(lines.any((l) => l.startsWith("\x1B[0m    $n ")), isTrue);
      }
    });

    test("Template gets generated from local path, project points to it",
        () async {
      var res = await cli.run("create", ["test_project", "--offline"]);
      expect(res, 0);

      var conduitLocationString = File.fromUri(cli.agent.workingDirectory.uri
              .resolve("test_project/")
              .resolve(".packages"))
          .readAsStringSync()
          .split("\n")
          .firstWhere((p) => p.startsWith("conduit:"))
          .split("conduit:")
          .last;

      var path = path_lib.normalize(path_lib.fromUri(conduitLocationString));
      expect(path, path_lib.join(Directory.current.path, "lib"));
    });

    /* for every template */
    final templates = Directory("templates")
        .listSync()
        .whereType<Directory>()
        .map((fse) => fse.uri.pathSegments[fse.uri.pathSegments.length - 2])
        .toList();
    final conduitPubspec = loadYaml(File("pubspec.yaml").readAsStringSync());
    final conduitVersion = Version.parse("${conduitPubspec["version"]}");

    for (var template in templates) {
      test(
        "Templates can use 'this' version of Conduit in their dependencies",
        () {
          var projectDir = Directory("templates/$template/");
          var pubspec = File.fromUri(projectDir.uri.resolve("pubspec.yaml"));
          var contents = loadYaml(pubspec.readAsStringSync());
          final projectVersionConstraint = VersionConstraint.parse(
            contents["dependencies"]["conduit"] as String,
          );
          expect(projectVersionConstraint.allows(conduitVersion), isTrue);
        },
      );

      test("Tests run on template generated from local path", () async {
        expect(
          await cli.run(
            "create",
            [
              "test_project",
              "-t",
              template,
              "--offline",
            ],
          ),
          isZero,
        );

        final cmd = Platform.isWindows ? "pub.bat" : "pub";
        var res = Process.runSync(
          cmd,
          ["run", "test", "-j", "1"],
          runInShell: true,
          workingDirectory: cli.agent.workingDirectory.uri
              .resolve("test_project")
              .toFilePath(windows: Platform.isWindows),
        );

        print(res.stdout);
        print(res.stderr);

        expect(res.stdout, contains("All tests passed"));
        expect(res.exitCode, 0);
      });
    }
  });
}
