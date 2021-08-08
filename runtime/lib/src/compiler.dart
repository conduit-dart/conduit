import 'build_context.dart';
import 'mirror_context.dart';
import 'reflector.dart';

@runtimeReflector
abstract class Compiler {
  /// Returns a map of runtime objects that can be used at runtime while running in mirrored mode.
  Map<String, dynamic> compile(MirrorContext context);

  void didFinishPackageGeneration(BuildContext context) {}

  List<Uri> getUrisToResolve(BuildContext context) => [];
}

/// Runtimes that generate source code implement this method.
@runtimeReflector
abstract class SourceCompiler {
  /// The source code, including directives, that declare a class that is equivalent in behavior to this runtime.
  String compile(BuildContext ctx);
}
