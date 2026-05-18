// Golden-file test: feeds the 5-entity blog fixture through
// `SchemaBuilder.fromManagedDataModel(...)`, prints the resulting
// schema as SDL via `printSchema(...)`, and asserts byte-equality
// against the checked-in `test/fixtures/expected.graphql` file.
//
// When the SDL output legitimately changes, run
//
//   dart run test/_print_sdl_helper.dart > test/fixtures/expected.graphql
//
// from the package root and re-commit the snapshot.

import 'dart:io';

import 'package:conduit_core/conduit_core.dart' hide SchemaBuilder;
import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:test/test.dart';

import 'fixtures/blog_model.dart';

void main() {
  test('blog-fixture SDL matches the golden file', () {
    final dataModel = ManagedDataModel([User, Post, Comment, Tag, PostTag]);
    final schema = SchemaBuilder().fromManagedDataModel(dataModel);
    final actual = printSchema(schema);

    // The golden lives next to this test. We resolve the path
    // relative to the file URI rather than the cwd so the test
    // doesn't depend on `dart test` being invoked from the package
    // root (it usually is, but the IDE runner sometimes isn't).
    final goldenUri = Uri.parse('test/fixtures/expected.graphql');
    final goldenFile = File.fromUri(goldenUri);
    expect(
      goldenFile.existsSync(),
      isTrue,
      reason: 'Golden file ${goldenFile.path} not found. '
          'Run `dart run test/_print_sdl_helper.dart > '
          'test/fixtures/expected.graphql` from the package root.',
    );
    final expected = goldenFile.readAsStringSync();
    // Strict byte-equality. If this fails, the diff in the test
    // output is the meaningful signal.
    expect(actual, equals(expected));
  });
}
