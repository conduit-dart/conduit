import 'package:conduit_runtime/runtime.dart';

@runtimeReflector
class Consumer {
  String get message =>
      (RuntimeContext.current[runtimeType] as ConsumerRuntime).message;
}

@runtimeReflector
abstract class ConsumerRuntime {
  String get message;
}
