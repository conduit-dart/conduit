/// SQL-side resolver factory for the schema derived in G2.
///
/// `SqlResolverFactory` produces field resolvers that lower a GraphQL
/// query against a `ManagedDataModel`-derived schema into Conduit
/// `Query<T>` calls. It is the SQL half of the resolver framework
/// (G3); the graph half (G4) lives in a sibling factory.
///
/// ### Predicate lowering
///
/// `where:` filter args are GraphQL `<Scalar>Predicate` input objects.
/// Each scalar field on a generated `<Entity>Filter` input takes one
/// of these predicate inputs. The lowering correspondence is:
///
/// | GraphQL predicate | Conduit matcher                                         |
/// |-------------------|---------------------------------------------------------|
/// | `eq: V`           | `QueryExpression.equalTo(V)`                            |
/// | `ne: V`           | `QueryExpression.notEqualTo(V)`                         |
/// | `gt: V`           | `QueryExpression.greaterThan(V)`                        |
/// | `gte: V`          | `QueryExpression.greaterThanEqualTo(V)`                 |
/// | `lt: V`           | `QueryExpression.lessThan(V)`                           |
/// | `lte: V`          | `QueryExpression.lessThanEqualTo(V)`                    |
/// | `in: [V]`         | `QueryExpression.oneOf([V])`                            |
/// | `notIn: [V]`      | `QueryExpression.not.oneOf([V])`                        |
/// | `like: S`         | `QueryExpression.contains(S)` (substring; string-only)  |
/// | `isNull: true`    | `QueryExpression.isNull()`                              |
/// | `isNull: false`   | `QueryExpression.isNotNull()`                           |
///
/// Predicates within a single field AND together (Conduit's matcher
/// expressions are conjunctive by default). Predicates across multiple
/// fields also AND. Cross-field OR is intentionally not exposed in v1
/// — the plan keeps the surface narrow; OR composition can be added
/// behind a flag once apps need it.
///
/// `orderBy:` is a list of `<Entity>SortInput` objects, each with a
/// `field` enum (one entry per attribute) and a `direction`
/// (`ASC | DESC`). Order in the list is sort precedence — first sort
/// is primary, second is secondary, etc.
///
/// `limit:` lowers to `Query.fetchLimit`; `offset:` lowers to
/// `Query.offset`.
///
/// ### Resolver shape
///
/// graphql_schema2 v6.5.0 defines a resolver as
/// `FutureOr<V> Function(Serialized parent, Map<String, dynamic> args)`.
/// The executor passes the merged map of `globalVariables` and the
/// field's argument values as the second positional, so `args` doubles
/// as the channel for `'conduitRequest'` (and, in G3+, for the
/// per-request `DataLoaderRegistry`). G5 will use the same channel for
/// auth context.
///
/// Note: graphql_server2 6.5.0 short-circuits `resolveFieldValue` when
/// `parent is Map` — it returns `parent[fieldName]` and skips the
/// resolver. The factory's [attributeResolverFor] therefore only needs
/// to return a closure when the value would be wrong as a raw map
/// lookup (e.g. DateTime needs ISO-8601 stringification, but the
/// scalar's serializer handles that downstream so we still return null
/// in v1). For ManagedObjects we ALWAYS shape the result into a Map
/// before handing it back to the executor — that aligns the two paths
/// (Map vs ManagedObject) on the executor's preferred path.
library;

import 'dart:async';

import 'package:conduit_core/conduit_core.dart';
// `QuerySortDescriptor` lives in conduit_core's source tree but is not
// surfaced through `conduit_core.dart`'s public exports. The mixin
// surface (`QueryMixin.sortDescriptors` / `.expressions`) does cross
// the boundary, so we reach into the private path to construct values
// the mixin contract requires.
// ignore: implementation_imports
import 'package:conduit_core/src/db/query/sort_descriptor.dart';
import 'package:graphql_schema2/graphql_schema2.dart';

import 'data_loader.dart';

/// Key used to surface the per-request [DataLoaderRegistry] through the
/// graphql_server2 globals channel. The controller injects the registry
/// here at execution time and the factory's relationship resolvers
/// look it up.
const String dataLoaderRegistryArgKey = 'conduitDataLoaderRegistry';

/// Builds field resolvers that lower GraphQL queries into Conduit
/// `Query<T>` operations against a [ManagedContext].
///
/// One factory per `ManagedContext`. The factory is stateless beyond
/// the context handle — every resolver it produces is itself
/// idempotent and side-effect-free, so a single factory can serve
/// every controller instance bound to the same context.
class SqlResolverFactory {
  SqlResolverFactory(this.context);

  /// The Conduit [ManagedContext] every produced resolver runs against.
  /// Must contain entities matching the schema the resolvers were
  /// hooked into; mismatches surface at first execution as
  /// `ArgumentError`s from `Query.forEntity`.
  final ManagedContext context;

  /// Builds a fresh [DataLoaderRegistry]. The controller calls this
  /// per request to keep loader caches request-scoped.
  DataLoaderRegistry newRegistry() => DataLoaderRegistry();

  // -- Public hooks -----------------------------------------------------------

  /// Returns the resolver that powers `<Entity>(<pk>: <pkType>!)`.
  ///
  /// The closure pulls the pk from `args[<pkName>]`, builds a
  /// `Query<E>.where(...)` matching it, runs `fetchOne`, and returns
  /// the row's [_managedObjectAsMap] form (or `null` if no row matched).
  GraphQLFieldResolver<Object?, Object?> byPkResolverFor(ManagedEntity entity) {
    final pk = entity.primaryKeyAttribute;
    if (pk == null) {
      throw StateError(
        'Cannot build a by-pk resolver for entity ${entity.name}: it has '
        'no primary-key attribute.',
      );
    }
    return (Object? parent, Map<String, dynamic> args) async {
      final raw = args[pk.name];
      if (raw == null) return null;
      final coerced = _coerceScalar(pk, raw);
      if (coerced == null) return null;
      final query = Query.forEntity(entity, context);
      _addEqualityPredicate(query, pk, coerced);
      return query.fetchOne();
    };
  }

  /// Returns the resolver that powers `<plural>: [<Entity>!]!`.
  ///
  /// The closure inspects `args` for the optional `where:`, `orderBy:`,
  /// `limit:`, and `offset:` keys and lowers each present argument to
  /// the corresponding `Query` mutation (predicates → `expressions`,
  /// sorts → `sortDescriptors`, limit/offset → fields of the same
  /// name). It then runs `fetch()` and returns each row as a Map.
  GraphQLFieldResolver<Object?, Object?> listResolverFor(ManagedEntity entity) {
    return (Object? parent, Map<String, dynamic> args) async {
      final query = Query.forEntity(entity, context);
      _applyListArgs(query, entity, args);
      return query.fetch();
    };
  }

  /// Returns the resolver for a relationship field on a parent entity.
  ///
  /// * `belongsTo` resolvers look up the destination row by its primary
  ///   key, batched through a per-request loader (so resolving 100
  ///   posts' `author` fans out to one `IN (...)` round-trip).
  /// * `hasMany` resolvers fetch the inverse-side rows for the parent
  ///   PK, also batched (so resolving `users { posts }` for 50 users
  ///   fans out to one `WHERE author_id IN (...)` round-trip).
  /// * `hasOne` resolvers run the same path as hasMany but wrap the
  ///   list back into a single optional result.
  GraphQLFieldResolver<Object?, Object?> relationshipResolverFor(
    ManagedRelationshipDescription rel,
  ) {
    switch (rel.relationshipType) {
      case ManagedRelationshipType.belongsTo:
        return _belongsToResolver(rel);
      case ManagedRelationshipType.hasMany:
        return _hasManyResolver(rel);
      case ManagedRelationshipType.hasOne:
        return _hasOneResolver(rel);
    }
  }

  /// Returns a resolver for an attribute that pulls [attr]'s value off
  /// the parent (whether the parent is a `Map`, a `ManagedObject`, or
  /// a transient-property holder).
  ///
  /// **Why we always return a non-null resolver here.** graphql_server2
  /// v6.5.0 short-circuits `resolveFieldValue` when `objectValue is Map`
  /// — it does `objectValue[fieldName]` and skips the resolver. That
  /// short-circuit means *relationship* resolvers never run when the
  /// parent is a Map (their key is absent from the asMap() projection,
  /// so the lookup yields null). To force the executor through the
  /// resolver path for relationships, our list resolvers return
  /// ManagedObject instances rather than maps. ManagedObject is not a
  /// Map, so it falls through to the resolver path — and we then need
  /// every attribute to ship its own resolver, because there's no
  /// `defaultFieldResolver` on the GraphQL executor that would handle
  /// scalars.
  ///
  /// The closure returned here handles all three parent shapes:
  ///   * `ManagedObject` — read via the `[]` operator (which routes
  ///     through `backing` and any output-side transients).
  ///   * `Map` — read via `parent[attr.name]` (covers the case where a
  ///     hand-rolled resolver in some other branch returns a Map).
  ///   * anything else — surface `null`.
  GraphQLFieldResolver<Object?, Object?>? attributeResolverFor(
    ManagedAttributeDescription attr,
  ) {
    final name = attr.name;
    return (Object? parent, Map<String, dynamic> args) {
      if (parent is ManagedObject) {
        return _serializeAttributeValue(attr, parent[name]);
      }
      if (parent is Map) {
        return _serializeAttributeValue(attr, parent[name]);
      }
      return null;
    };
  }

  /// Serializes an attribute value for return through the GraphQL
  /// executor.
  ///
  /// graphql_server2 validates each scalar return against its declared
  /// type and rejects mismatches. For most scalars the raw column
  /// value is fine, but two cases need conversion:
  ///
  ///   * `bigInteger` columns when [bigIntegerAsString] is true on the
  ///     SchemaBuilder — values arrive as `int` from the driver and
  ///     have to ship as `String`. We honour [stringifyBigInts] to
  ///     toggle this.
  ///   * `document` columns — these hold a `Document` Conduit object;
  ///     we surface them as JSON-encoded strings to match the
  ///     schema-derivation contract.
  ///
  /// Datetime values can stay native; the `DateTime` scalar's
  /// serializer turns them into ISO-8601 strings before they hit the
  /// wire.
  Object? _serializeAttributeValue(
    ManagedAttributeDescription attr,
    Object? value,
  ) {
    if (value == null) return null;
    final type = attr.type;
    if (type == null) return value;
    switch (type.kind) {
      case ManagedPropertyType.bigInteger:
        return stringifyBigInts ? value.toString() : value;
      case ManagedPropertyType.document:
        // Documents serialize as JSON strings per the G2 mapping.
        if (value is Document) return value.data;
        return value;
      case ManagedPropertyType.integer:
      case ManagedPropertyType.string:
      case ManagedPropertyType.boolean:
      case ManagedPropertyType.doublePrecision:
      case ManagedPropertyType.datetime:
      case ManagedPropertyType.list:
      case ManagedPropertyType.map:
        return value;
    }
  }

  /// When `true` (the default), `bigInteger` column values are
  /// stringified before being returned through resolvers — matching
  /// the `bigIntegerAsString: true` default on `SchemaBuilder`. Apps
  /// that pass `bigIntegerAsString: false` to the schema must also
  /// pass `stringifyBigInts: false` to the factory; otherwise the
  /// Int!-typed field will reject the String value.
  bool stringifyBigInts = true;

  // -- Internal helpers -------------------------------------------------------

  /// Reads the registry threaded through `args` by the controller.
  /// Returns null when no registry is configured (unit tests, or G2-
  /// style callers with no dataloader); resolvers that need batching
  /// fall back to per-call queries in that case.
  DataLoaderRegistry? _registryFromArgs(Map<String, dynamic> args) {
    final raw = args[dataLoaderRegistryArgKey];
    return raw is DataLoaderRegistry ? raw : null;
  }

  GraphQLFieldResolver<Object?, Object?> _belongsToResolver(
    ManagedRelationshipDescription rel,
  ) {
    final destEntity = rel.destinationEntity;
    final destPk = destEntity.primaryKeyAttribute!;

    return (Object? parent, Map<String, dynamic> args) async {
      // The parent ships as a ManagedObject from the list resolver. A
      // belongsTo relationship surfaces under `parent[rel.name]` as a
      // partial ManagedObject carrying just the FK; we read the
      // destination PK off it.
      final fkValue = _foreignKeyFromParent(parent, rel, destPk.name);
      if (fkValue == null) return null;

      final registry = _registryFromArgs(args);
      if (registry == null) {
        return _fetchByPk(destEntity, destPk, fkValue);
      }
      final loader = registry.getOrAdd<Object, ManagedObject>(
        _LoaderKey.belongsTo(rel),
        () => DataLoader<Object, ManagedObject>(
          (keys) => _batchFetchByPk(destEntity, destPk, keys),
        ),
      );
      return loader.load(fkValue);
    };
  }

  GraphQLFieldResolver<Object?, Object?> _hasManyResolver(
    ManagedRelationshipDescription rel,
  ) {
    final destEntity = rel.destinationEntity;
    final inverse = rel.inverse;
    if (inverse == null) {
      // Should be impossible for a well-formed Conduit data model; bail
      // loudly rather than emit silently empty lists.
      throw StateError(
        'Relationship ${rel.entity.name}.${rel.name} has no inverse on '
        '${destEntity.name}; cannot lower to SQL.',
      );
    }
    final parentPk = rel.entity.primaryKeyAttribute!;

    return (Object? parent, Map<String, dynamic> args) async {
      final parentPkValue = _readField(parent, parentPk.name);
      if (parentPkValue == null) return const <ManagedObject>[];

      final registry = _registryFromArgs(args);
      if (registry == null) {
        final grouped =
            await _fetchHasMany(destEntity, inverse, [parentPkValue]);
        return grouped[parentPkValue] ?? const <ManagedObject>[];
      }
      final loader = registry.getOrAdd<Object, List<ManagedObject>>(
        _LoaderKey.hasMany(rel),
        () => DataLoader<Object, List<ManagedObject>>(
          (keys) => _batchFetchHasMany(destEntity, inverse, keys),
        ),
      );
      final list = await loader.load(parentPkValue);
      return list ?? const <ManagedObject>[];
    };
  }

  GraphQLFieldResolver<Object?, Object?> _hasOneResolver(
    ManagedRelationshipDescription rel,
  ) {
    // hasOne shares the loader with hasMany — same SQL shape, same
    // batch semantics — but yields the first (and only) result.
    final inner = _hasManyResolver(rel);
    return (Object? parent, Map<String, dynamic> args) async {
      final list = await inner(parent, args);
      if (list is List && list.isNotEmpty) return list.first;
      return null;
    };
  }

  Future<ManagedObject?> _fetchByPk(
    ManagedEntity entity,
    ManagedAttributeDescription pk,
    Object value,
  ) async {
    final query = Query.forEntity(entity, context);
    _addEqualityPredicate(query, pk, value);
    return query.fetchOne();
  }

  Future<List<ManagedObject?>> _batchFetchByPk(
    ManagedEntity entity,
    ManagedAttributeDescription pk,
    List<Object> keys,
  ) async {
    final query = Query.forEntity(entity, context);
    _addOneOfPredicate(query, pk, keys);
    final rows = await query.fetch();
    final byKey = <Object, ManagedObject>{};
    for (final row in rows) {
      final pkValue = row[pk.name];
      if (pkValue != null) byKey[pkValue as Object] = row;
    }
    // Preserve key order; null for any missing key (DataLoader contract).
    return [for (final k in keys) byKey[k]];
  }

  Future<Map<Object, List<ManagedObject>>> _fetchHasMany(
    ManagedEntity destEntity,
    ManagedRelationshipDescription inverse,
    List<Object> parentKeys,
  ) async {
    if (parentKeys.isEmpty) return const {};
    final query = Query.forEntity(destEntity, context);
    // The inverse is a belongsTo on the destination entity. Filtering
    // on `inverse.destinationEntity.primaryKey` through the inverse's
    // FK column is the SQL equivalent of `WHERE author_id IN (...)`.
    final pkAttr = inverse.destinationEntity.primaryKeyAttribute!;
    _addBelongsToOneOfPredicate(query, inverse, pkAttr, parentKeys);

    final rows = await query.fetch();
    final out = <Object, List<ManagedObject>>{};
    for (final row in rows) {
      // The FK lands on the row as a partial ManagedObject under
      // `inverse.name`, carrying just the destination's PK column.
      final fkContainer = row[inverse.name];
      Object? fkValue;
      if (fkContainer is ManagedObject) {
        fkValue = fkContainer[pkAttr.name];
      } else if (fkContainer is Map) {
        fkValue = fkContainer[pkAttr.name];
      } else {
        fkValue = fkContainer;
      }
      if (fkValue == null) continue;
      (out[fkValue] ??= []).add(row);
    }
    return out;
  }

  Future<List<List<ManagedObject>?>> _batchFetchHasMany(
    ManagedEntity destEntity,
    ManagedRelationshipDescription inverse,
    List<Object> parentKeys,
  ) async {
    final grouped = await _fetchHasMany(destEntity, inverse, parentKeys);
    return [for (final k in parentKeys) grouped[k] ?? const <ManagedObject>[]];
  }

  // -- Argument lowering ------------------------------------------------------

  /// Public test seam: lowers the GraphQL list-arg map [args] into
  /// state on [query]. The list resolver does this internally before
  /// `fetch()`; exposing it lets unit tests assert lowering shape
  /// without spinning up a real database.
  ///
  /// The state shape touched is:
  ///   * `where:` -> appended `QueryExpression`s on
  ///     `(query as QueryMixin).expressions`.
  ///   * `orderBy:` -> appended `QuerySortDescriptor`s on
  ///     `(query as QueryMixin).sortDescriptors`.
  ///   * `limit:` / `offset:` -> set on `Query.fetchLimit` / `Query.offset`.
  void applyListArgs(
    Query query,
    ManagedEntity entity,
    Map<String, dynamic> args,
  ) =>
      _applyListArgs(query, entity, args);

  void _applyListArgs(
    Query query,
    ManagedEntity entity,
    Map<String, dynamic> args,
  ) {
    final whereArg = args['where'];
    if (whereArg is Map) {
      _applyWhere(query, entity, whereArg);
    }

    final orderArg = args['orderBy'];
    if (orderArg is List) {
      for (final entry in orderArg) {
        if (entry is! Map) continue;
        _applySortEntry(query, entity, entry);
      }
    }

    final limitArg = args['limit'];
    if (limitArg is int && limitArg > 0) {
      query.fetchLimit = limitArg;
    }

    final offsetArg = args['offset'];
    if (offsetArg is int && offsetArg > 0) {
      query.offset = offsetArg;
    }
  }

  void _applyWhere(
    Query query,
    ManagedEntity entity,
    Map<dynamic, dynamic> whereArg,
  ) {
    whereArg.forEach((rawKey, rawPredicate) {
      if (rawKey is! String || rawPredicate is! Map) return;
      final attr = entity.attributes[rawKey];
      if (attr == null) return; // unknown field; ignored defensively
      _applyPredicateMap(query, attr, rawPredicate);
    });
  }

  void _applyPredicateMap(
    Query query,
    ManagedAttributeDescription attr,
    Map<dynamic, dynamic> predicate,
  ) {
    predicate.forEach((rawOp, rawValue) {
      if (rawOp is! String) return;
      _addOpPredicate(query, attr, rawOp, rawValue);
    });
  }

  void _addOpPredicate(
    Query query,
    ManagedAttributeDescription attr,
    String op,
    Object? rawValue,
  ) {
    // We construct a fresh QueryExpression keyed on the attribute and
    // populate its `expression` field by routing through a temporary
    // expression we discard. Going through QueryMixin's `expressions`
    // list directly is cleaner than trying to type-erase a property
    // closure for `Query.where`.
    final mixin = query as QueryMixin;
    Object? coerced;
    if (rawValue is List) {
      coerced = rawValue.map((v) => _coerceScalar(attr, v)).toList();
    } else {
      coerced = _coerceScalar(attr, rawValue);
    }

    switch (op) {
      case 'eq':
        if (coerced == null) return;
        _addEqualityPredicateOnMixin(mixin, attr, coerced);
        break;
      case 'ne':
        if (coerced == null) return;
        _addPredicateOnMixin(
          mixin,
          attr,
          ComparisonExpression(coerced, PredicateOperator.notEqual),
        );
        break;
      case 'gt':
        if (coerced == null) return;
        _addPredicateOnMixin(
          mixin,
          attr,
          ComparisonExpression(coerced, PredicateOperator.greaterThan),
        );
        break;
      case 'gte':
        if (coerced == null) return;
        _addPredicateOnMixin(
          mixin,
          attr,
          ComparisonExpression(coerced, PredicateOperator.greaterThanEqualTo),
        );
        break;
      case 'lt':
        if (coerced == null) return;
        _addPredicateOnMixin(
          mixin,
          attr,
          ComparisonExpression(coerced, PredicateOperator.lessThan),
        );
        break;
      case 'lte':
        if (coerced == null) return;
        _addPredicateOnMixin(
          mixin,
          attr,
          ComparisonExpression(coerced, PredicateOperator.lessThanEqualTo),
        );
        break;
      case 'in':
        if (coerced is! List || coerced.isEmpty) return;
        _addPredicateOnMixin(mixin, attr, SetMembershipExpression(coerced));
        break;
      case 'notIn':
        if (coerced is! List || coerced.isEmpty) return;
        _addPredicateOnMixin(
          mixin,
          attr,
          SetMembershipExpression(coerced, within: false),
        );
        break;
      case 'like':
        if (coerced is! String) return;
        _addPredicateOnMixin(
          mixin,
          attr,
          StringExpression(
            coerced,
            PredicateStringOperator.contains,
            allowSpecialCharacters: false,
          ),
        );
        break;
      case 'isNull':
        if (rawValue is! bool) return;
        _addPredicateOnMixin(
          mixin,
          attr,
          NullCheckExpression(shouldBeNull: rawValue),
        );
        break;
      default:
        // Unknown predicate keys are ignored. Schema-level enforcement
        // (input-object validation) catches misnamed predicates well
        // before we get here, so this path is defensive only.
        return;
    }
  }

  void _addEqualityPredicate(
    Query query,
    ManagedAttributeDescription attr,
    Object value,
  ) {
    _addEqualityPredicateOnMixin(query as QueryMixin, attr, value);
  }

  void _addEqualityPredicateOnMixin(
    QueryMixin mixin,
    ManagedAttributeDescription attr,
    Object value,
  ) {
    if (value is String) {
      _addPredicateOnMixin(
        mixin,
        attr,
        StringExpression(
          value,
          PredicateStringOperator.equals,
          allowSpecialCharacters: false,
        ),
      );
    } else {
      _addPredicateOnMixin(
        mixin,
        attr,
        ComparisonExpression(value, PredicateOperator.equalTo),
      );
    }
  }

  void _addOneOfPredicate(
    Query query,
    ManagedAttributeDescription attr,
    List<Object> values,
  ) {
    _addPredicateOnMixin(
      query as QueryMixin,
      attr,
      SetMembershipExpression(values),
    );
  }

  void _addBelongsToOneOfPredicate(
    Query query,
    ManagedRelationshipDescription rel,
    ManagedAttributeDescription destPk,
    List<Object> values,
  ) {
    final mixin = query as QueryMixin;
    // For a belongsTo column, predicate keypath is `[rel, destPk]` —
    // i.e. we're filtering by the destination's PK through the FK
    // column. Conduit's PostgresQuery builder handles this two-element
    // keypath as a foreign-key predicate (table.dart:175).
    final expr = QueryExpression<dynamic, dynamic>(KeyPath(rel))
      ..keyPath.add(destPk);
    expr.expression = SetMembershipExpression(values);
    mixin.expressions.add(expr);
  }

  void _addPredicateOnMixin(
    QueryMixin mixin,
    ManagedAttributeDescription attr,
    PredicateExpression expression,
  ) {
    final expr = QueryExpression<dynamic, dynamic>(KeyPath(attr))
      ..expression = expression;
    mixin.expressions.add(expr);
  }

  void _applySortEntry(
    Query query,
    ManagedEntity entity,
    Map<dynamic, dynamic> entry,
  ) {
    final rawField = entry['field'];
    final rawDir = entry['direction'];
    if (rawField is! String) return;
    final attr = entity.attributes[rawField];
    if (attr == null) return;
    final order = rawDir == 'DESC'
        ? QuerySortOrder.descending
        : QuerySortOrder.ascending;
    final mixin = query as QueryMixin;
    mixin.sortDescriptors.add(QuerySortDescriptor(attr.name, order));
  }

  // -- Coercion ---------------------------------------------------------------

  /// Coerces a JSON-decoded scalar [raw] to the Dart type the Conduit
  /// matcher layer expects for [attr]. Strings round-trip; integers
  /// reach us as `int` already; bigInteger lands as a String (because
  /// our scalar mapping is `String!` for big ints) and we parse it back
  /// to int here so the matcher gets a numeric value.
  Object? _coerceScalar(ManagedAttributeDescription attr, Object? raw) {
    if (raw == null) return null;
    final type = attr.type;
    if (type == null) return raw;
    switch (type.kind) {
      case ManagedPropertyType.bigInteger:
        if (raw is int) return raw;
        if (raw is String) return int.tryParse(raw) ?? raw;
        return raw;
      case ManagedPropertyType.integer:
        if (raw is int) return raw;
        if (raw is String) return int.tryParse(raw) ?? raw;
        return raw;
      case ManagedPropertyType.doublePrecision:
        if (raw is num) return raw.toDouble();
        if (raw is String) return double.tryParse(raw) ?? raw;
        return raw;
      case ManagedPropertyType.datetime:
        if (raw is DateTime) return raw;
        if (raw is String) return DateTime.tryParse(raw) ?? raw;
        return raw;
      case ManagedPropertyType.boolean:
      case ManagedPropertyType.string:
      case ManagedPropertyType.document:
      case ManagedPropertyType.list:
      case ManagedPropertyType.map:
        return raw;
    }
  }

  // -- Result shaping ---------------------------------------------------------

  /// Reads [fieldName] off [parent], handling both Map and
  /// ManagedObject parent shapes. List resolvers return ManagedObject
  /// instances (so the executor falls through to attribute resolvers
  /// instead of taking its Map-fast-path), but legacy callers that
  /// hand-roll a Map-parent path still work.
  Object? _readField(Object? parent, String fieldName) {
    if (parent is ManagedObject) {
      return parent.backing.contents.containsKey(fieldName)
          ? parent[fieldName]
          : null;
    }
    if (parent is Map) return parent[fieldName];
    return null;
  }

  Object? _foreignKeyFromParent(
    Object? parent,
    ManagedRelationshipDescription rel,
    String destPkName,
  ) {
    final raw = _readField(parent, rel.name);
    if (raw is ManagedObject) return raw[destPkName];
    if (raw is Map) return raw[destPkName];
    return raw;
  }
}

/// Stable cache key for relationship loaders. Equality is by relationship
/// identity — we want every resolver invocation that targets the same
/// `Post.author` field to hit the same loader within a request.
class _LoaderKey {
  const _LoaderKey._(this._kind, this._rel);

  factory _LoaderKey.belongsTo(ManagedRelationshipDescription rel) =>
      _LoaderKey._('belongsTo', rel);

  factory _LoaderKey.hasMany(ManagedRelationshipDescription rel) =>
      _LoaderKey._('hasMany', rel);

  final String _kind;
  final ManagedRelationshipDescription _rel;

  @override
  bool operator ==(Object other) =>
      other is _LoaderKey && other._kind == _kind && identical(other._rel, _rel);

  @override
  int get hashCode => Object.hash(_kind, identityHashCode(_rel));
}
