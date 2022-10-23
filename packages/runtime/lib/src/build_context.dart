import 'dart:io';
import 'dart:mirrors';
import 'package:path/path.dart';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:package_config/package_config.dart';
import 'package:pubspec/pubspec.dart';
import 'package:conduit_runtime/src/analyzer.dart';
import 'package:conduit_runtime/src/context.dart';
import 'package:conduit_runtime/src/mirror_context.dart';
import 'package:yaml/yaml.dart';

/// Configuration and context values used during [Build.execute].
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

  PackageConfig? _packageConfig = null;

  /// The [RuntimeContext] available during the build process.
  MirrorContext get context => RuntimeContext.current as MirrorContext;

  Uri get targetScriptFileUri => forTests
      ? getDirectory(buildDirectoryUri.resolve("test/"))
          .uri
          .resolve("main_test.dart")
      : buildDirectoryUri.resolve("main.dart");

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

  /// The generated runtime directory
  Directory get buildRuntimeDirectory =>
      getDirectory(buildDirectoryUri.resolve("generated_runtime/"));

  /// Directory for compiled packages
  Directory get buildPackagesDirectory =>
      getDirectory(buildDirectoryUri.resolve("packages/"));

  /// Directory for compiled application
  Directory get buildApplicationDirectory => getDirectory(
      buildPackagesDirectory.uri.resolve("${sourceApplicationPubspec.name}/"));

  /// Gets dependency package location relative to [sourceApplicationDirectory].
  Future<PackageConfig> get packageConfig async {
    if (_packageConfig == null) {
      _packageConfig = (await findPackageConfig(sourceApplicationDirectory))!;
    }
    return _packageConfig!;
  }

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

  Future<Package?> getPackageFromUri(Uri? uri) async {
    if (uri == null) {
      return null;
    }
    if (uri.scheme == "package") {
      final segments = uri.pathSegments;
      return (await packageConfig)[segments.first]!;
    } else if (!uri.isAbsolute) {
      throw ArgumentError("'uri' must be absolute or a package URI");
    }
    return null;
  }

  Future<List<String>> getImportDirectives({
    Uri? uri,
    String? source,
    bool alsoImportOriginalFile = false,
  }) async {
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
    Package? package = await getPackageFromUri(uri);
    String? trailingSegments = uri?.pathSegments.sublist(1).join('/');
    final fileUri =
        package?.packageUriRoot.resolve(trailingSegments ?? '') ?? uri;
    final text = source ?? File.fromUri(fileUri!).readAsStringSync();
    final importRegex = RegExp("import [\\'\\\"]([^\\'\\\"]*)[\\'\\\"];");

    final imports = importRegex.allMatches(text).map((m) {
      final importedUri = Uri.parse(m.group(1)!);

      if (!importedUri.isAbsolute) {
        final path = fileUri
            ?.resolve(importedUri.path)
            .toFilePath(windows: Platform.isWindows);
        return "import 'file:${absolute(path!)}';";
      }

      return text.substring(m.start, m.end);
    }).toList();

    if (alsoImportOriginalFile) {
      imports.add("import '$uri';");
    }

    return imports;
  }

  Future<ClassDeclaration?> getClassDeclarationFromType(Type type) async {
    final classMirror = reflectType(type);
    Uri uri = classMirror.location!.sourceUri;
    if (!classMirror.location!.sourceUri.isAbsolute) {
      Package? package = await getPackageFromUri(uri);
      uri = package!.packageUriRoot;
    }
    return analyzer.getClassFromFile(
        MirrorSystem.getName(classMirror.simpleName), uri);
  }

  Future<FieldDeclaration?> _getField(ClassMirror type, String propertyName) {
    return getClassDeclarationFromType(type.reflectedType).then((cd) {
      try {
        return cd!.members.firstWhere((m) => (m as FieldDeclaration)
            .fields
            .variables
            .any((v) => v.name.value() == propertyName)) as FieldDeclaration;
      } catch (e) {
        return null;
      }
    });
  }

  Future<List<Annotation>> getAnnotationsFromField(
      Type _type, String propertyName) async {
    var type = reflectClass(_type);
    FieldDeclaration? field = await _getField(type, propertyName);
    while (field == null) {
      type = type.superclass!;
      if (type.reflectedType == Object) {
        break;
      }
      field = await _getField(type, propertyName);
    }

    if (field == null) {
      return [];
    }

    return field.metadata;
  }
}
