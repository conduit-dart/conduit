/// Support for doing something awesome.
///
/// More dartdocs go here.
import 'dart:io';

import 'package:fs_test_agent/working_directory_agent.dart';
import 'package:path/path.dart';
import 'package:pubspec/pubspec.dart';

/// A [WorkingDirectoryAgent] with additional behavior for managing a 'Dart package' directory.
class DartProjectAgent extends WorkingDirectoryAgent {
  /// Creates a new package and terminal on that package's working directory.
  ///
  /// Make sure to call [tearDownAll] in your test's method of the same name to
  /// delete the [projectsDirectory] ]where the package is written to. ('$PWD/tmp')
  ///
  /// Both [dependencies] and [devDependencies] are a valid dependency map,
  /// e.g. `{'aqueduct': '^2.0.0'}` or `{'relative' : {'path' : '../'}}`
  DartProjectAgent(
    this.name, {
    Map<String, dynamic> dependencies = const {},
    Map<String, dynamic> devDependencies = const {},
    Map<String, dynamic> dependencyOverrides = const {},
  }) : super(Directory(join(projectsDirectory.path, name))) {
    if (!projectsDirectory.existsSync()) {
      projectsDirectory.createSync();
    }
    workingDirectory.createSync(recursive: true);

    final libDir = Directory(join(workingDirectory.path, "lib"));
    libDir.createSync(recursive: true);

    addOrReplaceFile("analysis_options.yaml", _analysisOptionsContents);
    addOrReplaceFile(
      "pubspec.yaml",
      _pubspecContents(
        name,
        dependencies,
        devDependencies,
        dependencyOverrides,
      ),
    );
    addOrReplaceFile("lib/$name.dart", "");
  }

  DartProjectAgent.existing(Uri uri) : super(Directory.fromUri(uri)) {
    final pubspecFile = File(join(workingDirectory.path, "pubspec.yaml"));
    if (!pubspecFile.existsSync()) {
      throw ArgumentError(
        "the uri '$uri' is not a Dart project directory; does not contain pubspec.yaml",
      );
    }

    final pubspec = PubSpec.fromYamlString(pubspecFile.readAsStringSync());
    name = pubspec.name!;
  }

  /// Temporary directory where projects are stored ('/tmp/conduit')
  static Directory get projectsDirectory =>
      Directory(join(Directory.systemTemp.path, 'conduit'));

  /// Name of this project
  late String name;

  /// Directory of lib/ in project
  Directory get libraryDirectory {
    return Directory(join(workingDirectory.path, 'lib'));
  }

  /// Directory of test/ in project
  Directory get testDirectory {
    return Directory(join(workingDirectory.path, "test"));
  }

  /// Directory of lib/src/ in project
  Directory get srcDirectory {
    return Directory(join(workingDirectory.path, "lib", "src"));
  }

  /// Deletes [projectsDirectory]. Call after tests are complete
  static void tearDownAll() {
    try {
      projectsDirectory.deleteSync(recursive: true);
    } catch (_) {}
  }

  final _analysisOptionsContents = """
  """;

  static String _asYaml(Map<String, dynamic> m, {int indent = 0}) {
    final buf = StringBuffer();

    final indentBuffer = StringBuffer();
    for (var i = 0; i < indent; i++) {
      indentBuffer.write("  ");
    }
    final indentString = indentBuffer.toString();

    m.forEach((key, value) {
      buf.write("$indentString$key: ");
      if (value is String) {
        buf.writeln(value);
      } else if (value is Map<String, dynamic>) {
        buf.writeln();
        buf.write(_asYaml(value, indent: indent + 1));
      }
    });

    return buf.toString();
  }

  String _pubspecContents(
    String name,
    Map<String, dynamic> deps,
    Map<String, dynamic> devDeps,
    Map<String, dynamic> dependencyOverrides,
  ) {
    return """
name: $name
description: desc
version: 0.0.1

environment:
  sdk: ">=2.19.0 <3.0.0"

dependencies:
${_asYaml(deps, indent: 1)}

dev_dependencies:
${_asYaml(devDeps, indent: 1)}

dependency_overrides:
${_asYaml(dependencyOverrides, indent: 1)}
""";
  }

  /// Creates a new $name.dart file in lib/src/
  ///
  /// Imports the library file for this terminal.
  void addSourceFile(String fileName, String contents, {bool export = true}) {
    addOrReplaceFile(
      "lib/src/$fileName.dart",
      """
import 'package:$name/$name.dart';

$contents
  """,
    );

    addLibraryExport("src/$fileName.dart");
  }

  /// Creates a new $name.dart file in lib/
  ///
  /// Imports the library file for this terminal.
  void addLibraryFile(String fileName, String contents, {bool export = true}) {
    addOrReplaceFile(
      "lib/$fileName.dart",
      """
import 'package:$name/$name.dart';

$contents
  """,
    );

    addLibraryExport("$fileName.dart");
  }

  /// Adds [exportUri] as an export to the main library file of this project.
  ///
  /// e.g. `addLibraryExport('package:aqueduct/aqueduct.dart')
  void addLibraryExport(String exportUri) {
    modifyFile("lib/$name.dart", (c) {
      return "export '$exportUri';\n$c";
    });
  }
}
