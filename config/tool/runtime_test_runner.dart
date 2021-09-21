// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:conduit_runtime/runtime.dart';

Future main(List<String> args) async {
  final blacklist = ["no_default_constructor_test.dart"];
  final testFiles = Directory.fromUri(Directory.current.uri.resolve("test/"))
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith("_test.dart"))
      .where(
        (f) => blacklist
            .where((blacklisted) => f.uri.path.endsWith(blacklisted))
            .isEmpty,
      )
      .toList();

  var remainingCounter = testFiles.length;
  var passCounter = 0;
  var failCounter = 0;
  void prompt() => print(
        """
Test Files:
  Pass  : $passCounter
  Fail  : $failCounter
  Remain: $remainingCounter
  """,
      );
  for (final f in testFiles) {
    prompt();
    print("Loading test ${f.path}...");
    final ctx = BuildContext(
      Directory.current.uri.resolve("lib/").resolve("conduit_config.dart"),
      Directory.current.uri.resolve("build/"),
      Directory.current.uri.resolve("run"),
      f.readAsStringSync(),
      forTests: true,
    );
    final bm = BuildManager(ctx);
    await bm.build();

    print("Running tests derived from ${f.path}...");
    final result = await Process.start(
      "dart",
      ["test/main_test.dart"],
      workingDirectory:
          ctx.buildDirectoryUri.toFilePath(windows: Platform.isWindows),
      environment: {
        "TEST_BOOL": "true",
        "TEST_DB_ENV_VAR": "postgres://user:password@host:5432/dbname",
        "TEST_VALUE": "1"
      },
    );
    // ignore: unawaited_futures
    stdout.addStream(result.stdout);
    // ignore: unawaited_futures
    stderr.addStream(result.stderr);

    if (await result.exitCode != 0) {
      exitCode = -1;
      failCounter++;
      print("Tests FAILED in ${f.path}.");
    } else {
      passCounter++;
    }
    await bm.clean();
    remainingCounter--;
  }
  prompt();
}
