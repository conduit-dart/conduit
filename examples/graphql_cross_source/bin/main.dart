import 'package:conduit_core/conduit_core.dart';
import 'package:graphql_cross_source_example/graphql_cross_source_example.dart';

Future<void> main() async {
  final app = Application<CrossSourceChannel>()
    ..options.port = 8888
    ..options.address = '127.0.0.1';
  await app.startOnCurrentIsolate();
  print('Cross-source GraphQL example listening on '
      'http://${app.options.address}:${app.options.port}/graphql');
}
