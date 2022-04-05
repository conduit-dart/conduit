// ignore_for_file: prefer_void_to_null
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:package_config/package_config.dart';
import 'package:conduit_isolate_exec/conduit_isolate_exec.dart';
import 'package:conduit_runtime/runtime.dart';

class BuildExecutable extends Executable<Null> {
  BuildExecutable(Map<String, dynamic> message) : super(message) {
    context = BuildContext.fromMap(message);
  }

  late BuildContext context;

  @override
  Future<Null> execute() async {
    final build = Build(context);
    await build.execute();
  }
}

class BuildManager {
  /// Creates a new build manager to compile a non-mirrored build.
  BuildManager(this.context);

  final BuildContext context;

  Uri get sourceDirectoryUri => context.sourceApplicationDirectory.uri;

  Future build() async {
    if (!context.buildDirectory.existsSync()) {
      context.buildDirectory.createSync();
    }

    // Here is where we need to provide a temporary copy of the script file with the main function stripped;
    // this is because when the RuntimeGenerator loads, it needs Mirror access to any declarations in this file
    var scriptSource = context.source;
    final strippedScriptFile = File.fromUri(context.targetScriptFileUri)
      ..writeAsStringSync(scriptSource);
    final analyzer = CodeAnalyzer(strippedScriptFile.absolute.uri);
    final analyzerContext = analyzer.contexts.contextFor(analyzer.path);
    final parsedUnit = analyzerContext.currentSession
        .getParsedUnit2(analyzer.path) as ParsedUnitResult;

    final mainFunctions = parsedUnit.unit.declarations
        .whereType<FunctionDeclaration>()
        .where((f) => f.name.name == "main")
        .toList();

    for (final f in mainFunctions.reversed) {
      scriptSource = scriptSource.replaceRange(f.offset, f.end, "");
    }

    strippedScriptFile.writeAsStringSync(scriptSource);
    await IsolateExecutor.run(
      BuildExecutable(context.safeMap),
      packageConfigURI:
          sourceDirectoryUri.resolve('.dart_tool/package_config.json'),
      imports: [
        "package:conduit_runtime/runtime.dart",
        context.targetScriptFileUri.toString()
      ],
      logHandler: (s) => print(s), //ignore: avoid_print
    );
  }

  Future clean() async {
    if (context.buildDirectory.existsSync()) {
      context.buildDirectory.deleteSync(recursive: true);
    }
  }
}
