// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:conduit/src/command.dart';
import 'package:conduit/src/metadata.dart';
import 'package:conduit/src/mixins/project.dart';
import 'package:conduit_runtime/runtime.dart';
import 'package:io/io.dart';

class CLIBuild extends CLICommand with CLIProject {
  @Flag(
    "retain-build-artifacts",
    help:
        "Whether or not the 'build' directory should be left intact after the application is compiled.",
    defaultsTo: false,
  )
  bool get retainBuildArtifacts => decode<bool>("retain-build-artifacts");

  @Option(
    "build-directory",
    help:
        "The directory to store build artifacts during compilation. By default, this directory is deleted when this command completes. See 'retain-build-artifacts' flag.",
    defaultsTo: "/tmp/build",
  )
  Directory get buildDirectory => Directory(
        Uri.parse(decode<String>("build-directory"))
            .toFilePath(windows: Platform.isWindows),
      ).absolute;

  @MultiOption("define",
      help:
          "Adds an environment variable to use during runtime. This can be added more than once.",
      abbr: "D")
  Map<String, String> get environment =>
      Map.fromEntries(decodeMulti("define").map((entry) {
        final pair = entry.split("=");
        return MapEntry(pair[0], pair[1]);
      }));

  @override
  Future<int> handle() async {
    final root = projectDirectory!.uri;
    final libraryUri = root.resolve("lib/").resolve("$libraryName.dart");
    final ctx = BuildContext(
      libraryUri,
      buildDirectory.uri,
      root.resolve("$packageName.aot"),
      getScriptSource(await getChannelName()),
      environment: environment,
    );

    print("Starting build process...");

    final bm = BuildManager(ctx);
    await bm.build();

    return 0;
  }

  @override
  Future cleanup() async {
    if (retainBuildArtifacts) {
      copyPathSync(buildDirectory.path, './_build');
    }
    if (buildDirectory.existsSync()) {
      buildDirectory.deleteSync(recursive: true);
    }
  }

  @override
  String get name {
    return "build";
  }

  @override
  String get description {
    return "Creates an executable of a Conduit application.";
  }

  String getScriptSource(String channelName) {
    return File(projectDirectory!.uri
            .resolve('bin/main.dart')
            .toFilePath(windows: Platform.isWindows))
        .readAsStringSync();
  }
}
