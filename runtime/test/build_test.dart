import 'dart:convert';
import 'dart:io';

import 'package:conduit_runtime/runtime.dart';
import 'build_test.reflectable.dart';
import 'package:test/test.dart';

/*
need test with normal package, relative package, git package
need to test for local (relative), in pub cache (absolute)
*/

void main() {
  initializeReflectable();
  final testPackagesUri =
      Directory.current.parent.uri.resolve('runtime_test_packages/');
  final tmp =
      Directory.current.parent.uri.resolve("tmp/").resolve('application/');

  setUpAll(() async {
    String cmd;
    if (Platform.isWindows) {
      cmd = (await Process.run("where", ["pub.bat"])).stdout;
    } else {
      cmd = (await Process.run("which", ["pub"])).stdout;
    }
    cmd = cmd.replaceAll('\n', '');

    final appDir = testPackagesUri.resolve("application/");
    await Process.run(cmd, ["get", "--offline"],
        workingDirectory: appDir.toFilePath(windows: Platform.isWindows),
        runInShell: true);
    await Process.run(cmd, ["get", "--offline"],
        workingDirectory: testPackagesUri
            .resolve("dependency/")
            .toFilePath(windows: Platform.isWindows),
        runInShell: true);
    final appLib = appDir.resolve("lib/").resolve("application.dart");

    final ctx = BuildContext(
        appLib,
        tmp,
        tmp.resolve("app.aot"),
        File.fromUri(appDir.resolve("bin/").resolve("main.dart"))
            .readAsStringSync());
    final bm = BuildManager(ctx);
    await bm.build();
  });

  // tearDownAll(() {
  //   final tmpDir = Directory(tmp.toFilePath(windows: Platform.isWindows));
  //   if (tmpDir.existsSync()) {
  //     tmpDir.deleteSync(recursive: true);
  //   }
  // });

  // tearDown(() {
  //   final tmpDir =
  //       Directory(tmp.resolve('../').toFilePath(windows: Platform.isWindows));
  //   if (tmpDir.existsSync()) {
  //     tmpDir.deleteSync(recursive: true);
  //   }
  // });

  test("Non-compiled version returns mirror runtimes", () {
    final output = dart(testPackagesUri.resolve("application/"));
    expect(json.decode(output), {
      "Consumer": "mirrored",
      "ConsumerSubclass": "mirrored",
      "ConsumerScript": "mirrored",
    });
  });

  test("Application can be AOT compiled", () {
    final output = runExecutable(
        tmp.resolve("app.aot"), testPackagesUri.resolve("application/"));
    expect(json.decode(output), {
      "Consumer": "mirrored",
      "ConsumerSubclass": "mirrored",
      "ConsumerScript": "mirrored",
    });
  });
}

String dart(Uri workingDir) {
  final result = Process.runSync(
    "dart",
    ["bin/main.dart"],
    workingDirectory: workingDir.toFilePath(windows: Platform.isWindows),
    runInShell: true,
  );
  if (result.exitCode != 0) {
    throw StateError('Running dart failed with: ${result.stderr}');
  }
  return result.stdout.toString();
}

String runExecutable(Uri buildUri, Uri workingDir) {
  final result = Process.runSync(
      buildUri.toFilePath(windows: Platform.isWindows), [],
      workingDirectory: workingDir.toFilePath(windows: Platform.isWindows),
      runInShell: true);
  if (result.exitCode != 0) {
    throw StateError('Running executable failed with: ${result.stderr}');
  }
  return result.stdout.toString();
}
