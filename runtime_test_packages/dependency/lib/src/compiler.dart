import 'package:conduit_runtime/runtime.dart';

import '../dependency.dart';

@runtimeReflector
class DependencyCompiler extends Compiler {
  @override
  Map<String, dynamic> compile(MirrorContext context) {
    return Map.fromEntries(context.getSubclassesOf(Consumer).map((c) {
      return MapEntry(
        c.simpleName,
        ConsumerRuntimeImpl(),
      );
    }))
      ..addAll({"Consumer": ConsumerRuntimeImpl()});
  }
}

@runtimeReflector
class ConsumerRuntimeImpl extends ConsumerRuntime implements SourceCompiler {
  @override
  String get message => "mirrored";

  @override
  String compile(BuildContext ctx) => """
import 'package:dependency/dependency.dart';
import 'package:conduit_runtime/conduit_runtime.dart';

final instance = ConsumerRuntimeImpl();

@runtimeReflector
class ConsumerRuntimeImpl extends ConsumerRuntime {
  @override
  String get message => "generated";
}
  """;
}
