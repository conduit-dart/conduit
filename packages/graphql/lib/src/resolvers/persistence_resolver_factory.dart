/// G5 cross-source resolver umbrella.
///
/// `PersistenceResolverFactory` owns one optional [SqlResolverFactory]
/// and one optional [GraphResolverFactory] and produces a
/// [ResolverHookSet] that the unified [SchemaBuilder.fromPersistence]
/// path threads through both halves.
///
/// **What this class is.**
///
/// * The single point of attachment between [SchemaBuilder] and the
///   resolver layer when a deployment serves both a relational and a
///   graph store from one schema. The schema builder calls into the
///   hook set at every emission site (attribute, relationship,
///   query-root list, query-root by-pk, graph traversal, graph edge
///   list); the hook set delegates to the appropriate side based on
///   which descriptor it received.
/// * The hook for **field-level authorization** (G5's other deliverable
///   alongside cross-source dispatch). When [hooks] is called with a
///   non-null [FieldAuthPolicy], every produced resolver is wrapped in
///   an auth-checking closure that consults the policy + the conduit
///   [Request]'s [Authorization] before dispatching the underlying
///   resolver. Failed checks raise a `GraphQLException` keyed at the
///   field path, per the GraphQL execution spec.
///
/// **What this class is not.**
///
/// * Not a cross-source join engine. Stitching SQL and graph data
///   into one response is the application's responsibility — see
///   `docs/persistence/graphql-cross-source.md` for the worked
///   pattern. The umbrella's job is to *route* per-field, not to
///   *fan out* per-query.
/// * Not a coordinator for cross-store transactions. See the
///   [Persistence] umbrella docs (`docs/persistence/multi-backend.md`)
///   for why XA/2PC is out of scope.
library;

import 'dart:async';

import 'package:conduit_core/conduit_core.dart';
import 'package:graphql_schema2/graphql_schema2.dart';

import '../auth/field_authorize.dart';
import 'graph_resolver_factory.dart';
import 'sql_resolver_factory.dart';

/// Resolver-attachment hook set for the unified
/// [SchemaBuilder.fromPersistence] path.
///
/// The schema builder invokes one of the four `*Resolver` callbacks
/// per emission site. Each callback returns a
/// `GraphQLFieldResolver<Object?, Object?>` (the type
/// graphql_schema2 v6.5.0 attaches to a `GraphQLObjectField`'s
/// `resolve:` slot) or `null` to leave the slot empty.
///
/// On the relational side the descriptors are
/// [ManagedAttributeDescription], [ManagedRelationshipDescription],
/// and [ManagedEntity] — the same shapes G3's [SchemaBuilder] hooks
/// already accept. On the graph side the schema builder still
/// inline-invokes [GraphResolverFactory.list] / `byId` / `traverse` /
/// `edgeList`, because graphql_schema2 v6.5.0 ties resolvers to
/// `GraphQLObjectField` at construction time and a hook set cannot
/// participate in that path without a deeper schema rewrite. The
/// graph-side hook is therefore the [graphFactory] handle the
/// builder pulls directly out of the resolver-hook set's owner.
class ResolverHookSet {
  ResolverHookSet({
    required this.attributeResolver,
    required this.relationshipResolver,
    required this.queryListResolver,
    required this.queryByPkResolver,
    this.graphFactory,
  });

  /// Hook for an attribute field on a SQL `ManagedObject` projection.
  /// Mirrors [SqlResolverFactory.attributeResolverFor]'s signature.
  final GraphQLFieldResolver<Object?, Object?>? Function(
    ManagedAttributeDescription attr,
  ) attributeResolver;

  /// Hook for a relationship field on a SQL projection.
  final GraphQLFieldResolver<Object?, Object?>? Function(
    ManagedRelationshipDescription rel,
  ) relationshipResolver;

  /// Hook for a Query-root list-all field for a SQL entity.
  final GraphQLFieldResolver<Object?, Object?>? Function(
    ManagedEntity entity,
  ) queryListResolver;

  /// Hook for a Query-root by-pk field for a SQL entity.
  final GraphQLFieldResolver<Object?, Object?>? Function(
    ManagedEntity entity,
  ) queryByPkResolver;

  /// Direct handle to the graph factory, exposed because
  /// [SchemaBuilder.fromGraphDataModel] inline-invokes graph resolvers
  /// during emission. Null when no graph store is configured.
  final GraphResolverFactory? graphFactory;
}

/// Umbrella that bundles a [SqlResolverFactory] and a
/// [GraphResolverFactory], producing the [ResolverHookSet] consumed by
/// [SchemaBuilder.fromPersistence].
///
/// The generic parameter [G] is the graph-store type the application's
/// [Persistence] umbrella is parameterized on — typically
/// `GraphPersistentStore` or a concrete backend such as
/// `Neo4jPersistentStore`. Carrying it through here keeps the
/// `Persistence<G>` and `PersistenceResolverFactory<G>` shapes
/// type-aligned at the use site.
class PersistenceResolverFactory<G extends Object> {
  /// Constructs the umbrella.
  ///
  /// Pass [sql] for relational dispatch, [graph] for graph dispatch, or
  /// both for cross-source schemas. An umbrella with neither configured
  /// is legal but useless — every produced resolver returns `null`.
  PersistenceResolverFactory({this.sql, this.graph});

  /// SQL resolver factory, or null in graph-only deployments.
  final SqlResolverFactory? sql;

  /// Graph resolver factory, or null in SQL-only deployments.
  final GraphResolverFactory? graph;

  /// Builds the [ResolverHookSet] used by
  /// [SchemaBuilder.fromPersistence].
  ///
  /// When [authPolicy] is non-null, every produced resolver is wrapped
  /// in an auth-checking closure that consults the policy + the
  /// request's [Authorization] before dispatching. The wrapper:
  ///
  /// 1. Calls the underlying resolver's factory to produce the inner
  ///    resolver.
  /// 2. Reads the [FieldAuthorize] declaration for the descriptor off
  ///    [authPolicy].
  /// 3. If a declaration exists, the wrapped resolver pulls the
  ///    [Request] from `args['conduitRequest']` and checks its
  ///    [Authorization.scopes] against the declaration's [scopes]
  ///    (any-of). On scope mismatch, [allowOwner] (if supplied) is
  ///    consulted with `(parent, request)`; a `true` return permits
  ///    the field, `false` raises a [GraphQLException].
  /// 4. If no declaration exists, the inner resolver runs directly.
  ///
  /// When [authPolicy] is null, the hook set produces inner resolvers
  /// untouched.
  ResolverHookSet hooks({FieldAuthPolicy? authPolicy}) {
    final sqlFactory = sql;
    final graphFactory = graph;

    GraphQLFieldResolver<Object?, Object?>? wrap(
      Object descriptor,
      GraphQLFieldResolver<Object?, Object?>? inner,
    ) {
      if (authPolicy == null || inner == null) return inner;
      final authDecl = authPolicy.authFor(descriptor);
      if (authDecl == null) return inner;
      return _wrapWithAuth(inner, authDecl);
    }

    return ResolverHookSet(
      attributeResolver: (attr) {
        if (sqlFactory == null) return null;
        final inner = sqlFactory.attributeResolverFor(attr);
        return wrap(attr, inner);
      },
      relationshipResolver: (rel) {
        if (sqlFactory == null) return null;
        final inner = sqlFactory.relationshipResolverFor(rel);
        return wrap(rel, inner);
      },
      queryListResolver: (entity) {
        if (sqlFactory == null) return null;
        final inner = sqlFactory.listResolverFor(entity);
        return wrap(entity, inner);
      },
      queryByPkResolver: (entity) {
        if (sqlFactory == null) return null;
        final inner = sqlFactory.byPkResolverFor(entity);
        return wrap(entity, inner);
      },
      graphFactory: graphFactory,
    );
  }
}

/// Wraps [inner] in an auth-checking closure honoring [auth].
///
/// Public because the cross-source schema builder needs to wrap the
/// inline graph resolvers it constructs at emission time (see
/// `SchemaBuilder.fromPersistence`'s graph-side branch). Most callers
/// reach this indirectly via [PersistenceResolverFactory.hooks].
GraphQLFieldResolver<Object?, Object?> wrapResolverWithAuth(
  GraphQLFieldResolver<Object?, Object?> inner,
  FieldAuthorize auth,
) =>
    _wrapWithAuth(inner, auth);

/// Key for the per-resolver-call [Authorization] override. Tests (and
/// non-Conduit hosts) can write an [Authorization] under this key in
/// the executor's globalVariables / argumentValues map; the wrapper
/// reads it directly and skips the [Request] lookup.
///
/// In production the [GraphQLController] only writes
/// [authorizationArgKey] (`'conduitRequest'`); the wrapper falls back
/// to that and pulls `request.authorization` off it. Either channel
/// works.
const String fieldAuthorizationArgKey = 'conduitAuthorization';

GraphQLFieldResolver<Object?, Object?> _wrapWithAuth(
  GraphQLFieldResolver<Object?, Object?> inner,
  FieldAuthorize auth,
) {
  return (Object? parent, Map<String, dynamic> args) async {
    Authorization? authorization;
    Request? request;

    final directAuth = args[fieldAuthorizationArgKey];
    if (directAuth is Authorization) {
      authorization = directAuth;
    }
    final raw = args[authorizationArgKey];
    if (raw is Request) {
      request = raw;
      authorization ??= raw.authorization;
    }

    if (authorization == null && request == null) {
      throw GraphQLException.fromMessage(
        'Field requires authorization but the GraphQL execution context '
        'has neither a conduit Request nor an Authorization attached. '
        'Make sure the field is reached through GraphQLController '
        '(production) or that tests write conduitAuthorization into '
        'argumentValues.',
      );
    }

    final hasScope = authorization != null &&
        auth.scopes.any(authorization.isAuthorizedForScope);
    if (!hasScope) {
      final allowOwner = auth.allowOwner;
      final ownerOk = allowOwner != null &&
          parent != null &&
          request != null &&
          allowOwner(parent, request);
      if (!ownerOk) {
        throw GraphQLException.fromMessage(
          auth.scopes.isEmpty
              ? 'Field is not authorized for this caller.'
              : 'Field requires one of the following scopes: '
                  '${auth.scopes.join(", ")}.',
        );
      }
    }

    final result = inner(parent, args);
    if (result is Future) {
      return await result;
    }
    return result;
  };
}
