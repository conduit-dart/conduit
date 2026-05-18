// Throwaway helper script that prints the derived SDL for the
// cross-source fixture to stdout. Used during development to seed the
// `expected_cross_source.graphql` golden file. Not run by `dart test`.

import 'package:conduit_graphql/conduit_graphql.dart';

import '_helpers/fake_persistence.dart';
import 'fixtures/cross_source_fixture.dart';

void main() {
  final persistence = buildFakePersistence(
    sqlModel: buildCrossSourceSqlModel(),
    graphModel: buildCrossSourceGraphModel(),
  );
  final result = SchemaBuilder().fromPersistence(
    persistence,
    graphConfig: buildCrossSourceGraphConfig(),
  );
  // ignore: avoid_print
  print(printSchema(result.schema));
}
