/// Resolver factory for the **graph** side of the conduit_graphql
/// derivation pipeline.
///
/// Mirrors G3's planned SQL resolver factory but lowers GraphQL field
/// arguments into `GraphQuery<N>` / `GraphFilterExpression` instead of
/// `Query<T>` / `QueryPredicate`. Lives in its own file so the schema
/// builder doesn't depend on resolver internals — the builder accepts
/// an optional [GraphResolverFactory] and, when supplied, asks it for
/// the per-field `resolve` closure during emission.
///
/// G4 covers:
///
/// * list-all per node entity (`fetch()`)
/// * by-id per node entity (`where(id eq).fetchOne()`)
/// * edge-list per edge entity (cypher escape-hatch shaped to match
///   the schema's edge ObjectType)
/// * traverse along a typed edge from a single node
///   (`GraphContext.traverse<N>(parent, EdgeKind)`)
///
/// **Out of scope (G5):**
///
/// * Cross-source dispatch — when both `fromManagedDataModel` and
///   `fromGraphDataModel` are wired into one schema, picking which
///   resolver runs is the umbrella's job, not this factory's.
/// * Field-level authorization. A `@FieldAuthorize` decorator runs
///   ahead of the resolver chain in G5; the factory currently treats
///   every request as authorized at the schema layer (transport-level
///   auth still applies via `GraphQLController`).
///
/// ### Why the registration step
///
/// `GraphContext.traverse<N>` and `GraphQuery<N>` both carry a
/// self-referential bound `N extends GraphNode<N>`. The schema builder
/// only knows `entity.type` (a `Type`), and `Type` cannot be lifted
/// back into a generic argument at call sites — that would need
/// reflection, which `dart:mirrors` is dropping. Instead, the
/// **user** registers each concrete node type up front via
/// [registerNodeType], passing a closure that captures the static
/// `N` once. The registered closure is what the factory calls during
/// resolution. This is the same pattern `Neo4jPersistentStore`
/// already uses for hydration via `registerNodeFactory<User>(User.new)`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:conduit_graph/conduit_graph.dart';

/// Per-node-type dispatcher: the bridge between the static-type-erased
/// schema layer and the static-typed `GraphQuery<N>` / `traverse<N>`
/// surfaces.
///
/// A dispatcher is created via [GraphResolverFactory.registerNodeType].
/// User code never instantiates this directly; the factory wires it
/// up internally so the schema builder can route resolution by
/// runtime [Type] alone.
class _NodeDispatcher {
  _NodeDispatcher({
    required this.list,
    required this.byId,
    required this.traverse,
  });

  final Future<List<GraphNode<dynamic>>> Function(Map<String, dynamic> args)
      list;
  final Future<GraphNode<dynamic>?> Function(Map<String, dynamic> args) byId;
  final Future<List<GraphNode<dynamic>>> Function(
    GraphNode<dynamic> from,
    Type edgeKind,
  ) traverse;
}

/// Lowers GraphQL field arguments to [GraphQuery] / traversal calls
/// against a [GraphContext].
///
/// **Wiring:**
///
/// 1. Construct: `final factory = GraphResolverFactory(context);`
/// 2. Register each node type once: `factory.registerNodeType<User>();`
///    — this captures the static `N` so the resolvers can route work
///    through `GraphQuery<N>` and `traverse<N>` later.
/// 3. Pass the factory to the schema builder:
///    `SchemaBuilder().fromGraphDataModel(model, resolverFactory:
///    factory)`. The builder will call back into the public methods
///    below to populate `resolve` on every emitted field.
class GraphResolverFactory {
  GraphResolverFactory(this.context);

  /// The context — provides the persistent store + the data-model
  /// registry the resolvers look entity types up in.
  final GraphContext context;

  /// Static-type captures, keyed by Dart node type. Populated by
  /// [registerNodeType]; consumed by [list], [byId], and [traverse].
  final Map<Type, _NodeDispatcher> _dispatchers = {};

  /// Registers a node type with the factory. Captures the static `N`
  /// so resolution sites — which only know the runtime `Type` — can
  /// dispatch through `GraphQuery<N>` and `traverse<N>` without
  /// reflection.
  ///
  /// Call this once per concrete `GraphNode` subclass before passing
  /// the factory to the schema builder. (Calls after the schema is
  /// built are still safe but won't surface new types.)
  void registerNodeType<N extends GraphNode<N>>() {
    _dispatchers[N] = _NodeDispatcher(
      list: (args) async {
        final query = _baseQuery<N>();
        _applyArgs(query, args);
        final result = await query.fetch();
        return List<GraphNode<dynamic>>.from(result);
      },
      byId: (args) async {
        final id = args['id'];
        if (id == null) return null;
        final query = _baseQuery<N>()
          ..where((proxy) => proxy['id'].equalTo(id));
        return query.fetchOne();
      },
      traverse: (from, edgeKind) async {
        final result =
            await context.traverse<N>(from, edgeKind);
        return List<GraphNode<dynamic>>.from(result);
      },
    );
  }

  // -- Top-level Query-root resolvers --------------------------------------

  /// list-all `<plural>` resolver. Lowers `where` / `orderBy` /
  /// `limit` / `offset` args to `GraphQuery<N>` builder calls.
  Future<List<GraphNode<dynamic>>> list({
    required GraphNodeEntity entity,
    required Map<String, dynamic> args,
  }) {
    final dispatcher = _dispatcherOrThrow(entity.type);
    return dispatcher.list(args);
  }

  /// by-id `<singular>(id: ...)` resolver. The query layer adds an
  /// id-equality predicate on top of any user-supplied filter (the
  /// per-id endpoint deliberately does not surface filter args; if a
  /// caller wants additional predicates they should use the list-all
  /// field).
  Future<GraphNode<dynamic>?> byId({
    required GraphNodeEntity entity,
    required Map<String, dynamic> args,
  }) {
    final dispatcher = _dispatcherOrThrow(entity.type);
    return dispatcher.byId(args);
  }

  /// list-all-edges `<edgePlural>` resolver.
  ///
  /// Edges are not first-class in `GraphQuery<N>` — the DSL is
  /// anchored on nodes, not edges. We drop into the cypher escape
  /// hatch to produce a list of edge records. Output shape matches
  /// what the schema builder declared on the edge `GraphQLObjectType`:
  /// a list of maps keyed by `id`, the declared edge-property names,
  /// plus `from` and `to`.
  ///
  /// This is the one resolver path that does not flow through
  /// `GraphQuery<N>`. Inventing a `GraphQuery<E>` for edges in this
  /// package would creep into scope that belongs in `conduit_graph`.
  /// The cypher path keeps the factory honest with the GraphQL
  /// contract while the upstream DSL catches up.
  Future<List<Map<String, Object?>>> edgeList({
    required GraphEdgeEntity entity,
    required Map<String, dynamic> args,
  }) async {
    final label = entity.label.name;
    // No filter / pagination support yet — that surface lands when
    // `GraphQuery<E>` does.
    final cypher = 'MATCH (a)-[r:$label]->(b) '
        'RETURN id(r) AS id, properties(r) AS props, '
        'id(a) AS fromId, id(b) AS toId';
    final rows = await context.cypher(cypher);
    return [
      for (final row in rows)
        <String, Object?>{
          'id': row['id']?.toString(),
          'from': {'id': row['fromId']?.toString()},
          'to': {'id': row['toId']?.toString()},
          ..._unwrapProperties(row['props']),
        },
    ];
  }

  /// Traverse field resolver for a typed edge from a parent node.
  ///
  /// The schema builder emits, e.g., `User.posts: [Post!]!` for an
  /// `Authored` edge from `User` to `Post`. When that field is
  /// selected, this resolver runs `context.traverse(parent, Authored)`
  /// via the destination type's registered dispatcher (which captured
  /// the static `N` at registration time).
  Future<List<GraphNode<dynamic>>> traverse({
    required GraphNode<dynamic> from,
    required Type edgeType,
  }) async {
    // We need the *destination* node type, not the source's. Look it
    // up via the data-model registry on the context — every
    // user-registered edge entity carries its toType.
    final edgeEntity = _findEdgeEntityByType(edgeType);
    if (edgeEntity == null) {
      throw StateError(
        'Edge type $edgeType is not registered in the GraphContext '
        'attached to this resolver factory.',
      );
    }
    final destType = edgeEntity.toType;
    if (destType == null) {
      throw StateError(
        'Edge entity for $edgeType has no declared toType — register '
        'the edge with explicit From/To generics.',
      );
    }
    final dispatcher = _dispatcherOrThrow(destType);
    return dispatcher.traverse(from, edgeType);
  }

  // -- Internals -----------------------------------------------------------

  _NodeDispatcher _dispatcherOrThrow(Type type) {
    final d = _dispatchers[type];
    if (d == null) {
      throw StateError(
        'GraphResolverFactory has no dispatcher for $type. '
        'Call registerNodeType<$type>() before deriving the schema.',
      );
    }
    return d;
  }

  GraphEdgeEntity? _findEdgeEntityByType(Type type) {
    for (final e in context.dataModel.edgeEntities.values) {
      if (e.type == type) return e;
    }
    return null;
  }

  /// Build a base [GraphQuery] anchored on [N]'s entity. The pattern
  /// is minimal — just an unhopped node binding — because the
  /// user-facing arg surface today is `where` / `orderBy` / `limit` /
  /// `offset`, and traversal is handled by the dedicated [traverse]
  /// path.
  GraphQuery<N> _baseQuery<N extends GraphNode<N>>() {
    final entity = context.dataModel.nodeEntities[N];
    final pattern = GraphPattern<N>.build(
      (_) {},
      label: entity?.label,
      nodeType: N,
    );
    return GraphQuery<N>(
      pattern: pattern,
      executor: context.persistentStore.executeQuery,
    );
  }

  /// Lowers GraphQL `where` / `orderBy` / `limit` / `offset` args to
  /// the [GraphQuery] builder.
  ///
  /// Argument shape (matches the input types the schema builder
  /// emits in [SchemaBuilder._graphArgsForList] once filter/sort
  /// arg generation lands; the runtime mapping below is a superset
  /// so resolvers stay forward-compatible with G3's eventual
  /// extensions):
  ///
  /// ```graphql
  /// users(
  ///   where:   { name: { equalTo: "alice" }, age: { greaterThan: 21 } },
  ///   orderBy: [{ property: "age", direction: ASC }],
  ///   limit:   10,
  ///   offset:  20,
  /// ): [User!]!
  /// ```
  void _applyArgs(GraphQuery query, Map<String, dynamic> args) {
    final where = args['where'];
    if (where is Map) {
      final filter = _filterFromMap(Map<String, dynamic>.from(where));
      if (filter != null) {
        query.where((_) => filter);
      }
    }
    final orderBy = args['orderBy'];
    if (orderBy is List) {
      for (final entry in orderBy) {
        if (entry is! Map) continue;
        final property = entry['property'];
        final direction = entry['direction'];
        if (property is! String) continue;
        query.orderByProperty(
          property,
          direction: direction == 'DESC'
              ? GraphSortDirection.descending
              : GraphSortDirection.ascending,
        );
      }
    }
    final limit = args['limit'];
    if (limit is int) {
      query.limitTo(limit);
    }
    final offset = args['offset'];
    if (offset is int) {
      query.offsetBy(offset);
    }
  }

  /// Compiles a `where:` argument map into a [GraphFilterExpression]
  /// AST. Each top-level key is a property name; the nested map keys
  /// pick the operator. Unsupported operators are silently dropped —
  /// the schema-side input type only surfaces operators the AST
  /// supports, so a well-formed query never reaches this branch with
  /// an unknown key.
  GraphFilterExpression? _filterFromMap(Map<String, dynamic> map) {
    final terms = <GraphFilterExpression>[];
    for (final entry in map.entries) {
      final property = entry.key;
      final ops = entry.value;
      if (ops is! Map) continue;
      ops.forEach((op, value) {
        switch (op) {
          case 'equalTo':
            terms.add(GraphPropertyFilter(
              property: property,
              operator: GraphFilterOperator.equal,
              value: value,
            ));
          case 'notEqualTo':
            terms.add(GraphPropertyFilter(
              property: property,
              operator: GraphFilterOperator.notEqual,
              value: value,
            ));
          case 'greaterThan':
            terms.add(GraphPropertyFilter(
              property: property,
              operator: GraphFilterOperator.greaterThan,
              value: value,
            ));
          case 'greaterThanOrEqualTo':
            terms.add(GraphPropertyFilter(
              property: property,
              operator: GraphFilterOperator.greaterThanOrEqual,
              value: value,
            ));
          case 'lessThan':
            terms.add(GraphPropertyFilter(
              property: property,
              operator: GraphFilterOperator.lessThan,
              value: value,
            ));
          case 'lessThanOrEqualTo':
            terms.add(GraphPropertyFilter(
              property: property,
              operator: GraphFilterOperator.lessThanOrEqual,
              value: value,
            ));
          case 'contains':
            if (value != null) {
              terms.add(GraphPropertyFilter(
                property: property,
                operator: GraphFilterOperator.contains,
                value: value,
              ));
            }
          case 'startsWith':
            if (value is String) {
              terms.add(GraphPropertyFilter(
                property: property,
                operator: GraphFilterOperator.startsWith,
                value: value,
              ));
            }
          case 'endsWith':
            if (value is String) {
              terms.add(GraphPropertyFilter(
                property: property,
                operator: GraphFilterOperator.endsWith,
                value: value,
              ));
            }
          case 'isIn':
            if (value is List) {
              terms.add(GraphPropertyFilter(
                property: property,
                operator: GraphFilterOperator.inList,
                value: List<Object?>.unmodifiable(value),
              ));
            }
          case 'isNull':
            if (value == true) {
              terms.add(GraphPropertyFilter(
                property: property,
                operator: GraphFilterOperator.isNull,
              ));
            }
          case 'isNotNull':
            if (value == true) {
              terms.add(GraphPropertyFilter(
                property: property,
                operator: GraphFilterOperator.isNotNull,
              ));
            }
          default:
            // Unknown operator — drop on the floor. The schema-side
            // input type does not expose it, so a well-formed client
            // will not have produced it.
            break;
        }
      });
    }
    if (terms.isEmpty) return null;
    if (terms.length == 1) return terms.first;
    return GraphCompoundFilter(GraphFilterCombinator.and, terms);
  }

  /// Best-effort unpacking of a `properties(r)` map returned from
  /// raw Cypher. Some Bolt implementations decode the map directly;
  /// older paths surface it as a JSON-encoded string. Handle both.
  Map<String, Object?> _unwrapProperties(Object? raw) {
    if (raw is Map) {
      return Map<String, Object?>.from(raw);
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      } on FormatException {
        // fall through
      }
    }
    return const {};
  }
}
