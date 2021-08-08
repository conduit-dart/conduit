import 'dart:io';
import 'package:path/path.dart';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:pubspec/pubspec.dart';
import 'analyzer.dart';
import 'context.dart';
import 'file_system.dart';
import 'mirror_context.dart';
import 'package:reflectable/reflectable.dart';
import 'package:yaml/yaml.dart';

import 'reflector.dart';

/// Configuration and context values used during [Build.execute].
@runtimeReflector
class BuildContext {
  BuildContext(
    this.rootLibraryFileUri,
    this.buildDirectoryUri,
    this.executableUri,
    this.source, {
    this.forTests = false,
  }) {
    analyzer = CodeAnalyzer(sourceApplicationDirectory.uri);
  }

  factory BuildContext.fromMap(Map<String, dynamic> map) {
    return BuildContext(
      Uri.parse(map['rootLibraryFileUri'] as String),
      Uri.parse(map['buildDirectoryUri'] as String),
      Uri.parse(map['executableUri'] as String),
      map['source'] as String,
      forTests: map['forTests'] as bool? ?? false,
    );
  }

  Map<String, dynamic> get safeMap => {
        'rootLibraryFileUri': sourceLibraryFile.uri.toString(),
        'buildDirectoryUri': buildDirectoryUri.toString(),
        'source': source,
        'executableUri': executableUri.toString(),
        'forTests': forTests
      };

  late CodeAnalyzer analyzer;

  /// A [Uri] to the library file of the application to be compiled.
  final Uri rootLibraryFileUri;

  /// A [Uri] to the executable build product file.
  final Uri executableUri;

  /// A [Uri] to directory where build artifacts are stored during the build process.
  final Uri buildDirectoryUri;

  /// The source script for the executable.
  final String source;

  /// Whether dev dependencies of the application package are included in the dependencies of the compiled executable.
  final bool forTests;

  /// The [RuntimeContext] available during the build process.
  MirrorContext get context => RuntimeContext.current as MirrorContext;

  Uri get targetScriptFileUri => forTests
      ? getDirectory(buildDirectoryUri.resolve("test/"))
          .uri
          .resolve("main_test.dart")
      : buildDirectoryUri.resolve('bin/').resolve("main.dart");

  PubSpec get sourceApplicationPubspec => PubSpec.fromYamlString(
        File.fromUri(sourceApplicationDirectory.uri.resolve("pubspec.yaml"))
            .readAsStringSync(),
      );

  Map<dynamic, dynamic> get sourceApplicationPubspecMap =>
      loadYaml(File.fromUri(
        sourceApplicationDirectory.uri.resolve("pubspec.yaml"),
      ).readAsStringSync()) as Map<dynamic, dynamic>;

  /// The directory of the application being compiled.
  Directory get sourceApplicationDirectory =>
      getDirectory(rootLibraryFileUri.resolve("../"));

  /// The library file of the application being compiled.
  File get sourceLibraryFile => getFile(rootLibraryFileUri);

  /// The directory where build artifacts are stored.
  Directory get buildDirectory => getDirectory(buildDirectoryUri);

  /// Gets dependency package location relative to [sourceApplicationDirectory].
  Map<String, Uri> get resolvedPackages => getResolvedPackageUris(
      sourceApplicationDirectory.uri.resolve(".packages"),
      relativeTo: sourceApplicationDirectory.uri);

  /// Returns a [Directory] at [uri], creates it recursively if it doesn't exist.
  Directory getDirectory(Uri uri) {
    final dir = Directory.fromUri(uri);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Returns a [File] at [uri], creates all parent directories recursively if necessary.
  File getFile(Uri uri) {
    final file = File.fromUri(uri);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    return file;
  }

  Uri? resolveUri(Uri? uri) {
    if (uri == null) {
      return null;
    }
    var outputUri = uri;
    if (outputUri.scheme == "package") {
      final segments = outputUri.pathSegments;
      outputUri = resolvedPackages[segments.first]!.resolve("lib/");
      for (var i = 1; i < segments.length; i++) {
        if (i < segments.length - 1) {
          outputUri = outputUri.resolve("${segments[i]}/");
        } else {
          outputUri = outputUri.resolve(segments[i]);
        }
      }
    } else if (!outputUri.isAbsolute) {
      throw ArgumentError("'uri' must be absolute or a package URI");
    }

    return outputUri;
  }

  List<String> getImportDirectives({
    Uri? uri,
    String? source,
    bool alsoImportOriginalFile = false,
  }) {
    if (uri != null && source != null) {
      throw ArgumentError(
          "either uri or source must be non-null, but not both");
    }

    if (uri == null && source == null) {
      throw ArgumentError(
          "either uri or source must be non-null, but not both");
    }

    if (alsoImportOriginalFile == true && uri == null) {
      throw ArgumentError(
          "flag 'alsoImportOriginalFile' may only be set if 'uri' is also set");
    }

    final fileUri = resolveUri(uri);
    final text = source ?? File.fromUri(fileUri!).readAsStringSync();
    final importRegex = RegExp("import [\\'\\\"]([^\\'\\\"]*)[\\'\\\"];");

    final imports = importRegex.allMatches(text).map((m) {
      final importedUri = Uri.parse(m.group(1)!);

      if (!importedUri.isAbsolute) {
        final path = fileUri!
            .resolve(importedUri.path)
            .toFilePath(windows: Platform.isWindows);
        return "import 'file:${absolute(path)}';";
      }

      return text.substring(m.start, m.end);
    }).toList();

    if (alsoImportOriginalFile) {
      imports.add("import '$uri';");
    }

    return imports;
  }

  ClassDeclaration getClassDeclarationFromType(Type type) {
    final classMirror = runtimeReflector.reflectType(type);
    return analyzer.getClassFromFile(
      classMirror.simpleName,
      resolveUri(classMirror.location.sourceUri)!,
    );
  }

  List<Annotation> getAnnotationsFromField(Type _type, String propertyName) {
    var type = runtimeReflector.reflectType(_type) as ClassMirror;
    var field =
        getClassDeclarationFromType(type.reflectedType).getField(propertyName);
    while (field == null) {
      type = type.superclass!;
      if (type.reflectedType == Object) {
        break;
      }
      field = getClassDeclarationFromType(type.reflectedType)
          .getField(propertyName);
    }

    return (field!.parent!.parent! as FieldDeclaration).metadata.toList();
  }
}
