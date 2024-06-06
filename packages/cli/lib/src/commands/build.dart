// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:args/args.dart' as arg_package;
import 'package:conduit/src/command.dart';
import 'package:conduit/src/metadata.dart';
import 'package:conduit/src/mixins/project.dart';
import 'package:conduit_core/conduit_core.dart';
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
    final method = (reflect(_runnerFunc) as ClosureMirror).function;

    return """
import 'dart:async';
import 'dart:io';

import 'package:conduit_core/conduit_core.dart';
import 'package:args/args.dart' as arg_package;
import 'package:$packageName/$libraryName.dart';

${method.source!.replaceFirst("Application<ApplicationChannel>", "Application<$channelName>").replaceFirst("_runnerFunc", "main")}
""";
  }
}

Future _runnerFunc(List<String> args, dynamic sendPort) async {
  final argParser = arg_package.ArgParser()
    ..addOption(
      "address",
      abbr: "a",
      help: "The address to listen on. See HttpServer.bind for more details."
          " Using the default will listen on any address.",
    )
    ..addOption(
      "config-path",
      abbr: "c",
      help:
          "The path to a configuration file. This File is available in the ApplicationOptions "
          "for a ApplicationChannel to use to read application-specific configuration values. Relative paths are relative to [directory].",
      defaultsTo: "config.yaml",
    )
    ..addOption(
      "isolates",
      abbr: "n",
      help: "Number of isolates handling requests.",
    )
    ..addOption(
      "port",
      abbr: "p",
      help: "The port number to listen for HTTP requests on.",
      defaultsTo: "8888",
    )
    ..addFlag(
      "ipv6-only",
      help: "Limits listening to IPv6 connections only.",
      negatable: false,
    )
    ..addOption(
      "ssl-certificate-path",
      help:
          "The path to an SSL certicate file. If provided along with --ssl-certificate-path, the application will be HTTPS-enabled.",
    )
    ..addOption(
      "ssl-key-path",
      help:
          "The path to an SSL private key file. If provided along with --ssl-certificate-path, the application will be HTTPS-enabled.",
    )
    ..addOption(
      "timeout",
      help: "Number of seconds to wait to ensure startup succeeded.",
      defaultsTo: "45",
    )
    ..addFlag("help");

  final values = argParser.parse(args);
  if (values["help"] == true) {
    print(argParser.usage);
    return 0;
  }

  final app = Application<ApplicationChannel>();
  app.options = ApplicationOptions()
    ..port = int.parse(values['port'] as String)
    ..address = values['address']
    ..isIpv6Only = values['ipv6-only'] == true
    ..configurationFilePath = values['config-path'] as String?
    ..certificateFilePath = values['ssl-certificate-path'] as String?
    ..privateKeyFilePath = values['ssl-key-path'] as String?;
  final isolateCountString = values['isolates'];
  if (isolateCountString == null) {
    await app.startOnCurrentIsolate();
  } else {
    await app.start(numberOfInstances: int.parse(isolateCountString as String));
  }
}
