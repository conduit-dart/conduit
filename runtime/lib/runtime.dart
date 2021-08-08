library runtime;

import 'package:conduit_runtime/src/mirror_context.dart';

import 'src/compiler.dart';

export 'src/analyzer.dart';
export 'src/build.dart';
export 'src/build_context.dart';
export 'src/build_manager.dart';
export 'src/compiler.dart';
export 'src/context.dart';
export 'src/exceptions.dart';
export 'src/file_system.dart';
export 'src/mirror_coerce.dart';
export 'src/mirror_context.dart';
export 'src/reflector.dart';

/// Compiler for the runtime package itself.
///
/// Removes dart:mirror from a replica of this package, and adds
/// a generated runtime to the replica's pubspec.
class RuntimePackageCompiler extends Compiler {
  @override
  Map<String, dynamic> compile(MirrorContext context) => {};
}
