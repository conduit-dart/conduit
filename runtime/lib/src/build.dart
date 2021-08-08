// ignore_for_file: avoid_print
import 'dart:io';

import 'package:conduit_isolate_exec/conduit_isolate_exec.dart';
import 'build_context.dart';
import 'file_system.dart';
import 'package:json2yaml/json2yaml.dart';
import 'package:path/path.dart';

class Build {
  Build(this.context);

  final BuildContext context;

  late final Map<String, Uri> packageMap = context.resolvedPackages;

  Future execute() async {
    final compilers = context.context.compilers;

    print("Resolving ASTs...");
    final astsToResolve = <Uri>{
      ...compilers.expand((c) => c.getUrisToResolve(context))
    };
    await Future.forEach<Uri>(
      astsToResolve,
      (astUri) => context.analyzer.resolveUnitAt(context.resolveUri(astUri)!),
    );

    final pubspecMap = <String, dynamic>{
      'name': 'runtime_target',
      'version': '1.0.0',
      'environment': {'sdk': '>=2.12.0 <3.0.0'},
      'dependencies': {},
      'dev_dependencies':
          context.sourceApplicationPubspecMap['dev_dependencies'],
      'dependency_overrides':
          context.sourceApplicationPubspecMap['dependency_overrides']
    };

    final sourceDirectory = context.rootLibraryFileUri
        .resolve('../')
        .toFilePath(windows: Platform.isWindows);
    final sourceDependencies =
        context.sourceApplicationPubspecMap['dependencies'];
    for (final key in sourceDependencies.keys) {
      if (sourceDependencies[key] is Map &&
          sourceDependencies[key]['path'] != null) {
        pubspecMap['dependencies'][key] = {
          'path':
              normalize(join(sourceDirectory, sourceDependencies[key]['path']))
        };
      } else {
        pubspecMap['dependencies'][key] = sourceDependencies[key];
      }
    }
    pubspecMap['dependencies']
        [context.sourceApplicationPubspec.name] = {'path': sourceDirectory};

    File.fromUri(context.buildDirectoryUri.resolve("pubspec.yaml"))
        .writeAsStringSync(
            json2yaml(pubspecMap, yamlStyle: YamlStyle.pubspecYaml));

    Directory(context.buildDirectoryUri.resolve('bin/').path).createSync();
    context
        .getFile(context.targetScriptFileUri)
        .writeAsStringSync(context.source);

    context
        .getFile(context.buildDirectoryUri.resolve('build.yaml'))
        .writeAsStringSync(File(context.sourceApplicationDirectory.uri
                .resolve('build.yaml')
                .toFilePath(windows: Platform.isWindows))
            .readAsStringSync());

    for (final compiler in context.context.compilers) {
      compiler.didFinishPackageGeneration(context);
    }

    print("Fetching dependencies (--offline --no-precompile)...");
    await getDependencies();
    print("Finished fetching dependencies.");
    runBuildRunner(targetDirectory: context.buildDirectory.path);
    if (!context.forTests) {
      print("Compiling...");

      await compile(context.targetScriptFileUri, context.executableUri);
      print("Success. Executable is located at '${context.executableUri}'.");
    }
  }

  void _deleteDir(String path) {
    final current = Directory(path);
    if (current.existsSync()) {
      current.deleteSync(recursive: true);
    }
  }

  Future getDependencies() async {
    _deleteDir(context.buildDirectoryUri.resolve('.packages').path);
    _deleteDir(context.buildDirectoryUri.resolve('pubspec.lock').path);
    _deleteDir(context.buildDirectoryUri.resolve('.dart_tool/').path);
    String cmd;
    if (Platform.isWindows) {
      cmd = (await Process.run("where", ["pub.bat"])).stdout as String;
    } else {
      cmd = (await Process.run("which", ["pub"])).stdout as String;
    }
    cmd = cmd.replaceAll('\n', '');
    final res =
        Process.runSync(cmd, ['get', '--no-precompile'], runInShell: true);
    if (res.exitCode != 0) {
      print("${res.stdout}");
      print("${res.stderr}");
      throw StateError(
          "'pub get' failed with the following message: ${res.stderr}");
    }
  }

  Future compile(Uri srcUri, Uri dstUri) async {
    final res = await Process.run(
        "dart",
        [
          "compile",
          "exe",
          "--sound-null-safety",
          srcUri.toFilePath(windows: Platform.isWindows),
          "-o",
          dstUri.toFilePath(windows: Platform.isWindows)
        ],
        workingDirectory: context.rootLibraryFileUri
            .resolve('../')
            .toFilePath(windows: Platform.isWindows),
        runInShell: true);
    if (res.exitCode != 0) {
      throw StateError(
          "Failed to compile pacakage <${context.sourceApplicationPubspec.name}> with the following message: ${res.stderr}");
    }
    print("${res.stdout}");
  }

  void copyPackage(Uri srcUri, Uri dstUri) {
    copyDirectory(src: srcUri.resolve("lib/"), dst: dstUri.resolve("lib/"));
    context.getFile(srcUri.resolve("pubspec.yaml")).copySync(
        dstUri.resolve("pubspec.yaml").toFilePath(windows: Platform.isWindows));
  }
}
