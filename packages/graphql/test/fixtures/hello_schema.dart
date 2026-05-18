import 'package:conduit_graphql/conduit_graphql.dart';

/// A tiny hand-written schema used by the unit + e2e tests.
///
/// G1 ships only the HTTP transport — schemas are caller-supplied. This
/// fixture exists purely to exercise the controller's plumbing (parse,
/// validate, execute, error envelopes, introspection). G2 will replace
/// the hand-written path with derivation from `ManagedDataModel`, but
/// hand-written schemas remain the supported authoring path.
///
/// `graphql_server2`'s executor casts resolvers down to
/// `(dynamic, Map<String, dynamic>) => dynamic` regardless of the
/// generic types declared on `field<Value, Serialized>`. To stay
/// compatible we leave the resolver closures untyped — Dart's
/// generic-function inference would otherwise specialize them and
/// trigger a runtime cast failure inside the executor.
final GraphQLSchema helloSchema = graphQLSchema(
  queryType: objectType(
    'Query',
    fields: [
      field(
        'hello',
        graphQLString,
        resolve: (_, _) => 'world',
      ),
      field(
        'echo',
        graphQLString,
        inputs: [
          GraphQLFieldInput('message', graphQLString.nonNullable()),
        ],
        resolve: (_, args) => args['message'] as String,
      ),
      // Used by the "resolver throws" test. Spec says runtime resolver
      // errors come back inside the JSON envelope, not as HTTP 4xx.
      field(
        'boom',
        graphQLString,
        resolve: (_, _) => throw StateError('boom'),
      ),
    ],
  ),
  mutationType: objectType(
    'Mutation',
    fields: [
      field(
        'shout',
        graphQLString,
        inputs: [
          GraphQLFieldInput('message', graphQLString.nonNullable()),
        ],
        resolve: (_, args) =>
            (args['message'] as String).toUpperCase(),
      ),
    ],
  ),
);
