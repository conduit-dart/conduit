# Script

You may also run Conduit applications with a standalone script, instead of `conduit serve`. In fact, `conduit serve` creates a temporary Dart script to run the application. If you created your application with `conduit create`, a standalone already exists in your project named `bin/main.dart`.

A sample script looks like this:

```dart
import 'dart:async';
import 'dart:io';

import 'package:conduit/conduit.dart';
import 'package:my_application/my_application.dart';

Future main() async {
  var app = new Application<MyApplicationChannel>()
    ..options.port = 8888
    ..options.configurationFilePath = "config.yaml";

  await app.start(numberOfInstances: 3);    
}
```

This script can be used in place of `conduit serve`, but you must configure all `ApplicationOptions` in this script and not through the CLI.

