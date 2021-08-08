/// Support for doing something awesome.
///
/// More dartdocs go here.
library terminal;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart';

/// A utility for manipulating files and directories in [workingDirectory].
class WorkingDirectoryAgent {
  WorkingDirectoryAgent(Uri uri, {bool create = true}) {
    if (uri.isAbsolute) {
      workingDirectory = Directory.fromUri(uri);
    } else {
      workingDirectory = Directory(join(Directory.current.path, uri.path));
    }
    if (create) {
      workingDirectory.createSync(recursive: true);
    }
  }

  WorkingDirectoryAgent.current() : this(Uri());

  late Directory workingDirectory;

  static void copyDirectory({required Uri src, required Uri dst}) {
    final srcDir = Directory.fromUri(src);
    final dstDir = Directory.fromUri(dst);
    if (!dstDir.existsSync()) {
      dstDir.createSync(recursive: true);
    }

    srcDir.listSync().forEach((fse) {
      if (fse is File) {
        final outPath = dstDir.uri
            .resolve(fse.uri.pathSegments.last)
            .toFilePath(windows: Platform.isWindows);
        fse.copySync(outPath);
      } else if (fse is Directory) {
        final segments = fse.uri.pathSegments;
        final outPath = dstDir.uri.resolve(segments[segments.length - 2]);
        copyDirectory(src: fse.uri, dst: outPath);
      }
    });
  }

  /// Adds or replaces file in this terminal's working directory
  ///
  /// [path] is relative path to file e.g. "lib/src/file.dart"
  /// [contents] is the string contents of the file
  /// [imports] are import uri strings, e.g. 'package:aqueduct/aqueduct.dart' (don't use quotes)
  void addOrReplaceFile(String path, String contents,
      {List<String> imports = const []}) {
    final pathComponents = path.split("/");

    final relativeDirectoryComponents =
        pathComponents.sublist(0, pathComponents.length - 1);

    final uri = relativeDirectoryComponents.fold(
        workingDirectory.uri, (Uri prev, elem) => prev.resolve("$elem/"));

    final directory = Directory.fromUri(uri);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    final file = File.fromUri(directory.uri.resolve(pathComponents.last));
    final directives = imports.map((i) => "import '$i';").join("\n");
    file.writeAsStringSync("$directives\n$contents");
  }

  /// Updates the contents of an existing file
  ///
  /// [path] is relative path to file e.g. "lib/src/file.dart"
  /// [contents] is a function that takes the current contents of the file and returns
  /// the modified contents of the file
  void modifyFile(String path, String Function(String current) contents) {
    final pathComponents = path.split("/");
    final relativeDirectoryComponents =
        pathComponents.sublist(0, pathComponents.length - 1);
    final directory = Directory.fromUri(relativeDirectoryComponents.fold(
        workingDirectory.uri, (Uri prev, elem) => prev.resolve("$elem/")));
    final file = File.fromUri(directory.uri.resolve(pathComponents.last));
    if (!file.existsSync()) {
      throw ArgumentError("File at '${file.uri}' doesn't exist.");
    }

    final output = contents(file.readAsStringSync());
    file.writeAsStringSync(output);
  }

  File? getFile(String path) {
    final pathComponents = path.split("/");
    final relativeDirectoryComponents =
        pathComponents.sublist(0, pathComponents.length - 1);
    final directory = Directory.fromUri(relativeDirectoryComponents.fold(
        workingDirectory.uri, (Uri prev, elem) => prev.resolve("$elem/")));
    final file = File.fromUri(directory.uri.resolve(pathComponents.last));
    if (!file.existsSync()) {
      return null;
    }
    return file;
  }

  Future<ProcessResult> getDependencies({bool offline = true}) async {
    final args = ["get"];
    if (offline) {
      args.add("--offline");
    }

    final cmd = Platform.isWindows ? "pub.bat" : "pub";
    final result = await Process.run(cmd, args,
            workingDirectory: workingDirectory.absolute.path, runInShell: true)
        .timeout(const Duration(seconds: 45));

    if (result.exitCode != 0) {
      throw Exception("${result.stderr}");
    }

    return result;
  }
}
