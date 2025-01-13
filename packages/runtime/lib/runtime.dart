library;

import 'dart:io';

export 'package:conduit_runtime/src/analyzer.dart';
export 'package:conduit_runtime/src/build.dart';
export 'package:conduit_runtime/src/build_context.dart';
export 'package:conduit_runtime/src/build_manager.dart';
export 'package:conduit_runtime/src/compiler.dart';
export 'package:conduit_runtime/src/context.dart';
export 'package:conduit_runtime/src/exceptions.dart';
export 'package:conduit_runtime/src/generator.dart';
export 'package:conduit_runtime/src/mirror_coerce.dart';
export 'package:conduit_runtime/src/mirror_context.dart';

import 'package:conduit_runtime/src/compiler.dart';
import 'package:conduit_runtime/src/mirror_context.dart';

/// Compiler for the runtime package itself.
///
/// Removes dart:mirror from a replica of this package, and adds
/// a generated runtime to the replica's pubspec.
class RuntimePackageCompiler extends Compiler {
  @override
  Map<String, Object> compile(MirrorContext context) => {};

  @override
  void deflectPackage(Directory destinationDirectory) {
    final libraryFile = File.fromUri(
      destinationDirectory.uri.resolve("lib/").resolve("runtime.dart"),
    );
    libraryFile.writeAsStringSync(
      "library runtime;\nexport 'src/context.dart';\nexport 'src/exceptions.dart';",
    );

    final contextFile = File.fromUri(
      destinationDirectory.uri
          .resolve("lib/")
          .resolve("src/")
          .resolve("context.dart"),
    );
    final contextFileContents = contextFile.readAsStringSync().replaceFirst(
          "import 'package:conduit_runtime/src/mirror_context.dart';",
          "import 'package:generated_runtime/generated_runtime.dart';",
        );
    contextFile.writeAsStringSync(contextFileContents);

    final pubspecFile =
        File.fromUri(destinationDirectory.uri.resolve("pubspec.yaml"));
    final pubspecContents = pubspecFile.readAsStringSync().replaceFirst(
          "\ndependencies:",
          "\ndependencies:\n  generated_runtime:\n    path: ../../generated_runtime/",
        );
    pubspecFile.writeAsStringSync(pubspecContents);
  }
}
