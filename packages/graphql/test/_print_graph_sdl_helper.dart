// Throwaway helper script that prints the derived SDL for the
// social-graph fixture to stdout. Used during development to seed the
// `expected_graph.graphql` golden file. Not run by `dart test`.
//
// Uses `stdout.write` rather than `print` so the produced byte stream
// matches what `printSchema` returns exactly (no extra trailing
// newline) — the golden test compares bytes verbatim.
import 'dart:io';

import 'package:conduit_graphql/conduit_graphql.dart';

import 'fixtures/social_graph.dart';

void main() {
  final dataModel = buildSocialGraphDataModel();
  final config = buildSocialGraphSchemaConfig();
  final schema = SchemaBuilder().fromGraphDataModel(dataModel, config: config);
  stdout.write(printSchema(schema));
}
