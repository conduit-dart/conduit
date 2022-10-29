@Timeout(Duration(seconds: 45))
// ignore: unnecessary_const
@Tags(["cli"])
import 'dart:async';
import 'dart:io';

import 'package:fs_test_agent/dart_project_agent.dart';
import 'package:fs_test_agent/working_directory_agent.dart';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart' as yaml;

import '../not_tests/cli_helpers.dart';

File get certificateFile => File.fromUri(Directory.current.uri
    .resolve("../../")
    .resolve("ci/")
    .resolve("conduit.cert.pem"));

File get keyFile => File.fromUri(Directory.current.uri
    .resolve("../../")
    .resolve("ci/")
    .resolve("conduit.key.pem"));

void main() {
  late CLIClient templateCli;
  late CLIClient projectUnderTestCli;
  late CLITask task;

  setUpAll(() async {
    templateCli = await CLIClient(
            WorkingDirectoryAgent(DartProjectAgent.projectsDirectory))
        .createTestProject();
    await templateCli.agent.getDependencies(offline: true);
  });

  setUp(() async {
    projectUnderTestCli = templateCli.replicate(Uri.parse("replica/"));
  });

  tearDown(() async {
    await task.process?.stop(0);
  });

  tearDownAll(DartProjectAgent.tearDownAll);

  test("Served application starts and responds to route", () async {
    task = projectUnderTestCli.start("serve", ["-n", "1"]);
    await task.hasStarted;
    expect(projectUnderTestCli.output, contains("Port: 8888"));
    expect(projectUnderTestCli.output, contains("config.yaml"));

    final thisPubspec = yaml.loadYaml(
        File.fromUri(Directory.current.uri.resolve("pubspec.yaml"))
            .readAsStringSync());
    final thisVersion = Version.parse(thisPubspec["version"] as String);
    expect(projectUnderTestCli.output, contains("CLI Version: $thisVersion"));
    expect(projectUnderTestCli.output,
        contains("Conduit project version: $thisVersion"));

    final result = await http.get(Uri.parse("http://localhost:8888/example"));
    expect(result.statusCode, 200);

    // ignore: unawaited_futures
    task.process!.stop(0);
    expect(await task.exitCode, 0);
  });

  test("Ensure we don't find the base ApplicationChannel class", () async {
    projectUnderTestCli.agent.addOrReplaceFile(
        "lib/application_test.dart", "import 'package:conduit/conduit.dart';");

    task = projectUnderTestCli.start("serve", ["-n", "1"]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((e) => e);

    expect(await task.exitCode, isNot(0));
    expect(
        projectUnderTestCli.output, contains("No ApplicationChannel subclass"));
  });

  test("Exception throw during initializeApplication halts startup", () async {
    projectUnderTestCli.agent.modifyFile("lib/channel.dart", (contents) {
      return contents.replaceFirst(
          "extends ApplicationChannel {", """extends ApplicationChannel {
static Future initializeApplication(ApplicationOptions x) async { throw Exception("error"); }            
      """);
    });

    task = projectUnderTestCli.start("serve", ["-n", "1"]);

    // ignore: unawaited_futures
    task.hasStarted.catchError((e) => e);
    expect(await task.exitCode, isNot(0));
    expect(projectUnderTestCli.output, contains("Application failed to start"));
    expect(projectUnderTestCli.output,
        contains("Exception: error")); // error generated
    expect(projectUnderTestCli.output,
        contains("TestChannel.initializeApplication")); // stacktrace
  });

  test("Start with valid SSL args opens https server", () async {
    certificateFile.copySync(projectUnderTestCli.agent.workingDirectory.uri
        .resolve("server.crt")
        .toFilePath(windows: Platform.isWindows));
    keyFile.copySync(projectUnderTestCli.agent.workingDirectory.uri
        .resolve("server.key")
        .toFilePath(windows: Platform.isWindows));

    task = projectUnderTestCli.start("serve", [
      "--ssl-key-path",
      "server.key",
      "--ssl-certificate-path",
      "server.crt",
      "-n",
      "1"
    ]);
    await task.hasStarted;

    final completer = Completer<List<int>>();
    final socket = await SecureSocket.connect("localhost", 8888,
        onBadCertificate: (_) => true);
    const request =
        "GET /example HTTP/1.1\r\nConnection: close\r\nHost: localhost\r\n\r\n";
    socket.add(request.codeUnits);

    socket.listen(completer.complete);
    final httpResult = String.fromCharCodes(await completer.future);
    expect(httpResult, contains("200 OK"));
    await socket.close();
  });

  test("Start without one of SSL values throws exception", () async {
    certificateFile.copySync(projectUnderTestCli.agent.workingDirectory.uri
        .resolve("server.crt")
        .toFilePath(windows: Platform.isWindows));
    keyFile.copySync(projectUnderTestCli.agent.workingDirectory.uri
        .resolve("server.key")
        .toFilePath(windows: Platform.isWindows));

    task = projectUnderTestCli
        .start("serve", ["--ssl-key-path", "server.key", "-n", "1"]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((e) => e);
    expect(await task.exitCode, isNot(0));

    task = projectUnderTestCli
        .start("serve", ["--ssl-certificate-path", "server.crt", "-n", "1"]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((e) => e);
    expect(await task.exitCode, isNot(0));
  });

  test("Start with invalid SSL values throws exceptions", () async {
    keyFile.copySync(projectUnderTestCli.agent.workingDirectory.uri
        .resolve("server.key")
        .toFilePath(windows: Platform.isWindows));

    final badCertFile = File.fromUri(
        projectUnderTestCli.agent.workingDirectory.uri.resolve("server.crt"));
    badCertFile.writeAsStringSync("foobar");

    task = projectUnderTestCli.start("serve", [
      "--ssl-key-path",
      "server.key",
      "--ssl-certificate-path",
      "server.crt",
      "-n",
      "1"
    ]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((e) => e);
    expect(await task.exitCode, isNot(0));
  });

  test("Can't find SSL file, throws exception", () async {
    keyFile.copySync(projectUnderTestCli.agent.workingDirectory.uri
        .resolve("server.key")
        .toFilePath(windows: Platform.isWindows));

    task = projectUnderTestCli.start("serve", [
      "--ssl-key-path",
      "server.key",
      "--ssl-certificate-path",
      "server.crt",
      "-n",
      "1"
    ]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((e) => e);
    expect(await task.exitCode, isNot(0));
  });

  test("Run application with invalid code fails with error", () async {
    projectUnderTestCli.agent.modifyFile("lib/channel.dart", (contents) {
      return contents.replaceFirst("import", "importasjakads");
    });

    task = projectUnderTestCli.start("serve", ["-n", "1"]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((e) => e);

    expect(await task.exitCode, isNot(0));
    expect(projectUnderTestCli.output,
        contains("Variables must be declared using the keywords"));
  });

  test("Use config-path, relative path", () async {
    projectUnderTestCli.agent.addOrReplaceFile("foobar.yaml", "key: value");
    projectUnderTestCli.agent.modifyFile("lib/channel.dart", (c) {
      final newContents = c.replaceAll('return Response.ok({"key": "value"});',
          "return Response.ok(File(options!.configurationFilePath!).readAsStringSync())..contentType = ContentType.text;");
      return "import 'dart:io';\n$newContents";
    });

    task = projectUnderTestCli
        .start("serve", ["--config-path", "foobar.yaml", "-n", "1"]);
    await task.hasStarted;

    final result = await http.get(Uri.parse("http://localhost:8888/example"));
    expect(result.body, contains("key: value"));
  });

  test("Use config-path, absolute path", () async {
    projectUnderTestCli.agent.addOrReplaceFile("foobar.yaml", "key: value");
    projectUnderTestCli.agent.modifyFile("lib/channel.dart", (c) {
      final newContents = c.replaceAll('return Response.ok({"key": "value"});',
          "return Response.ok(File(options!.configurationFilePath!).readAsStringSync())..contentType = ContentType.text;");
      return "import 'dart:io';\n$newContents";
    });

    task = projectUnderTestCli.start("serve", [
      "--config-path",
      projectUnderTestCli.agent.workingDirectory.uri
          .resolve("foobar.yaml")
          .toFilePath(windows: Platform.isWindows),
      "-n",
      "1"
    ]);
    await task.hasStarted;

    final result = await http.get(Uri.parse("http://localhost:8888/example"));
    expect(result.body, contains("key: value"));
  });
}
