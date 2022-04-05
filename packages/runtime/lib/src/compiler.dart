import 'dart:io';

import 'package:conduit_runtime/runtime.dart';

abstract class Compiler {
  /// Modifies a package on the filesystem in order to remove dart:mirrors from the package.
  ///
  /// A copy of this compiler's package will be written to [destinationDirectory].
  /// This method is overridden to modify the contents of that directory
  /// to remove all uses of dart:mirrors.
  ///
  /// Packages should export their [Compiler] in their main library file and only
  /// import mirrors in files directly or transitively imported by the Compiler file.
  /// This method should remove that export statement and therefore remove all transitive mirror imports.
  void deflectPackage(Directory destinationDirectory);

  /// Returns a map of runtime objects that can be used at runtime while running in mirrored mode.
  Map<String, dynamic> compile(MirrorContext context);

  void didFinishPackageGeneration(BuildContext context) {}

  List<Uri> getUrisToResolve(BuildContext context) => [];
}

/// Runtimes that generate source code implement this method.
abstract class SourceCompiler {
  /// The source code, including directives, that declare a class that is equivalent in behavior to this runtime.
  Future<String> compile(BuildContext ctx) async {
    throw UnimplementedError();
  }
}
