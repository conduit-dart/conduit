import 'dart:convert';

import 'package:application/application.dart';
import 'package:dependency/dependency.dart';

void main() {
  // ignore: avoid_print
  print(json.encode({
    "Consumer": Consumer().message,
    "ConsumerSubclass": ConsumerSubclass().message,
    "ConsumerScript": ConsumerScript().message
  }),);
}

class ConsumerScript extends Consumer {}
