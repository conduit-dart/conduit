import 'dart:async';
import 'dart:io';

import 'package:conduit/src/cli/runner.dart';
import 'package:conduit/src/cli/running_process.dart';
import 'package:conduit_common_test/conduit_common_test.dart';
import 'package:fs_test_agent/dart_project_agent.dart';
import 'package:fs_test_agent/working_directory_agent.dart';
import 'package:path/path.dart';

class CLIClient {
  CLIClient(this.agent);

  final WorkingDirectoryAgent agent;

  DartProjectAgent get projectAgent {
    if (agent is DartProjectAgent) {
      return agent as DartProjectAgent;
    }

    throw StateError("is not a project terminal");
  }

  List<String>? defaultArgs;

  String get output {
    return _output.toString();
  }

  final StringBuffer _output = StringBuffer();

  static Future activateCLI({String path = "."}) {
    const String cmd = "dart";

    return Process.run(cmd, ["pub", "global", "activate", "-spath", path]);
  }

  static Future deactivateCLI() {
    const String cmd = "dart";

    return Process.run(cmd, ["pub", "global", "deactivate", "conduit"]);
  }

  Directory get defaultMigrationDirectory {
    return Directory.fromUri(agent.workingDirectory.uri.resolve("migrations/"));
  }

  Directory get libraryDirectory {
    return Directory.fromUri(agent.workingDirectory.uri.resolve("lib/"));
  }

  void delete() {
    agent.workingDirectory.deleteSync(recursive: true);
  }

  CLIClient replicate(Uri uri) {
    var dstUri = uri;
    if (!uri.isAbsolute) {
      dstUri = DartProjectAgent.projectsDirectory.uri.resolveUri(uri);
    }

    final dstDirectory = Directory.fromUri(dstUri);
    if (dstDirectory.existsSync()) {
      dstDirectory.deleteSync(recursive: true);
    }
    WorkingDirectoryAgent.copyDirectory(
        src: agent.workingDirectory.uri, dst: dstUri);
    return CLIClient(DartProjectAgent.existing(dstUri));
  }

  /// Clears any cached output from a prior call to [run].
  void clearOutput() {
    _output.clear();
  }

  Future<CLIClient> createTestProject(
      {String name = "application_test",
      String? template,
      bool offline = true}) async {
    final project = normalize(absolute(join('.')));
    if (template == null) {
      final client = CLIClient(DartProjectAgent(name, dependencies: {
        "conduit": {"path": project}
      }, devDependencies: {
        "test": "^1.6.7"
      }, dependencyOverrides: {
        'conduit_runtime': {'path': '${join(project, '..', 'runtime')}'},
        'conduit_isolate_exec': {
          'path': '${join(project, '..', 'isolate_exec')}'
        },
        'conduit_password_hash': {
          'path': '${join(project, '..', 'password_hash')}'
        },
        'conduit_open_api': {'path': '${join(project, '..', 'open_api')}'},
        'conduit_codable': {'path': '${join(project, '..', 'codable')}'},
        'conduit_config': {'path': '${join(project, '..', 'config')}'},
        'conduit_common': {'path': '${join(project, '..', 'common')}'},
        'fs_test_agent': {'path': '${join(project, '..', 'fs_test_agent')}'}
      }));

      client.projectAgent.addLibraryFile("channel", """
import 'dart:async';

import 'package:conduit/conduit.dart';

import '$name.dart';

class TestChannel extends ApplicationChannel {
  Controller get entryPoint {
    final router = new Router();
    router
      .route("/example")
      .linkFunction((request) async {
        return Response.ok({"key": "value"});
      });

    return router;
  }
}
  """);

      return client;
    }

    try {
      DartProjectAgent.projectsDirectory.createSync();
    } catch (_) {}

    final args = <String>[];
    args.addAll(["-t", template]);

    if (offline) {
      args.add("--offline");
    }

    args.add(name);

    await run("create", args);
    print("$output");

    return CLIClient(DartProjectAgent.existing(
        DartProjectAgent.projectsDirectory.uri.resolve("$name/")));
  }

  Future<int> executeMigrations({String? connectString}) async {
    connectString ??= PostgresTestConfig().connectionUrl;
    final res = await run("db", ["upgrade", "--connect", connectString]);
    if (res != 0) {
      print("executeMigrations failed: $output");
    }
    return res;
  }

  Future<int> run(String command, [List<String>? args]) async {
    args ??= [];
    args.insert(0, command);
    args.addAll(defaultArgs ?? []);

    print("Running 'conduit ${args.join(" ")}'");
    final saved = Directory.current;
    Directory.current = agent.workingDirectory;

    final cmd = Runner()..outputSink = _output;
    final results = cmd.options.parse(args);

    final exitCode = await cmd.process(results);
    if (exitCode != 0) {
      print("command failed: ${output}");
    }

    Directory.current = saved;

    return exitCode;
  }

  CLITask start(String command, List<String>? inputArgs) {
    final args = inputArgs ?? [];
    args.insert(0, command);
    args.addAll(defaultArgs ?? []);

    print("Starting 'conduit ${args.join(" ")}'");
    final saved = Directory.current;
    Directory.current = agent.workingDirectory;

    final cmd = Runner()..outputSink = _output;
    final results = cmd.options.parse(args);

    final task = CLITask();
    var elapsed = 0.0;
    final timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (cmd.runningProcess != null) {
        t.cancel();
        Directory.current = saved;
        task.process = cmd.runningProcess;
        task._processStarted.complete(true);
      } else {
        elapsed += 100;
        if (elapsed > 60000) {
          Directory.current = saved;
          t.cancel();
          task._processStarted
              .completeError(TimeoutException("Timed out after 30 seconds"));
        }
      }
    });

    cmd.process(results).then((exitCode) {
      if (!task._processStarted.isCompleted) {
        print("Command failed to start with exit code: $exitCode");
        print("Message: $output");
        timer.cancel();
        Directory.current = saved;
        task._processStarted.completeError(false);
        task._processFinished.complete(exitCode);
      } else {
        print("Command completed with exit code: $exitCode");
        print("Output: $output");
        task._processFinished.complete(exitCode);
      }
    });

    return task;
  }
}

class CLIResult {
  int? exitCode;
  StringBuffer collectedOutput = StringBuffer();

  String get output => collectedOutput.toString();
}

class CLITask {
  StoppableProcess? process;

  Future get hasStarted => _processStarted.future;

  Future<int> get exitCode => _processFinished.future;

  final Completer<int> _processFinished = Completer<int>();
  final Completer<bool> _processStarted = Completer<bool>();
}
