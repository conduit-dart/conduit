import 'dart:async';
import 'dart:io';

const String _directiveToken = "___DIRECTIVES___";
const String _assignmentToken = "___ASSIGNMENTS___";

class RuntimeGenerator {
  final _elements = <_RuntimeElement>[];

  void addRuntime({required String name, required String source}) {
    _elements.add(_RuntimeElement(name, source));
  }

  Future<void> writeTo(Uri directoryUri) async {
    final dir = Directory.fromUri(directoryUri);
    final libDir = Directory.fromUri(dir.uri.resolve("lib/"));
    final srcDir = Directory.fromUri(libDir.uri.resolve("src/"));
    if (!libDir.existsSync()) {
      libDir.createSync(recursive: true);
    }
    if (!srcDir.existsSync()) {
      srcDir.createSync(recursive: true);
    }

    final libraryFile =
        File.fromUri(libDir.uri.resolve("generated_runtime.dart"));
    await libraryFile.writeAsString(loaderSource);

    final pubspecFile = File.fromUri(dir.uri.resolve("pubspec.yaml"));
    await pubspecFile.writeAsString(pubspecSource);

    await Future.forEach(_elements, (_RuntimeElement e) async {
      final file = File.fromUri(srcDir.uri.resolveUri(e.relativeUri));
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }

      await file.writeAsString(e.source);
    });
  }

  String get pubspecSource => """
name: generated_runtime
description: A runtime generated by package:conduit_runtime
version: 1.0.0

environment:
  sdk: '>=3.4.0 <4.0.0'
""";

  String get _loaderShell => """
import 'package:conduit_runtime/runtime.dart';
import 'package:conduit_runtime/slow_coerce.dart' as runtime_cast;
$_directiveToken

RuntimeContext instance = GeneratedContext._();

class GeneratedContext extends RuntimeContext {
  GeneratedContext._() {
    final map = <String, Object>{};

    $_assignmentToken

    runtimes = RuntimeCollection(map);
  }

  @override
  T coerce<T>(dynamic input) {
    return runtime_cast.cast<T>(input);
  }
}
  """;

  String get loaderSource {
    return _loaderShell
        .replaceFirst(_directiveToken, _directives)
        .replaceFirst(_assignmentToken, _assignments);
  }

  String get _directives {
    final buf = StringBuffer();

    for (final e in _elements) {
      buf.writeln(
        "import 'src/${e.relativeUri.toFilePath(windows: Platform.isWindows)}' as ${e.importAlias};",
      );
    }

    return buf.toString();
  }

  String get _assignments {
    final buf = StringBuffer();

    for (final e in _elements) {
      buf.writeln("map['${e.typeName}'] = ${e.importAlias}.instance;");
    }

    return buf.toString();
  }
}

class _RuntimeElement {
  _RuntimeElement(this.typeName, this.source);

  final String typeName;
  final String source;

  Uri get relativeUri => Uri.file("${typeName.toLowerCase()}.dart");

  String get importAlias {
    return "g_${typeName.toLowerCase()}";
  }
}
