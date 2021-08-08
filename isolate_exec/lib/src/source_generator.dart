import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/context_builder.dart';
import 'package:analyzer/dart/analysis/context_locator.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/file_system.dart' hide File;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:conduit_isolate_exec/src/executable.dart';
import 'package:conduit_isolate_exec/src/reflector.dart';
import 'package:path/path.dart';

import '../conduit_isolate_exec.dart';

const sourceName = '../isolate_exec/lib/src/source_generator.dart';

@isolateReflector
@sourceName
class SourceGenerator {
  SourceGenerator(
    this.executableType, {
    this.imports = const [],
    this.additionalTypes = const [],
    this.additionalContents,
    this.targetDirectory,
  });

  Type executableType;
  String? targetDirectory;

  String get typeName =>
      isolateReflector.reflectType(executableType).simpleName;
  final List<String> imports;
  final String? additionalContents;
  final List<Type> additionalTypes;

  Future<String> get scriptSource async {
    final typeSource = (await _getClass(executableType)).toSource();
    final builder = StringBuffer();
    final importsBuffer = StringBuffer();

    importsBuffer.writeln("// @dart = 2.12");
    for (final anImport in imports) {
      if (anImport.startsWith('file')) {
        continue;
      }
      importsBuffer.writeln("import '$anImport';");
    }
    importsBuffer.writeln("import 'dart:async';");
    importsBuffer.writeln("import 'dart:isolate';");
    importsBuffer.writeln("import 'package:reflectable/reflectable.dart';");
    importsBuffer.writeln(
        "import 'package:conduit_isolate_exec/conduit_isolate_exec.dart';");

    builder.writeln("""
Future main (List<String> args, Map<String, dynamic> message) async {
  initializeReflectable();
  final sendPort = message['_sendPort'];
  final executable = $typeName(message);
  final result = await executable.execute();
  sendPort.send({"_result": result});
}
    """);
    builder.writeln(typeSource);
    builder.writeln((await _getClass(Executable)).toSource());

    builder.writeln("const sourceName = '';");

    for (final type in additionalTypes) {
      final source = await _getClass(type);
      builder.writeln(source.toSource());
    }

    if (additionalContents != null) {
      builder.writeln(additionalContents);
    }

    const artifactName = 'source_generator_artifact';
    String importsString;
    try {
      final tmpFile =
          File(join(absolute(targetDirectory ?? ''), 'lib/$artifactName.dart'));
      await tmpFile.writeAsString(importsBuffer.toString() + builder.toString(),
          mode: FileMode.writeOnly);

      runBuildRunner(targetDirectory: targetDirectory);

      final reflectableArtifact = File(join(absolute(targetDirectory ?? ''),
          'lib/$artifactName.reflectable.dart'));

      importsString =
          importsBuffer.toString() + await reflectableArtifact.readAsString();
      importsString = _removePrefixImport(importsString, '$artifactName.dart');
      importsString = _findAndRemoveDuplicateImports(importsString);
    } catch (e) {
      throw StateError('Failed to generate source for $targetDirectory: $e');
    }
    return importsString + builder.toString();
  }

  String _findAndRemoveDuplicateImports(String contents) {
    var newContents = contents;
    for (final animport in imports) {
      newContents = _removePrefixImport(contents, animport);
    }
    return newContents;
  }

  String _removePrefixImport(String contents, String importName) {
    final import = RegExp("import '$importName" + r"' as (prefix\d*);");
    final prefix = import.firstMatch(contents)?.group(1);
    if (prefix != null) {
      return contents.replaceFirst(import, "").replaceAll("$prefix.", "");
    }
    return contents;
  }

  static Future<ClassDeclaration> _getClass(Type type) async {
    final uri = Uri.parse(join(Directory.current.path,
        isolateReflector.reflectType(type).metadata.last as String));
    final path = uri.toFilePath(windows: Platform.isWindows);

    final context = _createContext(path);
    final session = context.currentSession;
    final unit = session.getParsedUnit2(path) as ParsedUnitResult;
    final typeName = isolateReflector.reflectType(type).simpleName;

    return unit.unit.declarations
        .whereType<ClassDeclaration>()
        .firstWhere((classDecl) => classDecl.name.name == typeName);
  }
}

AnalysisContext _createContext(
  String path, {
  ResourceProvider? resourceProvider,
}) {
  resourceProvider ??= PhysicalResourceProvider.INSTANCE;
  final builder = ContextBuilder(resourceProvider: resourceProvider);
  final contextLocator = ContextLocator(
    resourceProvider: resourceProvider,
  );
  final root = contextLocator.locateRoots(
    includedPaths: [path],
  );
  return builder.createContext(contextRoot: root.first);
}

void _deleteDir(String path) {
  final current = Directory(path);
  if (current.existsSync()) {
    current.deleteSync(recursive: true);
  }
}

void runBuildRunner({String? targetDirectory}) {
  final current = Uri.file(targetDirectory ?? Directory.current.path);
  _deleteDir(current.resolve('.packages').path);
  _deleteDir(current.resolve('.dart_tool/').path);
  String cmd;
  if (Platform.isWindows) {
    cmd = (Process.runSync("where", ["pub.bat"])).stdout as String;
  } else {
    cmd = (Process.runSync("which", ["pub"])).stdout as String;
  }
  cmd = cmd.replaceAll('\n', '');
  Process.runSync(cmd, ['get', '--no-precompile'],
      workingDirectory: current.path, runInShell: true);
  final result = Process.runSync(cmd,
      ['run', 'build_runner', 'build', '-v', '--delete-conflicting-outputs'],
      workingDirectory: current.path, runInShell: true);
  print(result.stdout);

  if (result.exitCode != 0) {
    print(result.stderr);
    throw StateError(
        'Reflectable code generation failed with error: ${result.stderr}');
  }
}
