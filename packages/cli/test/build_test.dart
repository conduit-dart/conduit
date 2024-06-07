import 'dart:io';

import 'package:fs_test_agent/dart_project_agent.dart';
import 'package:fs_test_agent/working_directory_agent.dart';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;

import 'not_tests/cli_helpers.dart';

void main() {
  late CLIClient cli;
  final pids = [];

  setUpAll(() async {
    await CLIClient.activateCLI();
    final terminal = WorkingDirectoryAgent(DartProjectAgent.projectsDirectory);
    cli = CLIClient(terminal);
  });

  setUp(() async {
    await cli.run(
      "create",
      [
        "test_project",
        "--offline",
        "--stacktrace",
      ],
    );
  });

  tearDown(() {
    DartProjectAgent.projectsDirectory.listSync().forEach((e) {
      e.deleteSync(recursive: true);
    });
    cli.clearOutput();
  });

  tearDownAll(() {
    DartProjectAgent.tearDownAll();
    pids.forEach((p) {
      Process.killPid(p);
    });
  });

  test("Build works", () async {
    final res = await cli.run(
      "build",
      [
        "--directory",
        "test_project/",
      ],
    );
    expect(res, 0);
    final binPath = cli.agent.workingDirectory.uri
        .resolve("test_project/test_project.aot")
        .toFilePath(windows: Platform.isWindows);
    expect(
      File(
        binPath,
      ).existsSync(),
      isTrue,
    );

    final binRes = await Process.start(binPath, []);
    pids.add(binRes.pid);

    expect(String.fromCharCodes(await binRes.stdout.first),
        contains("[INFO] conduit: Server conduit/1 started."));
    Process.killPid(binRes.pid);
  });

  test("Build works with define", () async {
    final File mainFile = File(cli.agent.workingDirectory.uri
        .resolve("test_project/lib/channel.dart")
        .toFilePath(windows: Platform.isWindows));
    await mainFile.readAsString().then((String source) {
      mainFile.writeAsStringSync(source.replaceFirst(
          'return Response.ok({"key": "value"});',
          '''const lit = String.fromEnvironment("FOO");
          return Response.ok({"key": lit});'''));
    });

    final res = await cli.run("build", [
      "--define=FOO=BAR",
      "--directory",
      "test_project/",
    ]);
    expect(res, 0);

    final binPath = cli.agent.workingDirectory.uri
        .resolve("test_project/test_project.aot")
        .toFilePath(windows: Platform.isWindows);
    expect(
      File(
        binPath,
      ).existsSync(),
      isTrue,
    );

    final binRes = await Process.start(binPath, []);
    pids.add(binRes.pid);
    expect(String.fromCharCodes(await binRes.stdout.first),
        contains("[INFO] conduit: Server conduit/1 started."));
    final response = await http.get(Uri.parse('http://0.0.0.0:8888/example'));
    expect(response.body, contains("BAR"));
    Process.killPid(binRes.pid);
  });
}
