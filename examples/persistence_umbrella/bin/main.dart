// Entry point for the persistence-umbrella example.
//
// Boots [ExampleChannel] on `localhost:8888`. Try:
//
//     curl http://localhost:8888/me/1
//     curl http://localhost:8888/me/2
//
// Both routes touch the SQL store (for the user) and the graph store
// (for the friends list). The example uses fake in-memory stores so it
// runs without infrastructure.

import 'package:conduit_core/conduit_core.dart';
import 'package:persistence_umbrella_example/persistence_umbrella_example.dart';

Future<void> main() async {
  final app = Application<ExampleChannel>()
    ..options.port = 8888
    ..options.address = 'localhost';

  await app.start(numberOfInstances: 1, consoleLogging: true);
  // ignore: avoid_print
  print('Listening on http://${app.options.address}:${app.options.port}');
}
