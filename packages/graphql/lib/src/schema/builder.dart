import 'package:conduit_core/conduit_core.dart';
import 'package:graphql_schema2/graphql_schema2.dart';

/// Forward-declared entry point for schema derivation from a Conduit
/// data model.
///
/// **Status: G2 placeholder.** G1 ships only the HTTP transport — the
/// `GraphQLController` accepts a hand-written [GraphQLSchema]. This
/// class exists so callers can already see (and import) the API surface
/// that G2 will fill in; every method is currently
/// `UnimplementedError`.
///
/// ### Design intent for G2
///
/// G2 will walk a [ManagedDataModel] and emit a [GraphQLSchema]
/// directly, mirroring the deferred-ref pattern used by Conduit's
/// existing OpenAPI emitter (`packages/common/lib/src/openapi/`):
///
/// 1. Iterate every [ManagedEntity] in the model.
/// 2. For each entity, emit a `GraphQLObjectType` whose fields are
///    derived from `ManagedAttributeDescription` (scalars, dates,
///    booleans, transient props) and `ManagedRelationshipDescription`
///    (object / list relationships).
/// 3. Resolve circular references lazily — relationships register a
///    deferred reference into the type registry, exactly like
///    `APIComponentCollection<T>` does for OpenAPI schemas.
/// 4. Emit input types for `where:` / `orderBy:` / `limit:` / `offset:`
///    arguments on root-`Query` fields. The argument shape lowers to
///    `Query<T>` predicates in G3.
///
/// ### Why this is here in G1
///
/// Pinning the public name and import path now means G2 lands as a
/// pure addition rather than a rename — downstream callers writing
/// hand-written schemas in G1 can structure their wire-up around this
/// class and replace their hand-built [GraphQLSchema] with
/// `SchemaBuilder.fromManagedDataModel(...)` in G2 without touching
/// the controller mount.
class SchemaBuilder {
  SchemaBuilder._();

  /// Derives a [GraphQLSchema] from [model].
  ///
  /// G2 work item. See class-level docs for the planned algorithm.
  static GraphQLSchema fromManagedDataModel(ManagedDataModel model) {
    throw UnimplementedError(
      'SchemaBuilder.fromManagedDataModel: schema derivation lands in G2 of '
      'the conduit_graphql plan. For G1, hand-assemble a GraphQLSchema and '
      'pass it directly to GraphQLController.',
    );
  }

  /// Derives a `GraphQLObjectType` for a single [entity], without
  /// closing over the rest of the model. G2 will use this to register
  /// types into a shared registry as it walks the model.
  static GraphQLObjectType objectTypeFor(ManagedEntity entity) {
    throw UnimplementedError(
      'SchemaBuilder.objectTypeFor: schema derivation lands in G2 of the '
      'conduit_graphql plan.',
    );
  }
}
