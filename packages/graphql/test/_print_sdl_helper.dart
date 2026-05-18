// Throwaway helper script that prints the derived SDL for the
// blog-model fixture to stdout. Used during development to seed the
// `expected.graphql` golden file. Not run by `dart test`.
import 'package:conduit_core/conduit_core.dart' hide SchemaBuilder;
import 'package:conduit_graphql/conduit_graphql.dart';

import 'fixtures/blog_model.dart';

void main() {
  final dataModel = ManagedDataModel([User, Post, Comment, Tag, PostTag]);
  final schema = SchemaBuilder().fromManagedDataModel(dataModel);
  // ignore: avoid_print
  print(printSchema(schema));
}
