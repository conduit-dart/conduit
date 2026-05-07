// Golden-file test: feeds the social-graph fixture through
// `SchemaBuilder.fromGraphDataModel(...)`, prints the resulting
// schema as SDL via `printSchema(...)`, and asserts byte-equality
// against the checked-in `test/fixtures/expected_graph.graphql` file.
//
// When the SDL output legitimately changes, run
//
//   dart run test/_print_graph_sdl_helper.dart > test/fixtures/expected_graph.graphql
//
// from the package root and re-commit the snapshot.

import 'dart:io';

import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:test/test.dart';

import 'fixtures/social_graph.dart';

void main() {
  test('social-graph fixture SDL matches the golden file', () {
    final dataModel = buildSocialGraphDataModel();
    final config = buildSocialGraphSchemaConfig();
    final schema = SchemaBuilder().fromGraphDataModel(
      dataModel,
      config: config,
    );
    final actual = printSchema(schema);

    final goldenUri = Uri.parse('test/fixtures/expected_graph.graphql');
    final goldenFile = File.fromUri(goldenUri);
    expect(
      goldenFile.existsSync(),
      isTrue,
      reason: 'Golden file ${goldenFile.path} not found. '
          'Run `dart run test/_print_graph_sdl_helper.dart > '
          'test/fixtures/expected_graph.graphql` from the package root.',
    );
    final expected = goldenFile.readAsStringSync();
    expect(actual, equals(expected));
  });
}
