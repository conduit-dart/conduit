/// GraphQL HTTP transport for Conduit.
///
/// `conduit_graphql` ships a [GraphQLController] — a [ResourceController]
/// subclass that implements the
/// [GraphQL-over-HTTP spec](https://graphql.github.io/graphql-over-http/draft/)
/// for `POST` and `GET` against a hand-written
/// [GraphQLSchema](package:graphql_schema2/graphql_schema2.dart).
///
/// This is **phase G1** of the Conduit GraphQL plan. The follow-up
/// phases — schema derivation from `ManagedDataModel` (G2), SQL
/// resolvers (G3), graph resolvers (G4), and cross-source dispatch
/// + field-level auth (G5) — are not in this package yet.
///
/// See `README.md` for usage and the deferred-work list.
library;

// Re-export the schema + parser surfaces callers need to assemble a
// hand-written schema. Re-exporting keeps callers from having to add
// graphql_schema2 / graphql_parser2 / graphql_server2 to their own
// pubspecs just to construct the argument to `GraphQLController`.
export 'package:graphql_parser2/graphql_parser2.dart';
export 'package:graphql_schema2/graphql_schema2.dart';
export 'package:graphql_server2/graphql_server2.dart';

export 'src/controller/graphql_controller.dart';
export 'src/schema/builder.dart';
export 'src/schema/scalars.dart';
export 'src/schema/sdl_printer.dart';
