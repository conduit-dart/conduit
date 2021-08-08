import 'dart:async';
import 'dart:io';

import 'package:conduit_runtime/runtime.dart';

Future main(List<String> args) async {
  final conduitDir = Directory.current.parent.uri.resolve('conduit/');
  final blacklist = [
    (String s) => s.contains('test/command/'),
    (String s) => s.contains('/compilation_errors/'),
    (String s) => s.contains('test/openapi/'),
    (String s) => s.contains('postgresql/migration/'),
    (String s) => s.contains('db/migration/'),
    (String s) => s.endsWith('entity_mirrors_test.dart'),
    (String s) => s.endsWith('moc_openapi_test.dart'),
    (String s) => s.endsWith('auth_documentation_test.dart'),
    (String s) => s.endsWith('entity_mirrors_test.dart'),
    (String s) => s.endsWith('cli/command_test.dart'),
  ];

  List<File> testFiles;

  if (args.length == 1) {
    testFiles = [File(args.first)];
  } else {
    final testDir = args.isNotEmpty
        ? conduitDir.resolveUri(Uri.parse(args[0]))
        : conduitDir.resolve('test/');

    testFiles = Directory.fromUri(testDir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('_test.dart'))
        .where((f) => blacklist.every(
            (blacklistFunction) => blacklistFunction(f.uri.path) == false))
        .toList();
  }
  var remainingCounter = testFiles.length;
  final passingFiles = <File>[];
  final failingFiles = <File>[];
  for (var f in testFiles) {
    final currentTime = DateTime.now();
    final makePrompt = () =>
        '(Pass: ${passingFiles.length} Fail: ${failingFiles.length} Remain: $remainingCounter)';

    print('Running tests derived from ${f.path}...');
    final ctx = BuildContext(
        conduitDir.resolve('lib/').resolve('conduit.dart'),
        Directory.current.parent.uri.resolve('_build/'),
        Directory.current.parent.uri.resolve('run'),
        File(conduitDir.resolve(f.path).path).readAsStringSync(),
        forTests: true);
    final bm = BuildManager(ctx);
    await bm.build();

    final result = await Process.start('dart', ['test/main_test.dart'],
        workingDirectory:
            ctx.buildDirectoryUri.toFilePath(windows: Platform.isWindows),
        environment: {
          'CONDUIT_CI_DIR_LOCATION': Directory.current.parent.uri
              .resolve('ci/')
              .toFilePath(windows: Platform.isWindows)
        });
    // ignore: unawaited_futures
    stdout.addStream(result.stdout);
    // ignore: unawaited_futures
    stderr.addStream(result.stderr);

    if (await result.exitCode != 0) {
      exitCode = -1;
      failingFiles.add(f);
      print('Tests FAILED in ${f.path}.');
    } else {
      passingFiles.add(f);
    }

    final elapsed = DateTime.now().difference(currentTime);
    remainingCounter--;
    print(
        '${makePrompt()} (${elapsed.inSeconds}s) Completed tests derived from ${f.path}.');
    await bm.clean();
  }

  print('==============');
  print('Result Summary');
  print('==============');

  final testRoot =
      Directory.current.parent.uri.resolve('conduit/').resolve('test/');
  String stripParentDir(Uri uri) {
    final testPathList = uri.pathSegments;
    final parentDirPathList = testRoot.pathSegments;
    final components = testPathList.skip(parentDirPathList.length - 1);

    return components.join('/');
  }

  passingFiles.forEach((f) {
    print('  ${stripParentDir(f.uri)}: success');
  });
  failingFiles.forEach((f) {
    print('  ${stripParentDir(f.uri)}: FAILURE');
  });
}
