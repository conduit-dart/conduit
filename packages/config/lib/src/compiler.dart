import 'dart:mirrors';

import 'package:conduit_config/src/configuration.dart';
import 'package:conduit_config/src/runtime.dart';
import 'package:conduit_runtime/dev.dart';

/// Registers `Configuration` subclasses with the JIT/dev mirror fallback.
/// Under AOT, the build_runner-generated `bootstrap()` installs the
/// registry directly and this class is unreachable.
class ConfigurationCompiler extends Compiler {
  @override
  Map<String, Object> compile(MirrorContext context) {
    return Map.fromEntries(
      context.getSubclassesOf(Configuration).map((c) {
        return MapEntry(
          MirrorSystem.getName(c.simpleName),
          ConfigurationRuntimeImpl(c),
        );
      }),
    );
  }
}
