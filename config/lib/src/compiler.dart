import 'package:conduit_config/src/configuration.dart';
import 'package:conduit_config/src/runtime.dart';
import 'package:conduit_runtime/runtime.dart';

class ConfigurationCompiler extends Compiler {
  @override
  Map<String, dynamic> compile(MirrorContext context) {
    return Map.fromEntries(context.getSubclassesOf(Configuration).map((c) {
      return MapEntry(c.simpleName, ConfigurationRuntimeImpl(c));
    }));
  }
}
