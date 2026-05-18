// Golden-file test: feeds the cross-source fixture through
// `SchemaBuilder.fromPersistence(...)`, prints the resulting schema as
// SDL via `printSchema(...)`, and asserts byte-equality against the
// checked-in `test/fixtures/expected_cross_source.graphql` file.
//
// When the SDL output legitimately changes, run
//
//   dart run test/_print_cross_source_sdl_helper.dart > \
//     test/fixtures/expected_cross_source.graphql
//
// from the package root and re-commit the snapshot.

import 'dart:io';

import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:test/test.dart';

import '_helpers/fake_persistence.dart';
import 'fixtures/cross_source_fixture.dart';

void main() {
  test('cross-source fixture SDL matches the golden file', () {
    final persistence = buildFakePersistence(
      sqlModel: buildCrossSourceSqlModel(),
      graphModel: buildCrossSourceGraphModel(),
    );
    final result = SchemaBuilder().fromPersistence(
      persistence,
      graphConfig: buildCrossSourceGraphConfig(),
    );
    final actual = printSchema(result.schema);

    final goldenUri = Uri.parse('test/fixtures/expected_cross_source.graphql');
    final goldenFile = File.fromUri(goldenUri);
    expect(
      goldenFile.existsSync(),
      isTrue,
      reason: 'Golden file ${goldenFile.path} not found. '
          'Run `dart run test/_print_cross_source_sdl_helper.dart > '
          'test/fixtures/expected_cross_source.graphql` from the package root.',
    );
    final expected = goldenFile.readAsStringSync();
    expect(actual, equals(expected));
  });
}
