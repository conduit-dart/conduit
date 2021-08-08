import 'dart:convert';

import 'package:application/application.dart';
import 'package:conduit_runtime/runtime.dart';
import 'package:dependency/dependency.dart';

import 'main.reflectable.dart';

void main() {
  initializeReflectable();
  print(json.encode({
    "Consumer": Consumer().message,
    "ConsumerSubclass": ConsumerSubclass().message,
    "ConsumerScript": ConsumerScript().message
  }));
}

@runtimeReflector
class ConsumerScript extends Consumer {}
