import 'dart:convert';

import 'package:application/application.dart';
import 'package:dependency/dependency.dart';

void main() {
  const foo = String.fromEnvironment("FOO");
  // ignore: avoid_print
  print(
    json.encode({
      "Consumer": Consumer().message,
      "ConsumerSubclass": ConsumerSubclass().message,
      "ConsumerScript": ConsumerScript().message,
      ...foo.isNotEmpty ? {"FOO": foo} : {},
    }),
  );
}

class ConsumerScript extends Consumer {}
