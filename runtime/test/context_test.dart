import 'dart:io';

import 'package:conduit_runtime/runtime.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main() {
  final testPackagesUri =
      Directory.current.parent.uri.resolve('runtime_test_packages/');
  final tmp =
      Directory.current.parent.uri.resolve("tmp/").resolve('application/');

  final absolutePathToAppLib = normalize(absolute(join(testPackagesUri
      .resolve("application/")
      .resolve("lib/")
      .toFilePath(windows: Platform.isWindows))));
  late BuildContext ctx;

  setUpAll(() {
    String cmd;
    if (Platform.isWindows) {
      cmd = (Process.runSync("where", ["pub.bat"])).stdout;
    } else {
      cmd = (Process.runSync("which", ["pub"])).stdout;
    }
    cmd = cmd.replaceAll('\n', '');

    final appDir = testPackagesUri.resolve("application/");
    Process.runSync(cmd, ["get", "--offline"],
        workingDirectory: appDir.toFilePath(windows: Platform.isWindows),
        runInShell: true);

    Process.runSync(cmd, ["get", "--offline"],
        workingDirectory: testPackagesUri
            .resolve("dependency/")
            .toFilePath(windows: Platform.isWindows),
        runInShell: true);
    final appLib = appDir.resolve("lib/").resolve("application.dart");
    ctx = BuildContext(
        appLib,
        tmp,
        tmp.resolve("app.aot"),
        File.fromUri(appDir.resolve("bin/").resolve("main.dart"))
            .readAsStringSync());
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

  test("Get import directives using single quotes", () {
    final imports = ctx.getImportDirectives(
        source:
            "import 'package:foo.dart';\nimport 'package:bar.dart'; class Foobar {}");
    expect(
        imports, ["import 'package:foo.dart';", "import 'package:bar.dart';"]);
  });
  test("Get import directives using double quotes", () {
    final imports = ctx.getImportDirectives(
        source:
            "import 'package:foo/foo.dart';\n import 'package:bar2/bar_.dart'; class Foobar {}");
    expect(imports,
        ["import 'package:foo/foo.dart';", "import 'package:bar2/bar_.dart';"]);
  });

  test("Find in file", () {
    final imports = ctx.getImportDirectives(
        uri: testPackagesUri
            .resolve("application/")
            .resolve("lib/")
            .resolve("application.dart"));
    expect(imports, [
      "import 'package:conduit_runtime/runtime.dart';",
      "import 'package:dependency/dependency.dart';",
      "import 'file:${absolutePathToAppLib}/src/file.dart';"
    ]);
  });

  test("Resolve input URI and resolves import relative paths", () {
    final imports = ctx.getImportDirectives(
        uri: Uri.parse("package:application/application.dart"));
    expect(imports, [
      "import 'package:conduit_runtime/runtime.dart';",
      "import 'package:dependency/dependency.dart';",
      "import 'file:${absolutePathToAppLib}/src/file.dart';"
    ]);
  });

  test("Resolve src files and parent directories", () {
    final imports = ctx.getImportDirectives(
        uri: Uri.parse("package:application/src/file.dart"));
    expect(
        imports, ["import 'file:${absolutePathToAppLib}/application.dart';"]);
  });
}
