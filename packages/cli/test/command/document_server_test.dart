// ignore: unnecessary_const
@Tags(["cli"])
import 'dart:io';

import 'package:fs_test_agent/dart_project_agent.dart';
import 'package:fs_test_agent/working_directory_agent.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../not_tests/cli_helpers.dart';

void main() {
  late CLIClient templateCli;
  late CLIClient projectUnderTestCli;

  setUpAll(() async {
    await CLIClient.activateCLI();
    templateCli = await CLIClient(
      WorkingDirectoryAgent(DartProjectAgent.projectsDirectory),
    ).createTestProject();
    await templateCli.agent.getDependencies();
  });

  tearDownAll(() async {
    await CLIClient.deactivateCLI();
    DartProjectAgent.tearDownAll();
  });

  setUp(() async {
    projectUnderTestCli = templateCli.replicate(Uri.parse("replica/"));
  });

  tearDown(() {
    projectUnderTestCli.agent.workingDirectory.deleteSync(recursive: true);
  });

  test("Can get API reference", () async {
    final task = projectUnderTestCli.start("document", ["serve"]);
    await task.hasStarted;

    expect(
      Directory.fromUri(
        projectUnderTestCli.agent.workingDirectory.uri
            .resolve(".conduit_spec/"),
      ).existsSync(),
      true,
    );

    final response = await http.get(Uri.parse("http://localhost:8111"));
    expect(response.body, contains("redoc spec-url='openapi.json'"));

    // ignore: unawaited_futures
    task.process!.stop(0);
    expect(await task.exitCode, 0);
    expect(
      Directory.fromUri(
        projectUnderTestCli.agent.workingDirectory.uri
            .resolve(".conduit_spec/"),
      ).existsSync(),
      false,
    );
  });
}
