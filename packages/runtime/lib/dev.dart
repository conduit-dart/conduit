/// Dev/JIT-only entrypoint for `package:conduit_runtime`.
///
/// Re-exports the mirror-based discovery, build pipeline, and `Compiler`
/// machinery that the legacy `conduit build` CLI and dev-mode reflection
/// fallback depend on. Keep these imports out of any code path that
/// needs to AOT-compile (`dart compile exe`); use
/// `package:conduit_runtime/runtime.dart` (which has no `dart:mirrors`
/// in its import graph) for that.
///
/// Dev/JIT users who want `RuntimeContext.current` to fall back to
/// `MirrorContext` automatically should call [enableMirrorFallback] once
/// at the top of `main()`. AOT users do not need this — the
/// build_runner-generated `bootstrap()` installs the runtime registry
/// directly.
library;

export 'package:conduit_runtime/runtime.dart';
export 'package:conduit_runtime/src/analyzer.dart';
export 'package:conduit_runtime/src/build.dart';
export 'package:conduit_runtime/src/build_context.dart';
export 'package:conduit_runtime/src/build_manager.dart';
export 'package:conduit_runtime/src/compiler.dart';
export 'package:conduit_runtime/src/generator.dart';
export 'package:conduit_runtime/src/mirror_coerce.dart';
export 'package:conduit_runtime/src/mirror_context.dart';

import 'dart:io';

import 'package:conduit_runtime/src/compiler.dart';
import 'package:conduit_runtime/src/context.dart';
import 'package:conduit_runtime/src/mirror_context.dart' as mc;

/// Wires the mirror-based `MirrorContext` as the default factory used by
/// `RuntimeContext.current`. Call once at the top of `main()` from
/// dev/JIT-mode code that doesn't go through the build_runner-generated
/// `bootstrap()`.
void enableMirrorFallback() {
  registerDefaultContextFactory(() => mc.instance);
}

/// Compiler for the runtime package itself.
///
/// Removes dart:mirror from a replica of this package, and adds
/// a generated runtime to the replica's pubspec.
class RuntimePackageCompiler extends Compiler {
  @override
  Map<String, Object> compile(mc.MirrorContext context) => {};

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
