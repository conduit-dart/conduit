import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_graph/conduit_graph.dart';
import 'package:graphql_schema2/graphql_schema2.dart';

import '../auth/field_authorize.dart';
import '../resolvers/graph_resolver_factory.dart';
import '../resolvers/persistence_resolver_factory.dart';
import 'graph_schema_config.dart';
import 'query_root_collision_policy.dart';
import 'scalars.dart';

/// Derives a [GraphQLSchema] from a Conduit [ManagedDataModel].
///
/// Walks every [ManagedEntity] in the model, mirroring the deferred-ref
/// pattern used by Conduit's existing OpenAPI emitter
/// (`packages/common/lib/src/openapi/`):
///
/// 1. Iterate every [ManagedEntity] and register a *deferred*
///    [GraphQLObjectType] token per entity. These tokens are created
///    with empty field lists at this point — only the name is stable.
/// 2. Walk each entity again. For every attribute, push a scalar field
///    onto the entity's registered object type. For every relationship,
///    push a reference to the *destination* entity's already-registered
///    object type (or a list of it for hasMany). This second pass is
///    what makes circular references safe: every type a relationship
///    might reference is already in the registry.
/// 3. Construct the root `Query` type with two fields per entity: a
///    list-all (`<plural>: [<Entity>!]!`) and a by-primary-key
///    (`<singular>(<pkField>: <pkType>!): <Entity>`). Both have
///    `null`-resolvers in G2; the resolver framework lands in G3.
///
/// G2 emits a *read-only* schema. There are no mutation/input types,
/// no filter/sort/pagination arguments, and no resolvers — those land
/// in G3+. Schema introspection works fully today.
///
/// ### Reuse pattern
///
/// The deferred-ref-via-registry approach mirrors
/// `APIComponentCollection<T>` from `packages/common`. Both walk the
/// data model twice (once to *promise* a type, once to *resolve* its
/// shape) so that circular references — `User.posts: [Post]`,
/// `Post.author: User` — naturally fall out without explicit
/// topological sorting.
///
/// ### Resolver hook seam (for G3)
///
/// The schema this class emits has `resolve: null` on every field.
/// G3's resolver framework will need to attach closures to:
///
/// * each entity-type field (`User.posts`, `Post.author`, ...) — these
///   become `Query<T>` joins or relation hydration;
/// * each Query-root field (`users`, `user(id:)`, ...) — these become
///   top-level `Query<T>` executors that produce the initial result
///   set.
///
/// Because graphql_schema2's `GraphQLObjectField` is constructed
/// once-and-immutable (no setter for `resolve`), G3 will need to *copy*
/// each field with a resolver attached, or [SchemaBuilder] will need
/// to grow a callback parameter that runs at field-creation time. The
/// latter is the planned approach; see the `resolver_hook` notes in
/// `_objectTypeForInternal`.
/// Callback type produced by [SqlResolverFactory] for entity-list and
/// by-pk fields, and threaded into [SchemaBuilder] via
/// `queryListResolver` / `queryByPkResolver`. Kept here (and not in
/// `resolvers/`) to avoid forcing a `resolvers/` import on the type
/// surface for callers who only want the factory's output type.
typedef SchemaResolver = GraphQLFieldResolver<Object?, Object?>;

class SchemaBuilder {
  /// Constructs a builder with optional overrides for the custom
  /// scalars used during emission and optional resolver / argument
  /// hooks for G3+.
  ///
  /// All of the resolver hook parameters default to `null`. When all
  /// four are null, [SchemaBuilder] behaves identically to its G2
  /// shape (every emitted field has `resolve: null`). G3 and beyond
  /// pass non-null hooks to wire in `Query<T>` / `GraphQuery<N>`
  /// execution; G5 will compose its own hooks on top of these.
  ///
  /// The argument-generation flags are also opt-in. When all three
  /// are false, the emitted Query root has G2-shape — list-all takes
  /// no arguments. Flipping any of them on grows the schema with a
  /// new generated type per entity (a `<Entity>Filter` input, a
  /// `<Entity>SortInput`, etc.).
  SchemaBuilder({
    GraphQLScalarType<DateTime, String>? dateTimeScalar,
    GraphQLScalarType<String, String>? uuidScalar,
    this.bigIntegerAsString = true,
    this.attributeResolver,
    this.relationshipResolver,
    this.queryListResolver,
    this.queryByPkResolver,
    this.generateFilterArgs = false,
    this.generateSortArgs = false,
    this.generatePaginationArgs = false,
  })  : dateTimeScalar = dateTimeScalar ?? graphQLDateTime,
        uuidScalar = uuidScalar ?? graphQLUUID;

  /// Scalar used for `ManagedPropertyType.datetime` properties.
  /// Defaults to [graphQLDateTime].
  final GraphQLScalarType<DateTime, String> dateTimeScalar;

  /// Scalar used for properties marked as UUIDs. Currently this only
  /// matters when the user supplies a UUID-typed `String` column via a
  /// custom annotation; the default scalar mapping treats any
  /// non-UUID-tagged string as `GraphQLString`. The slot exists so
  /// future phases can light it up without breaking the API.
  final GraphQLScalarType<String, String> uuidScalar;

  /// When `true` (the default), `ManagedPropertyType.bigInteger` lowers
  /// to `GraphQLString` rather than `GraphQLInt`, because GraphQL's
  /// `Int` scalar is a signed 32-bit integer and Conduit big-integers
  /// can carry 64-bit values that overflow it. Set to `false` to lower
  /// big-ints to `Int` if the deployment guarantees 32-bit-safe
  /// values.
  final bool bigIntegerAsString;

  /// Optional resolver hook invoked at attribute-field construction
  /// time. Returns `null` to leave the field's `resolve:` slot empty
  /// (the executor's default Map-lookup path applies).
  ///
  /// The hook runs once per attribute per emission, so closures
  /// captured into the returned resolver should be stable across
  /// requests (the resolver itself is invoked per request).
  final SchemaResolver? Function(ManagedAttributeDescription attr)?
      attributeResolver;

  /// Optional resolver hook invoked at relationship-field construction
  /// time. Returns `null` to leave the field's `resolve:` slot empty.
  final SchemaResolver? Function(ManagedRelationshipDescription rel)?
      relationshipResolver;

  /// Optional resolver hook invoked at Query-root list-field
  /// construction time (i.e. for `<plural>: [<Entity>!]!`).
  final SchemaResolver? Function(ManagedEntity entity)? queryListResolver;

  /// Optional resolver hook invoked at Query-root by-pk-field
  /// construction time (i.e. for `<singular>(<pk>: <pkType>!)`).
  final SchemaResolver? Function(ManagedEntity entity)? queryByPkResolver;

  /// When `true`, list-all Query-root fields gain a `where:` argument
  /// of a generated `<Entity>Filter` input type. Each filterable
  /// attribute becomes a field on that input, accepting one of
  /// `eq:/ne:/gt:/gte:/lt:/lte:/in:/notIn:/like:/isNull:` per
  /// scalar predicate input (lowering documented in
  /// `SqlResolverFactory`).
  final bool generateFilterArgs;

  /// When `true`, list-all Query-root fields gain an
  /// `orderBy: [<Entity>SortInput!]` argument. The sort input carries
  /// a `field:` enum (one entry per attribute) and a `direction:`
  /// (`ASC | DESC`).
  final bool generateSortArgs;

  /// When `true`, list-all Query-root fields gain `limit: Int` and
  /// `offset: Int` arguments. The resolver lowers them to
  /// `Query.fetchLimit` / `Query.offset`.
  final bool generatePaginationArgs;

  /// Derives a [GraphQLSchema] from [model].
  ///
  /// See class-level docs for the algorithm.
  GraphQLSchema fromManagedDataModel(ManagedDataModel model) {
    final entities = model.entities.toList();
    if (entities.isEmpty) {
      throw ArgumentError(
        'SchemaBuilder.fromManagedDataModel requires at least one '
        'ManagedEntity in the model, but the model is empty.',
      );
    }

    // First pass: register a deferred object-type token per entity.
    // Fields are populated in the second pass, after every type the
    // relationship resolver might need is known to the registry.
    final registry = <ManagedEntity, GraphQLObjectType>{};
    for (final entity in entities) {
      registry[entity] = GraphQLObjectType(entity.name, _entityDescription(entity));
    }

    // Second pass: populate fields for each registered type.
    for (final entity in entities) {
      _populateFields(entity, registry);
    }

    // Build the Query root from the populated registry.
    final queryRoot = _buildQueryRoot(entities, registry);

    return GraphQLSchema(queryType: queryRoot);
  }

  /// Derives a `GraphQLObjectType` for a single [entity], independent
  /// of any data-model-wide registry.
  ///
  /// This convenience wrapper builds a single-entity registry and runs
  /// both passes against it. Relationships pointing *out* of [entity]
  /// will reference newly-fabricated empty types (one per destination
  /// entity), which is fine for one-off type-shape inspection but is
  /// NOT what you want when emitting a full schema — use
  /// [fromManagedDataModel] for that.
  GraphQLObjectType objectTypeFor(ManagedEntity entity) {
    final registry = <ManagedEntity, GraphQLObjectType>{
      entity: GraphQLObjectType(entity.name, _entityDescription(entity)),
    };
    // Pre-register destination entities so relationship fields have a
    // reference to point at. We don't recurse — the destinations come
    // back as empty stubs.
    for (final rel in entity.relationships.values.whereType<ManagedRelationshipDescription>()) {
      registry.putIfAbsent(
        rel.destinationEntity,
        () => GraphQLObjectType(
          rel.destinationEntity.name,
          _entityDescription(rel.destinationEntity),
        ),
      );
    }
    _populateFields(entity, registry);
    return registry[entity]!;
  }

  // -- Internals -------------------------------------------------------------

  String _entityDescription(ManagedEntity entity) =>
      'GraphQL projection of Conduit entity ${entity.name} '
      '(table ${entity.tableName}).';

  /// Populates the fields of [entity]'s already-registered object type.
  void _populateFields(
    ManagedEntity entity,
    Map<ManagedEntity, GraphQLObjectType> registry,
  ) {
    final type = registry[entity]!;

    // Attributes — scalar columns + transient props.
    for (final attr in entity.attributes.values.whereType<ManagedAttributeDescription>()) {
      // Skip transient attributes that are input-only — they aren't
      // observable on the output side of the entity, so they shouldn't
      // appear in the GraphQL output schema.
      if (attr.isTransient && !attr.transientStatus!.isAvailableAsOutput) {
        continue;
      }
      final f = _fieldForAttribute(attr);
      if (f != null) type.fields.add(f);
    }

    // Relationships — both directions (hasMany / hasOne / belongsTo).
    for (final rel in entity.relationships.values.whereType<ManagedRelationshipDescription>()) {
      final f = _fieldForRelationship(rel, registry);
      if (f != null) type.fields.add(f);
    }
  }

  /// Maps a [ManagedAttributeDescription] to a `GraphQLObjectField`.
  /// Returns `null` if the attribute can't be represented (currently
  /// never — every type has a fallback).
  GraphQLObjectField? _fieldForAttribute(ManagedAttributeDescription attr) {
    final scalar = _scalarFor(attr);
    final wrapped = _applyAttributeNullability(scalar, attr);
    final resolver = attributeResolver?.call(attr);
    return GraphQLObjectField(
      attr.name,
      wrapped,
      // resolver_hook: G3 attaches a closure here that pulls
      // `attr.name` off the resolved parent value. v1's
      // `attributeResolverFor` always returns null because the
      // executor's default Map-parent shortcut already does the right
      // thing for every scalar kind; the slot stays open for G5+.
      resolve: resolver,
    );
  }

  /// Maps a [ManagedRelationshipDescription] to a `GraphQLObjectField`
  /// pointing at the registered destination object type.
  GraphQLObjectField? _fieldForRelationship(
    ManagedRelationshipDescription rel,
    Map<ManagedEntity, GraphQLObjectType> registry,
  ) {
    final destType = registry[rel.destinationEntity];
    if (destType == null) {
      // The destination entity wasn't part of the model passed in.
      // Skip the field rather than emit a broken reference — this
      // mirrors the OpenAPI emitter's behavior.
      return null;
    }
    final wrapped = _applyRelationshipNullability(destType, rel);
    final resolver = relationshipResolver?.call(rel);
    return GraphQLObjectField(
      rel.name,
      wrapped,
      // resolver_hook: G3 attaches a join/load resolver here. For
      // belongsTo this becomes a `Query<DestinationEntity>` filtered by
      // the foreign key; for hasOne / hasMany it becomes a
      // back-reference query against `inverseKey`.
      resolve: resolver,
    );
  }

  /// Lowers a [ManagedAttributeDescription] to a base scalar GraphQL
  /// type (no nullable / list wrappers applied).
  GraphQLType<dynamic, dynamic> _scalarFor(ManagedAttributeDescription attr) {
    final type = attr.type;
    if (type == null) {
      // Transient props with no resolved type — fall back to String.
      return graphQLString;
    }

    // Enums are stored as strings under the hood. Surfacing them as
    // GraphQL Enum types is a future enhancement; for v1 we leave
    // them as strings to keep the SDL deterministic.
    if (type.isEnumerated) {
      return graphQLString;
    }

    switch (type.kind) {
      case ManagedPropertyType.integer:
        return graphQLInt;
      case ManagedPropertyType.bigInteger:
        return bigIntegerAsString ? graphQLString : graphQLInt;
      case ManagedPropertyType.string:
        return graphQLString;
      case ManagedPropertyType.datetime:
        return dateTimeScalar;
      case ManagedPropertyType.boolean:
        return graphQLBoolean;
      case ManagedPropertyType.doublePrecision:
        return graphQLFloat;
      case ManagedPropertyType.document:
        // Documents are JSON-encoded into a string for v1. See README
        // "G2 schema-derivation limitations".
        return graphQLString;
      case ManagedPropertyType.list:
        final inner = _scalarForElement(type.elements);
        return GraphQLListType(inner.nonNullable());
      case ManagedPropertyType.map:
        // GraphQL has no native Map type. Serialize to JSON string for
        // v1; see README known-limitations.
        return graphQLString;
    }
  }

  /// Recursive helper for nested list/element scalars.
  GraphQLType<dynamic, dynamic> _scalarForElement(ManagedType? element) {
    if (element == null) return graphQLString;
    if (element.isEnumerated) return graphQLString;
    switch (element.kind) {
      case ManagedPropertyType.integer:
        return graphQLInt;
      case ManagedPropertyType.bigInteger:
        return bigIntegerAsString ? graphQLString : graphQLInt;
      case ManagedPropertyType.string:
        return graphQLString;
      case ManagedPropertyType.datetime:
        return dateTimeScalar;
      case ManagedPropertyType.boolean:
        return graphQLBoolean;
      case ManagedPropertyType.doublePrecision:
        return graphQLFloat;
      case ManagedPropertyType.document:
      case ManagedPropertyType.list:
      case ManagedPropertyType.map:
        return graphQLString;
    }
  }

  /// Wraps [scalar] in a [GraphQLNonNullableType] if [attr]'s shape
  /// guarantees the column is always populated.
  ///
  /// The rule: an attribute is non-null in GraphQL iff it is *not*
  /// nullable on the Conduit side AND has no default value. Primary
  /// keys are always non-null. Transient attributes are always nullable
  /// in v1 (we have no way to know without running the getter).
  GraphQLType<dynamic, dynamic> _applyAttributeNullability(
    GraphQLType<dynamic, dynamic> scalar,
    ManagedAttributeDescription attr,
  ) {
    if (attr.isPrimaryKey) {
      return scalar.nonNullable();
    }
    if (attr.isTransient) {
      // Output-side transient props are computed at request time and
      // can be null at the discretion of the getter. Stay nullable.
      return scalar;
    }
    if (!attr.isNullable && attr.defaultValue == null) {
      return scalar.nonNullable();
    }
    return scalar;
  }

  /// Decides the GraphQL nullability of a relationship field per the
  /// Conduit relationship type:
  ///
  /// * `belongsTo` — nullable iff the FK is nullable. (Conduit's
  ///   property builder lowers `Relate(isRequired: true)` to
  ///   `isNullable = false`.)
  /// * `hasOne` — always nullable. The other side may simply not
  ///   exist; Conduit can't guarantee it.
  /// * `hasMany` — non-null `[Type!]!`. Lists are guaranteed to be
  ///   present (possibly empty) but never null; their elements are
  ///   guaranteed non-null because a list of relationship rows can't
  ///   contain a null entity.
  GraphQLType<dynamic, dynamic> _applyRelationshipNullability(
    GraphQLObjectType destType,
    ManagedRelationshipDescription rel,
  ) {
    switch (rel.relationshipType) {
      case ManagedRelationshipType.belongsTo:
        if (!rel.isNullable) {
          return destType.nonNullable();
        }
        return destType;
      case ManagedRelationshipType.hasOne:
        return destType;
      case ManagedRelationshipType.hasMany:
        return GraphQLListType(destType.nonNullable()).nonNullable();
    }
  }

  /// Constructs the root `Query` type. For each entity, two fields:
  ///
  /// * `<plural>: [<Entity>!]!` — list-all.
  /// * `<singular>(<pk>: <pkType>!): <Entity>` — find-by-primary-key.
  ///
  /// Pluralization is naive: the singular field name is the entity
  /// name in lowercase-first form (`User` -> `user`); the plural is
  /// that name with an `s` suffix (`user` -> `users`). Real apps may
  /// want a future `@SchemaName('users')`-style override.
  GraphQLObjectType _buildQueryRoot(
    List<ManagedEntity> entities,
    Map<ManagedEntity, GraphQLObjectType> registry,
  ) {
    // Field names from entity names. We dedupe defensively in case two
    // entities collide on the lowercase form (unlikely under Conduit's
    // existing entity-uniqueness rules but cheap to guard).
    final fields = <GraphQLObjectField>[];
    final seen = <String>{};

    for (final entity in entities) {
      final type = registry[entity]!;
      final singular = _singularFieldName(entity);
      final plural = _pluralFieldName(singular);

      if (!seen.add(singular)) {
        // Duplicate singular — skip by-pk emission rather than crash.
        continue;
      }
      if (!seen.add(plural)) {
        continue;
      }

      // List-all: `<plural>: [<Entity>!]!`
      final listResolver = queryListResolver?.call(entity);
      final listArgs = _buildListArgsFor(entity);
      fields.add(
        GraphQLObjectField(
          plural,
          GraphQLListType(type.nonNullable()).nonNullable(),
          // resolver_hook: G3 attaches a `Query<T>.fetch()` here. The
          // `conduitRequest` global will provide the auth context.
          resolve: listResolver,
          arguments: listArgs,
          description:
              'Returns every ${entity.name}. Filtering, sorting, and '
              'pagination args are emitted when the SchemaBuilder is '
              'constructed with the matching generate*Args flag.',
        ),
      );

      // By-pk: `<singular>(<pk>: <pkType>!): <Entity>`
      final pkAttr = entity.primaryKeyAttribute;
      if (pkAttr != null) {
        final pkScalar = _scalarFor(pkAttr);
        final byPkResolver = queryByPkResolver?.call(entity);
        fields.add(
          GraphQLObjectField(
            singular,
            type,
            // resolver_hook: G3 attaches a `Query<T>.where(...).fetchOne()`.
            resolve: byPkResolver,
            arguments: [
              GraphQLFieldInput(
                pkAttr.name,
                pkScalar.nonNullable(),
                description:
                    'Primary key of the ${entity.name} to fetch.',
              ),
            ],
            description:
                'Returns the ${entity.name} with the given '
                '${pkAttr.name}, or null if none exists.',
          ),
        );
      }
    }

    return GraphQLObjectType(
      'Query',
      'Read-only Conduit GraphQL query root, derived from a '
          'ManagedDataModel.',
    )..fields.addAll(fields);
  }

  /// Lowercase-first form of [entity.name].
  String _singularFieldName(ManagedEntity entity) {
    final raw = entity.name;
    if (raw.isEmpty) return raw;
    return raw.substring(0, 1).toLowerCase() + raw.substring(1);
  }

  /// Naive pluralization: append `s`, with two narrow special cases
  /// for common terminations that the bare suffix would mangle. Full
  /// inflection is out of scope; users can override via the planned
  /// `@SchemaName` annotation in a later phase.
  String _pluralFieldName(String singular) {
    if (singular.isEmpty) return 's';
    final lower = singular.toLowerCase();
    // Words ending in 's', 'x', 'z', 'sh', 'ch' take 'es'.
    if (lower.endsWith('s') ||
        lower.endsWith('x') ||
        lower.endsWith('z') ||
        lower.endsWith('sh') ||
        lower.endsWith('ch')) {
      return '${singular}es';
    }
    // Words ending in consonant + 'y' take 'ies'.
    if (lower.endsWith('y') && singular.length >= 2) {
      final prev = singular[singular.length - 2].toLowerCase();
      const vowels = {'a', 'e', 'i', 'o', 'u'};
      if (!vowels.contains(prev)) {
        return '${singular.substring(0, singular.length - 1)}ies';
      }
    }
    return '${singular}s';
  }


  // -- G3: filter / sort / pagination args ------------------------------------

  /// Cache of scalar-keyed predicate input types. Each base scalar
  /// (`Int`, `String`, `Boolean`, `Float`, `DateTime`) gets exactly
  /// one `<Scalar>Predicate` input — they're reused across every
  /// field that filters on that scalar.
  ///
  /// Keyed by *type* identity rather than name to dodge the case where
  /// two custom scalars share a name (the SDL printer would already
  /// reject that, but the cache shouldn't depend on the printer's
  /// rejection path).
  final Map<GraphQLType<dynamic, dynamic>, GraphQLInputObjectType>
      _predicateInputCache = {};

  /// Cache of `<Entity>Filter` input types, keyed by entity. Each
  /// entity gets at most one filter type per builder invocation.
  final Map<ManagedEntity, GraphQLInputObjectType> _filterInputCache = {};

  /// Cache of `<Entity>SortInput` input types.
  final Map<ManagedEntity, GraphQLInputObjectType> _sortInputCache = {};

  /// Cache of `<Entity>SortField` enum types.
  final Map<ManagedEntity, GraphQLEnumType<String>> _sortFieldEnumCache = {};

  /// Shared `SortDirection` enum across all entities.
  GraphQLEnumType<String>? _sortDirectionEnum;

  /// Returns the list of `GraphQLFieldInput`s to attach to [entity]'s
  /// list-all Query-root field, gated by the [generateFilterArgs] /
  /// [generateSortArgs] / [generatePaginationArgs] flags.
  List<GraphQLFieldInput> _buildListArgsFor(ManagedEntity entity) {
    final args = <GraphQLFieldInput>[];

    if (generateFilterArgs) {
      final filter = _filterInputFor(entity);
      if (filter != null) {
        args.add(
          GraphQLFieldInput(
            'where',
            filter,
            description: 'Conjunctive filter over ${entity.name} rows.',
          ),
        );
      }
    }

    if (generateSortArgs) {
      final sort = _sortInputFor(entity);
      if (sort != null) {
        args.add(
          GraphQLFieldInput(
            'orderBy',
            GraphQLListType(sort.nonNullable()),
            description: 'Sort precedence list — first entry is primary.',
          ),
        );
      }
    }

    if (generatePaginationArgs) {
      args.add(
        GraphQLFieldInput(
          'limit',
          graphQLInt,
          description: 'Maximum number of rows to return. 0 / unset = no '
              'limit.',
        ),
      );
      args.add(
        GraphQLFieldInput(
          'offset',
          graphQLInt,
          description: 'Number of rows to skip from the start of the '
              'sorted result set.',
        ),
      );
    }

    return args;
  }

  /// Builds (and caches) `<Entity>Filter` — an input object with one
  /// field per filterable attribute. Returns null if the entity has
  /// no filterable attributes (which would produce an empty input,
  /// which graphql_schema2 doesn't support).
  GraphQLInputObjectType? _filterInputFor(ManagedEntity entity) {
    final cached = _filterInputCache[entity];
    if (cached != null) return cached;

    final fields = <GraphQLInputObjectField>[];
    for (final attr in entity.attributes.values
        .whereType<ManagedAttributeDescription>()) {
      // Transient attributes can't be filtered (they don't map to a
      // column). Filtering on them requires evaluating the getter,
      // which the SQL backend can't do.
      if (attr.isTransient) continue;
      final pred = _predicateInputForAttribute(attr);
      if (pred == null) continue;
      fields.add(
        GraphQLInputObjectField<Map<String, dynamic>, Map<String, dynamic>>(
          attr.name,
          pred,
          description: 'Predicate over ${entity.name}.${attr.name}.',
        ),
      );
    }

    if (fields.isEmpty) return null;

    final input = GraphQLInputObjectType(
      '${entity.name}Filter',
      description: 'Filter input for ${entity.name} list queries. Multiple '
          'fields AND together. Each field accepts a scalar predicate '
          '(eq, ne, gt, gte, lt, lte, in, notIn, like — string only — '
          'isNull).',
      inputFields: fields,
    );
    _filterInputCache[entity] = input;
    return input;
  }

  /// Returns the `<Scalar>Predicate` input for [attr]'s scalar type,
  /// or null if the attribute's lowered scalar isn't filterable
  /// (lists / maps / documents fall into this bucket).
  GraphQLInputObjectType? _predicateInputForAttribute(
    ManagedAttributeDescription attr,
  ) {
    final scalar = _scalarFor(attr);
    return _predicateInputForScalar(scalar);
  }

  /// Returns the cached `<Scalar>Predicate` input, or builds it on
  /// first ask. List/Map types return null — the SQL matcher layer has
  /// no operator surface for them.
  GraphQLInputObjectType? _predicateInputForScalar(
    GraphQLType<dynamic, dynamic> scalar,
  ) {
    if (scalar is GraphQLListType) return null;

    final cached = _predicateInputCache[scalar];
    if (cached != null) return cached;

    final scalarName = scalar.name ?? 'Scalar';
    final isString =
        scalar is GraphQLScalarType && scalar.name == graphQLString.name;

    final fields = <GraphQLInputObjectField>[
      GraphQLInputObjectField('eq', scalar, description: 'Equality match.'),
      GraphQLInputObjectField('ne', scalar, description: 'Inequality match.'),
      GraphQLInputObjectField('gt', scalar, description: 'Strictly greater.'),
      GraphQLInputObjectField('gte', scalar,
          description: 'Greater or equal.'),
      GraphQLInputObjectField('lt', scalar, description: 'Strictly less.'),
      GraphQLInputObjectField('lte', scalar, description: 'Less or equal.'),
      GraphQLInputObjectField(
        'in',
        GraphQLListType(scalar.nonNullable()),
        description: 'Membership in a non-empty set of values.',
      ),
      GraphQLInputObjectField(
        'notIn',
        GraphQLListType(scalar.nonNullable()),
        description: 'Negative-membership in a non-empty set of values.',
      ),
      if (isString)
        GraphQLInputObjectField(
          'like',
          scalar,
          description: 'Case-sensitive substring match.',
        ),
      GraphQLInputObjectField(
        'isNull',
        graphQLBoolean,
        description: 'true matches NULL columns; false matches non-NULL.',
      ),
    ];

    final input = GraphQLInputObjectType(
      '${scalarName}Predicate',
      description:
          'Predicate input for $scalarName fields. Multiple operators '
          'within one predicate input AND together.',
      inputFields: fields,
    );
    _predicateInputCache[scalar] = input;
    return input;
  }

  /// Builds (and caches) `<Entity>SortInput`. Returns null if the
  /// entity has no sortable attributes.
  GraphQLInputObjectType? _sortInputFor(ManagedEntity entity) {
    final cached = _sortInputCache[entity];
    if (cached != null) return cached;

    final fieldEnum = _sortFieldEnumFor(entity);
    if (fieldEnum == null) return null;

    final dirEnum = _sortDirectionEnumValue();

    final input = GraphQLInputObjectType(
      '${entity.name}SortInput',
      description: 'A single sort directive over a ${entity.name} field.',
      inputFields: [
        GraphQLInputObjectField<String, String>(
          'field',
          fieldEnum.nonNullable(),
          description: 'The ${entity.name} attribute to sort by.',
        ),
        GraphQLInputObjectField<String, String>(
          'direction',
          dirEnum.nonNullable(),
          description: 'ASC for ascending, DESC for descending.',
        ),
      ],
    );
    _sortInputCache[entity] = input;
    return input;
  }

  /// Builds (and caches) the `<Entity>SortField` enum — one value per
  /// non-transient attribute. Returns null if the entity has no
  /// sortable attributes.
  GraphQLEnumType<String>? _sortFieldEnumFor(ManagedEntity entity) {
    final cached = _sortFieldEnumCache[entity];
    if (cached != null) return cached;

    final names = entity.attributes.values
        .whereType<ManagedAttributeDescription>()
        .where((a) => !a.isTransient)
        .map((a) => a.name)
        .toList();
    if (names.isEmpty) return null;

    final values = names
        .map((n) => GraphQLEnumValue<String>(n, n))
        .toList();
    final e = GraphQLEnumType<String>(
      '${entity.name}SortField',
      values,
      description: 'Sortable ${entity.name} attributes.',
    );
    _sortFieldEnumCache[entity] = e;
    return e;
  }

  /// Returns the shared `SortDirection` enum, building it on first
  /// ask. One enum across the whole schema — no per-entity duplication.
  GraphQLEnumType<String> _sortDirectionEnumValue() {
    final existing = _sortDirectionEnum;
    if (existing != null) return existing;
    final e = GraphQLEnumType<String>(
      'SortDirection',
      [
        GraphQLEnumValue<String>('ASC', 'ASC',
            description: 'Ascending order.'),
        GraphQLEnumValue<String>('DESC', 'DESC',
            description: 'Descending order.'),
      ],
      description: 'Direction of a sort: ASC or DESC.',
    );
    _sortDirectionEnum = e;
    return e;
  }
  
  // ===========================================================================
  // G4 — graph schema derivation (parallel hierarchy to fromManagedDataModel).
  //
  // The methods below are strictly additive on top of the G2 surface. Nothing
  // in the relational walker calls into them, and they do not touch any of
  // the G2 helpers above except via the deliberately-shared scalars. G3's
  // arg-generation work (filter/sort/pagination input types) lives in its
  // own helper file once it lands; the graph-side mirror of that arg
  // generation lives here under the `_graphArgsFor*` helpers below.
  // ===========================================================================

  /// Custom `JSON` scalar used for schemaless property bags. Defaults
  /// to [graphQLJSON]; overridable for tests that want to swap in a
  /// validated variant. Independent of [dateTimeScalar] / [uuidScalar]
  /// because the JSON scalar is graph-only.
  ///
  /// Even though the slot exists on every builder, it is only ever
  /// referenced when [GraphSchemaConfig.nodes] declares
  /// `hasSchemalessProperties: true` for some node — purely-typed
  /// graph schemas do not surface this scalar.
  GraphQLScalarType<String, String> get jsonScalar => graphQLJSON;

  /// Derives a [GraphQLSchema] from a [GraphDataModel].
  ///
  /// Mirrors [fromManagedDataModel] but for the graph parallel hierarchy.
  /// The walker performs the same two-pass deferred-ref dance:
  ///
  /// 1. Register a deferred [GraphQLObjectType] per node entity, plus a
  ///    deferred type per declared union member label, plus a deferred
  ///    type per edge entity. Multi-label nodes additionally register a
  ///    [GraphQLUnionType] keyed on the primary label.
  /// 2. Populate fields on every registered type. Node fields come from
  ///    [GraphSchemaConfig.nodes] (the property bag is schemaless at
  ///    runtime, so we can't introspect it). Edge fields combine
  ///    declared edge properties with `from:` and `to:` endpoints.
  /// 3. Construct the Query root: per node type, list-all + by-id; per
  ///    edge type, list-all of the connection. Names collide with any
  ///    relational walker output if both are called on the same builder
  ///    (G5 unifies them); that case is detected and rejected here with
  ///    a [StateError].
  ///
  /// [config] is the per-node and per-edge declaration surface — see
  /// [GraphSchemaConfig]. Empty config is valid: every node still gets
  /// an `id: ID!` and `labels: [String!]!` field plus a Query-root
  /// list-all; every edge gets `from`, `to`, and an `id`.
  ///
  /// [resolverFactory] is the optional resolver-attachment hook
  /// (parallel to G3's planned hook for the SQL side). When supplied,
  /// every field this method emits has its `resolve` closure populated
  /// from the factory; otherwise resolvers stay `null` (introspection
  /// works, execution surfaces field errors per the GraphQL spec).
  GraphQLSchema fromGraphDataModel(
    GraphDataModel model, {
    GraphSchemaConfig? config,
    GraphResolverFactory? resolverFactory,
  }) {
    final cfg = config ?? GraphSchemaConfig();
    final nodeEntities = model.nodeEntities.values.toList();
    final edgeEntities = model.edgeEntities.values.toList();
    if (nodeEntities.isEmpty) {
      throw ArgumentError(
        'SchemaBuilder.fromGraphDataModel requires at least one '
        'GraphNodeEntity in the data model, but the model is empty.',
      );
    }

    // First pass: register type tokens. Each node entity contributes
    // its primary type + any extra union-member types declared by the
    // config. Edge entities contribute one object type each.
    final nodeRegistry = <GraphNodeEntity, GraphQLObjectType>{};
    final unionMemberRegistry = <String, GraphQLObjectType>{};
    final edgeRegistry = <GraphEdgeEntity, GraphQLObjectType>{};
    final unionRegistry = <GraphNodeEntity, GraphQLUnionType>{};

    for (final entity in nodeEntities) {
      final primary = GraphQLObjectType(
        entity.label.name,
        _nodeDescription(entity),
      );
      nodeRegistry[entity] = primary;
      unionMemberRegistry[entity.label.name] = primary;
      final extra = cfg.nodeConfig(entity.type).unionLabels;
      for (final extraName in extra) {
        if (extraName == entity.label.name) continue;
        unionMemberRegistry.putIfAbsent(
          extraName,
          () => GraphQLObjectType(
            extraName,
            'Multi-label projection of ${entity.label.name} '
                'under the additional label $extraName.',
          ),
        );
      }
    }
    for (final entity in edgeEntities) {
      edgeRegistry[entity] = GraphQLObjectType(
        entity.label.name,
        _edgeDescription(entity),
      );
    }

    // Second pass: populate node + edge fields, then build unions.
    for (final entity in nodeEntities) {
      _populateNodeFields(
        entity,
        cfg,
        nodeRegistry,
        unionMemberRegistry,
        edgeEntities,
        edgeRegistry,
        resolverFactory,
      );
    }
    for (final entity in edgeEntities) {
      _populateEdgeFields(
        entity,
        cfg,
        nodeRegistry,
        edgeRegistry,
        resolverFactory,
      );
    }

    // Build any union types whose entity declares extra labels. We
    // do this *after* fields are populated so members carry their
    // shape — a union over empty-stub types is allowed by the spec
    // but is useless for clients.
    for (final entity in nodeEntities) {
      final extra = cfg.nodeConfig(entity.type).unionLabels;
      if (extra.isEmpty) continue;
      final members = <GraphQLObjectType>[
        nodeRegistry[entity]!,
        for (final extraName in extra)
          if (extraName != entity.label.name)
            unionMemberRegistry[extraName]!,
      ];
      // Union name follows the convention `<Primary>Or<Other>...`,
      // which is verbose but stable and conflict-free. Most users will
      // alias this in their query layer.
      final unionName = _unionTypeName(entity.label.name, extra);
      unionRegistry[entity] = GraphQLUnionType(unionName, members);
    }

    // Construct the Query root.
    final queryRoot = _buildGraphQueryRoot(
      nodeEntities,
      edgeEntities,
      nodeRegistry,
      edgeRegistry,
      unionRegistry,
      cfg,
      resolverFactory,
    );

    return GraphQLSchema(queryType: queryRoot);
  }

  /// Single-entity convenience: returns the node [GraphQLObjectType]
  /// for [entity] independent of any data-model walk. Behaves like
  /// [objectTypeFor] for the SQL side — outgoing edges resolve to
  /// fresh empty stubs of their destination types if those entities
  /// are not part of the registry passed in.
  GraphQLObjectType nodeObjectTypeFor(
    GraphNodeEntity entity, {
    GraphSchemaConfig? config,
  }) {
    final cfg = config ?? GraphSchemaConfig();
    final nodeRegistry = <GraphNodeEntity, GraphQLObjectType>{
      entity: GraphQLObjectType(entity.label.name, _nodeDescription(entity)),
    };
    final unionMembers = <String, GraphQLObjectType>{
      entity.label.name: nodeRegistry[entity]!,
    };
    _populateNodeFields(
      entity,
      cfg,
      nodeRegistry,
      unionMembers,
      const [],
      const {},
      null,
    );
    return nodeRegistry[entity]!;
  }

  /// Single-entity convenience for edges. Endpoint object types are
  /// fabricated as empty stubs because we have no node entities to
  /// borrow from in this code path; use [fromGraphDataModel] when full
  /// shape is required.
  GraphQLObjectType edgeObjectTypeFor(
    GraphEdgeEntity entity, {
    GraphSchemaConfig? config,
    GraphQLObjectType? fromType,
    GraphQLObjectType? toType,
  }) {
    final cfg = config ?? GraphSchemaConfig();
    final edgeRegistry = <GraphEdgeEntity, GraphQLObjectType>{
      entity: GraphQLObjectType(entity.label.name, _edgeDescription(entity)),
    };
    final nodeRegistry = <GraphNodeEntity, GraphQLObjectType>{};
    if (fromType != null && entity.fromType != null) {
      nodeRegistry[GraphNodeEntity(
        type: entity.fromType!,
        label: GraphLabel(fromType.name),
      )] = fromType;
    }
    if (toType != null && entity.toType != null) {
      nodeRegistry[GraphNodeEntity(
        type: entity.toType!,
        label: GraphLabel(toType.name),
      )] = toType;
    }
    _populateEdgeFields(
      entity,
      cfg,
      nodeRegistry,
      edgeRegistry,
      null,
    );
    return edgeRegistry[entity]!;
  }

  // -- Internals (graph) ----------------------------------------------------

  String _nodeDescription(GraphNodeEntity entity) =>
      'GraphQL projection of graph node ${entity.label.name} '
      '(Dart type ${entity.type}).';

  String _edgeDescription(GraphEdgeEntity entity) {
    final from = entity.fromType?.toString() ?? '?';
    final to = entity.toType?.toString() ?? '?';
    return 'GraphQL projection of graph edge ${entity.label.name} '
        '($from -[:${entity.label.name}]-> $to).';
  }

  /// Convention for naming a multi-label union: primary then sorted
  /// extras joined by `Or`. Matches `User + Account -> UserOrAccount`
  /// in the social-graph fixture.
  String _unionTypeName(String primary, List<String> extras) {
    final sorted = [
      for (final e in extras)
        if (e != primary) e,
    ]..sort();
    return [primary, ...sorted].join('Or');
  }

  void _populateNodeFields(
    GraphNodeEntity entity,
    GraphSchemaConfig cfg,
    Map<GraphNodeEntity, GraphQLObjectType> nodeRegistry,
    Map<String, GraphQLObjectType> unionMembers,
    List<GraphEdgeEntity> edges,
    Map<GraphEdgeEntity, GraphQLObjectType> edgeRegistry,
    GraphResolverFactory? resolverFactory,
  ) {
    final nodeType = nodeRegistry[entity]!;
    final nodeCfg = cfg.nodeConfig(entity.type);

    final fields = _builtinNodeFields(entity);
    for (final descriptor in nodeCfg.properties) {
      fields.add(_fieldForGraphProperty(descriptor));
    }
    if (nodeCfg.hasSchemalessProperties) {
      fields.add(
        GraphQLObjectField<dynamic, dynamic>(
          'properties',
          jsonScalar.nonNullable(),
          resolve: null,
          description:
              'Schemaless property bag, JSON-encoded. Opt-in: this '
              'field only appears for nodes whose GraphSchemaConfig sets '
              'hasSchemalessProperties = true.',
        ),
      );
    }

    // Traversal fields — for every edge that originates at this node
    // type, surface the destination as a list, and (gated by the
    // config flag) the edge connection itself as a parallel list.
    for (final edge in edges) {
      if (edge.fromType != entity.type) continue;
      final destEntity = _findNodeEntityByType(nodeRegistry, edge.toType);
      if (destEntity == null) continue;
      final destObject = nodeRegistry[destEntity]!;
      final pluralDest = _pluralFieldName(_lowerFirst(destObject.name));
      final destinationFieldName =
          _disambiguateTraversalField(pluralDest, fields);
      final destinationField = GraphQLObjectField<dynamic, dynamic>(
        destinationFieldName,
        GraphQLListType(destObject.nonNullable()).nonNullable(),
        resolve: resolverFactory == null
            ? null
            : (parent, _) {
                if (parent is GraphNode) {
                  return resolverFactory.traverse(
                    from: parent,
                    edgeType: edge.type,
                  );
                }
                return null;
              },
        description:
            'Traverses ${edge.label.name} edges from this '
            '${entity.label.name} and returns the destination '
            '${destObject.name}s.',
      );
      fields.add(destinationField);

      if (cfg.exposeGraphEdgesAsConnections) {
        final edgeObject = edgeRegistry[edge]!;
        final edgeFieldName = _pluralFieldName(_lowerFirst(edgeObject.name));
        final edgeListField = GraphQLObjectField<dynamic, dynamic>(
          edgeFieldName,
          GraphQLListType(edgeObject.nonNullable()).nonNullable(),
          resolve: null, // edge-list traversal lands in G5
          description:
              'Walks ${edge.label.name} edges from this '
              '${entity.label.name}, returning the edge records '
              '(with edge properties) rather than the destination '
              'nodes. Opt-in via '
              'GraphSchemaConfig.exposeGraphEdgesAsConnections.',
        );
        fields.add(edgeListField);
      }
    }

    nodeType.fields.addAll(fields);

    // Mirror the populated fields onto every union-member stub so the
    // union's possible types all have a usable shape.
    for (final extraName in cfg.nodeConfig(entity.type).unionLabels) {
      if (extraName == entity.label.name) continue;
      final memberType = unionMembers[extraName];
      if (memberType == null) continue;
      memberType.fields.addAll(_cloneFields(fields));
    }
  }

  void _populateEdgeFields(
    GraphEdgeEntity entity,
    GraphSchemaConfig cfg,
    Map<GraphNodeEntity, GraphQLObjectType> nodeRegistry,
    Map<GraphEdgeEntity, GraphQLObjectType> edgeRegistry,
    GraphResolverFactory? resolverFactory,
  ) {
    final edgeType = edgeRegistry[entity]!;
    final edgeCfg = cfg.edgeConfig(entity.type);

    edgeType.fields.add(
      GraphQLObjectField<dynamic, dynamic>(
        'id',
        graphQLString.nonNullable(),
        resolve: null,
        description: 'Store-assigned id of the edge record.',
      ),
    );

    for (final descriptor in edgeCfg.properties) {
      edgeType.fields.add(_fieldForGraphProperty(descriptor));
    }

    final fromObject = entity.fromType == null
        ? null
        : _findNodeEntityByType(nodeRegistry, entity.fromType);
    final toObject = entity.toType == null
        ? null
        : _findNodeEntityByType(nodeRegistry, entity.toType);

    if (fromObject != null) {
      edgeType.fields.add(
        GraphQLObjectField<dynamic, dynamic>(
          'from',
          nodeRegistry[fromObject]!.nonNullable(),
          resolve: null,
          description: 'Source endpoint of the ${entity.label.name} edge.',
        ),
      );
    }
    if (toObject != null) {
      edgeType.fields.add(
        GraphQLObjectField<dynamic, dynamic>(
          'to',
          nodeRegistry[toObject]!.nonNullable(),
          resolve: null,
          description: 'Target endpoint of the ${entity.label.name} edge.',
        ),
      );
    }
  }

  /// The two universally-present node fields: `id: ID!` and
  /// `labels: [String!]!`. Keeping these separate from the
  /// configuration-declared properties keeps the minimum-viable shape
  /// useful even when no `GraphSchemaConfig` entries exist.
  List<GraphQLObjectField<dynamic, dynamic>> _builtinNodeFields(
    GraphNodeEntity entity,
  ) {
    return [
      GraphQLObjectField<dynamic, dynamic>(
        'id',
        graphQLString.nonNullable(),
        resolve: null,
        description: 'Store-assigned id of the node.',
      ),
      GraphQLObjectField<dynamic, dynamic>(
        'labels',
        GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        resolve: null,
        description: 'Labels carried by this node in the graph store.',
      ),
    ];
  }

  GraphQLObjectField<dynamic, dynamic> _fieldForGraphProperty(
    GraphPropertyDescriptor descriptor,
  ) {
    final scalar = _scalarForGraphPropertyType(descriptor.type);
    final wrapped =
        descriptor.isNullable ? scalar : scalar.nonNullable();
    return GraphQLObjectField<dynamic, dynamic>(
      descriptor.name,
      wrapped,
      resolve: null,
      description: descriptor.description,
    );
  }

  GraphQLType<dynamic, dynamic> _scalarForGraphPropertyType(
    GraphPropertyType type,
  ) {
    switch (type) {
      case GraphPropertyType.string:
        return graphQLString;
      case GraphPropertyType.integer:
        // GraphPropertyType.integer is documented as 64-bit on the
        // graph side. Mirror the bigInteger guardrail from the SQL
        // mapping so callers don't silently overflow Int.
        return bigIntegerAsString ? graphQLString : graphQLInt;
      case GraphPropertyType.double:
        return graphQLFloat;
      case GraphPropertyType.bool:
        return graphQLBoolean;
      case GraphPropertyType.datetime:
        return dateTimeScalar;
      case GraphPropertyType.list:
        // Element type is unknown at this layer (graph properties
        // don't carry generic information). String is a defensible
        // default mirroring the SQL walker's handling of
        // ManagedPropertyType.list with no element info.
        return GraphQLListType(graphQLString.nonNullable());
      case GraphPropertyType.map:
        // Same convention as the SQL walker: lower to a JSON-encoded
        // string. Apps that need typed access can declare a
        // hand-written type and surface it via the resolver factory.
        return jsonScalar;
    }
  }

  GraphNodeEntity? _findNodeEntityByType(
    Map<GraphNodeEntity, GraphQLObjectType> nodeRegistry,
    Type? type,
  ) {
    if (type == null) return null;
    for (final entity in nodeRegistry.keys) {
      if (entity.type == type) return entity;
    }
    return null;
  }

  GraphQLObjectType _buildGraphQueryRoot(
    List<GraphNodeEntity> nodeEntities,
    List<GraphEdgeEntity> edgeEntities,
    Map<GraphNodeEntity, GraphQLObjectType> nodeRegistry,
    Map<GraphEdgeEntity, GraphQLObjectType> edgeRegistry,
    Map<GraphNodeEntity, GraphQLUnionType> unionRegistry,
    GraphSchemaConfig cfg,
    GraphResolverFactory? resolverFactory,
  ) {
    final fields = <GraphQLObjectField<dynamic, dynamic>>[];
    final seen = <String>{};

    for (final entity in nodeEntities) {
      final type = nodeRegistry[entity]!;
      final union = unionRegistry[entity];
      // List-and-by-id traverse the underlying node type even when
      // the entity exposes a union; clients pick a discriminator via
      // GraphQL's standard `... on <Type>` inline-fragment. The union
      // type itself is reachable by querying the connection edge.
      final singularName = _lowerFirst(type.name);
      final pluralName = _pluralFieldName(singularName);

      _ensureUnique(seen, pluralName, type.name);
      _ensureUnique(seen, singularName, type.name);

      // List-all
      fields.add(
        GraphQLObjectField<dynamic, dynamic>(
          pluralName,
          GraphQLListType((union ?? type).nonNullable()).nonNullable(),
          resolve: resolverFactory == null
              ? null
              : (_, args) =>
                  resolverFactory.list(entity: entity, args: args),
          description:
              'Returns every ${type.name}. Read-only in G4; G5 adds '
              'where/order/pagination arguments and cross-source '
              'dispatch.',
        ),
      );

      // By-pk (using the store-assigned `id` since GraphNode has no
      // user-declared primary key).
      fields.add(
        GraphQLObjectField<dynamic, dynamic>(
          singularName,
          (union ?? type),
          resolve: resolverFactory == null
              ? null
              : (_, args) => resolverFactory.byId(entity: entity, args: args),
          arguments: [
            GraphQLFieldInput(
              'id',
              graphQLString.nonNullable(),
              description: 'Store-assigned id of the ${type.name} to fetch.',
            ),
          ],
          description:
              'Returns the ${type.name} with the given id, or null '
              'if none exists.',
        ),
      );
    }

    for (final entity in edgeEntities) {
      final type = edgeRegistry[entity]!;
      final singularName = _lowerFirst(type.name);
      final pluralName = _pluralFieldName(singularName);
      _ensureUnique(seen, pluralName, type.name);

      fields.add(
        GraphQLObjectField<dynamic, dynamic>(
          pluralName,
          GraphQLListType(type.nonNullable()).nonNullable(),
          resolve: resolverFactory == null
              ? null
              : (_, args) =>
                  resolverFactory.edgeList(entity: entity, args: args),
          description:
              'Returns every ${type.name} edge record. The edge '
              'object carries its declared edge properties plus '
              'from/to endpoints.',
        ),
      );
    }

    return GraphQLObjectType(
      'Query',
      'Read-only Conduit GraphQL query root, derived from a '
          'GraphDataModel.',
    )..fields.addAll(fields);
  }

  /// Throws [StateError] when a query-root field name collides with a
  /// previously-emitted name. The resolution rule documented in the
  /// G4 plan: graph + relational walkers in the same builder must not
  /// collide; cross-source unification is G5's responsibility.
  void _ensureUnique(Set<String> seen, String name, String typeName) {
    if (!seen.add(name)) {
      throw StateError(
        'Query-root field name "$name" emitted more than once while '
        'deriving GraphDataModel schema (offending type: $typeName). '
        'Two graph types map to the same field; rename one or wait '
        'for G5\'s cross-source unification before mixing two models '
        'in the same SchemaBuilder.',
      );
    }
  }

  String _lowerFirst(String s) {
    if (s.isEmpty) return s;
    return s.substring(0, 1).toLowerCase() + s.substring(1);
  }

  /// If [name] collides with an already-added field, append `Via<EdgeName>`.
  /// We only see this when two outgoing edges from the same source node
  /// land on the same destination type (e.g. `User -[Authored]-> Post`
  /// and `User -[Liked]-> Post` both want to surface as `posts`).
  String _disambiguateTraversalField(
    String name,
    List<GraphQLObjectField<dynamic, dynamic>> fields,
  ) {
    if (fields.every((f) => f.name != name)) return name;
    var i = 2;
    while (fields.any((f) => f.name == '$name$i')) {
      i++;
    }
    return '$name$i';
  }

  /// Shallow copy of [fields] for installation onto an additional
  /// union-member type. Sharing the same `GraphQLObjectField`
  /// instances would work in principle (they're immutable from the
  /// outside) but copying makes the SDL printer's per-type field
  /// iteration deterministic.
  List<GraphQLObjectField<dynamic, dynamic>> _cloneFields(
    List<GraphQLObjectField<dynamic, dynamic>> fields,
  ) {
    return [
      for (final f in fields)
        GraphQLObjectField<dynamic, dynamic>(
          f.name,
          f.type,
          arguments: f.inputs,
          resolve: f.resolve,
          description: f.description,
          deprecationReason: f.deprecationReason,
        ),
    ];
  }

  // ===========================================================================
  // G5 — cross-source dispatch + field-level auth.
  //
  // [fromPersistence] unifies the relational walker (G2 + G3) and the graph
  // walker (G4) into a single emitted [GraphQLSchema]. The two halves remain
  // strictly additive — every emitted ObjectType is reachable via the
  // returned [PersistenceSchema]'s side-channel `sourceFor` map, which tags
  // each type with `'sql'` or `'graph'`.
  //
  // Cross-source dispatch is **not** automatic: the umbrella routes per
  // field, never joins per query. Joining a SQL row to a graph node is a
  // hand-written stitching resolver — see
  // `docs/persistence/graphql-cross-source.md` for the worked pattern.
  // ===========================================================================

  /// Side-channel populated by [fromPersistence]: maps every emitted
  /// ObjectType (relational + graph) to the literal source tag
  /// `'sql'` or `'graph'`. Read via [PersistenceSchema.sourceFor].
  ///
  /// Built fresh on every [fromPersistence] invocation; previous tags
  /// are dropped. Other emit paths
  /// ([fromManagedDataModel] / [fromGraphDataModel]) leave this empty.
  final Map<GraphQLObjectType, String> _sourceTags = {};

  /// Returns `'sql'`, `'graph'`, or `null` for an [GraphQLObjectType]
  /// emitted by the most recent [fromPersistence] call.
  String? sourceTagFor(GraphQLObjectType type) => _sourceTags[type];

  /// Derives a unified [PersistenceSchema] from a [Persistence] umbrella.
  ///
  /// Walks both halves of the umbrella (whichever are configured) and
  /// emits one [GraphQLSchema] with both sides' object types reachable
  /// from a single Query root. Source-tags every emitted ObjectType so
  /// callers can introspect which half emitted what.
  ///
  /// [resolverFactory] is the cross-source umbrella that wires SQL and
  /// graph resolvers to their respective emission sites. When non-null
  /// it is the **single** point of attachment — do not also pass
  /// resolver hooks via the [SchemaBuilder] constructor; the umbrella's
  /// hook set replaces them.
  ///
  /// [graphConfig] mirrors the parameter on [fromGraphDataModel].
  ///
  /// [collisionPolicy] picks how query-root field name collisions
  /// between the two halves are resolved. Defaults to
  /// [QueryRootCollisionPolicy.error] for back-compat with G4.
  ///
  /// [authPolicy] enables field-level authorization. When non-null it
  /// is consulted at every emission site (attribute, relationship,
  /// graph property, query-root) and any descriptor with a registered
  /// [FieldAuthorize] receives an auth-wrapping resolver that runs
  /// before the underlying resolver. Failed checks raise a
  /// `GraphQLException` per the GraphQL execution spec.
  PersistenceSchema fromPersistence<G extends Object>(
    Persistence<G> persistence, {
    PersistenceResolverFactory<G>? resolverFactory,
    GraphSchemaConfig? graphConfig,
    QueryRootCollisionPolicy collisionPolicy =
        QueryRootCollisionPolicy.error,
    FieldAuthPolicy? authPolicy,
  }) {
    if (!persistence.hasSql && !persistence.hasGraph) {
      throw ArgumentError(
        'SchemaBuilder.fromPersistence requires at least one of `sql:` or '
        '`graph:` to be configured on the Persistence umbrella, but the '
        'umbrella has neither.',
      );
    }

    _sourceTags.clear();

    // Build the relational half, if any.
    final sqlRegistry = <ManagedEntity, GraphQLObjectType>{};
    final sqlEntities = <ManagedEntity>[];
    if (persistence.hasSql) {
      final sqlContext = persistence.sqlContext;
      if (sqlContext == null) {
        throw StateError(
          'SchemaBuilder.fromPersistence: persistence.hasSql is true but '
          'persistence.sqlContext is null. The umbrella holds the store '
          'but the application has not yet wired its ManagedContext; '
          'call this from `prepare()` after attaching the context.',
        );
      }
      final model = sqlContext.dataModel;
      if (model == null) {
        throw StateError(
          'SchemaBuilder.fromPersistence: ManagedContext has no '
          'dataModel attached.',
        );
      }
      sqlEntities.addAll(model.entities);
      for (final entity in sqlEntities) {
        final type = GraphQLObjectType(
          entity.name,
          _entityDescription(entity),
        );
        sqlRegistry[entity] = type;
        _sourceTags[type] = 'sql';
      }
      for (final entity in sqlEntities) {
        _populateFields(entity, sqlRegistry);
      }
    }

    // Build the graph half, if any.
    final cfg = graphConfig ?? GraphSchemaConfig();
    final nodeRegistry = <GraphNodeEntity, GraphQLObjectType>{};
    final unionMemberRegistry = <String, GraphQLObjectType>{};
    final edgeRegistry = <GraphEdgeEntity, GraphQLObjectType>{};
    final unionRegistry = <GraphNodeEntity, GraphQLUnionType>{};
    final nodeEntities = <GraphNodeEntity>[];
    final edgeEntities = <GraphEdgeEntity>[];
    final graphFactory = resolverFactory?.graph;
    if (persistence.hasGraph) {
      final graphContextRaw = persistence.graphContext;
      if (graphContextRaw == null) {
        throw StateError(
          'SchemaBuilder.fromPersistence: persistence.hasGraph is true but '
          'persistence.graphContext is null. Wire the GraphContext in '
          '`prepare()` before calling fromPersistence.',
        );
      }
      if (graphContextRaw is! GraphContext) {
        throw StateError(
          'SchemaBuilder.fromPersistence: persistence.graphContext must be '
          'a GraphContext instance, got ${graphContextRaw.runtimeType}.',
        );
      }
      final graphModel = graphContextRaw.dataModel;
      nodeEntities.addAll(graphModel.nodeEntities.values);
      edgeEntities.addAll(graphModel.edgeEntities.values);

      for (final entity in nodeEntities) {
        final primary = GraphQLObjectType(
          entity.label.name,
          _nodeDescription(entity),
        );
        nodeRegistry[entity] = primary;
        unionMemberRegistry[entity.label.name] = primary;
        _sourceTags[primary] = 'graph';
        final extra = cfg.nodeConfig(entity.type).unionLabels;
        for (final extraName in extra) {
          if (extraName == entity.label.name) continue;
          final memberType = unionMemberRegistry.putIfAbsent(
            extraName,
            () => GraphQLObjectType(
              extraName,
              'Multi-label projection of ${entity.label.name} '
                  'under the additional label $extraName.',
            ),
          );
          _sourceTags[memberType] = 'graph';
        }
      }
      for (final entity in edgeEntities) {
        final type = GraphQLObjectType(
          entity.label.name,
          _edgeDescription(entity),
        );
        edgeRegistry[entity] = type;
        _sourceTags[type] = 'graph';
      }
      for (final entity in nodeEntities) {
        _populateNodeFields(
          entity,
          cfg,
          nodeRegistry,
          unionMemberRegistry,
          edgeEntities,
          edgeRegistry,
          graphFactory,
        );
      }
      for (final entity in edgeEntities) {
        _populateEdgeFields(
          entity,
          cfg,
          nodeRegistry,
          edgeRegistry,
          graphFactory,
        );
      }
      for (final entity in nodeEntities) {
        final extra = cfg.nodeConfig(entity.type).unionLabels;
        if (extra.isEmpty) continue;
        final members = <GraphQLObjectType>[
          nodeRegistry[entity]!,
          for (final extraName in extra)
            if (extraName != entity.label.name)
              unionMemberRegistry[extraName]!,
        ];
        final unionName = _unionTypeName(entity.label.name, extra);
        unionRegistry[entity] = GraphQLUnionType(unionName, members);
      }
    }

    // Apply field-level auth wrappers AFTER population so we don't have
    // to thread the policy through every populator.
    if (authPolicy != null) {
      _applyFieldAuthToSqlTypes(sqlRegistry, authPolicy);
      _applyFieldAuthToGraphProperties(
        cfg,
        nodeRegistry,
        edgeRegistry,
        unionMemberRegistry,
        authPolicy,
      );
    }

    final hookSet = resolverFactory?.hooks(authPolicy: authPolicy);

    // Build the unified Query root with collision resolution.
    final queryRoot = _buildUnifiedQueryRoot(
      sqlEntities: sqlEntities,
      sqlRegistry: sqlRegistry,
      nodeEntities: nodeEntities,
      edgeEntities: edgeEntities,
      nodeRegistry: nodeRegistry,
      edgeRegistry: edgeRegistry,
      unionRegistry: unionRegistry,
      cfg: cfg,
      hookSet: hookSet,
      graphFactory: graphFactory,
      authPolicy: authPolicy,
      collisionPolicy: collisionPolicy,
    );

    return PersistenceSchema._(
      schema: GraphQLSchema(queryType: queryRoot),
      sqlObjectTypes: Map.unmodifiable({
        for (final e in sqlRegistry.entries) e.key.name: e.value,
      }),
      graphObjectTypes: Map.unmodifiable({
        for (final e in nodeRegistry.entries) e.key.label.name: e.value,
        for (final e in edgeRegistry.entries) e.key.label.name: e.value,
      }),
      sourceTags: Map.unmodifiable(_sourceTags),
    );
  }

  /// Wraps each pre-populated SQL object type's resolvers with auth
  /// closures derived from [policy]. Reads the descriptor off the
  /// builder's data-model walk and replaces the field-resolver slot in
  /// place — graphql_schema2 v6.5.0 doesn't expose a setter for
  /// `resolve:`, so we replace the field instance.
  void _applyFieldAuthToSqlTypes(
    Map<ManagedEntity, GraphQLObjectType> registry,
    FieldAuthPolicy policy,
  ) {
    for (final entry in registry.entries) {
      final entity = entry.key;
      final type = entry.value;
      final replacements = <GraphQLObjectField, GraphQLObjectField>{};
      for (final attr in entity.attributes.values
          .whereType<ManagedAttributeDescription>()) {
        final auth = policy.authFor(attr);
        if (auth == null) continue;
        final field = _findFieldByName(type, attr.name);
        if (field == null) continue;
        final inner = field.resolve;
        if (inner == null) continue;
        final wrapped = wrapResolverWithAuth(inner, auth);
        replacements[field] = GraphQLObjectField(
          field.name,
          field.type,
          arguments: field.inputs,
          resolve: wrapped,
          description: field.description,
          deprecationReason: field.deprecationReason,
        );
      }
      for (final rel in entity.relationships.values
          .whereType<ManagedRelationshipDescription>()) {
        final auth = policy.authFor(rel);
        if (auth == null) continue;
        final field = _findFieldByName(type, rel.name);
        if (field == null) continue;
        final inner = field.resolve;
        if (inner == null) continue;
        final wrapped = wrapResolverWithAuth(inner, auth);
        replacements[field] = GraphQLObjectField(
          field.name,
          field.type,
          arguments: field.inputs,
          resolve: wrapped,
          description: field.description,
          deprecationReason: field.deprecationReason,
        );
      }
      for (final old in replacements.keys) {
        final i = type.fields.indexOf(old);
        if (i >= 0) type.fields[i] = replacements[old]!;
      }
    }
  }

  /// Wraps every field on every graph-side object type whose
  /// corresponding [GraphPropertyDescriptor] declared an `auth:` entry,
  /// or whose lookup against [policy] (using a [GraphPropertyAuthKey])
  /// returns non-null. Touches both nodes and edges, plus union
  /// member stubs.
  void _applyFieldAuthToGraphProperties(
    GraphSchemaConfig cfg,
    Map<GraphNodeEntity, GraphQLObjectType> nodeRegistry,
    Map<GraphEdgeEntity, GraphQLObjectType> edgeRegistry,
    Map<String, GraphQLObjectType> unionMemberRegistry,
    FieldAuthPolicy policy,
  ) {
    for (final entry in nodeRegistry.entries) {
      final entity = entry.key;
      final type = entry.value;
      final nodeCfg = cfg.nodeConfig(entity.type);
      _wrapDeclaredGraphProperties(
        owningType: entity.type,
        objectType: type,
        descriptors: nodeCfg.properties,
        policy: policy,
      );
      // Mirror onto union-member stubs.
      for (final extraName in nodeCfg.unionLabels) {
        if (extraName == entity.label.name) continue;
        final member = unionMemberRegistry[extraName];
        if (member == null) continue;
        _wrapDeclaredGraphProperties(
          owningType: entity.type,
          objectType: member,
          descriptors: nodeCfg.properties,
          policy: policy,
        );
      }
    }
    for (final entry in edgeRegistry.entries) {
      final entity = entry.key;
      final type = entry.value;
      final edgeCfg = cfg.edgeConfig(entity.type);
      _wrapDeclaredGraphProperties(
        owningType: entity.type,
        objectType: type,
        descriptors: edgeCfg.properties,
        policy: policy,
      );
    }
  }

  void _wrapDeclaredGraphProperties({
    required Type owningType,
    required GraphQLObjectType objectType,
    required List<GraphPropertyDescriptor> descriptors,
    required FieldAuthPolicy policy,
  }) {
    for (final descriptor in descriptors) {
      final declared = descriptor.auth;
      final lookedUp =
          policy.authFor(GraphPropertyAuthKey(owningType, descriptor.name));
      final auth = declared ?? lookedUp;
      if (auth == null) continue;
      final field = _findFieldByName(objectType, descriptor.name);
      if (field == null) continue;
      final inner = field.resolve ?? _graphPropertyMapResolver(descriptor.name);
      final wrapped = wrapResolverWithAuth(inner, auth);
      final replacement = GraphQLObjectField(
        field.name,
        field.type,
        arguments: field.inputs,
        resolve: wrapped,
        description: field.description,
        deprecationReason: field.deprecationReason,
      );
      final i = objectType.fields.indexOf(field);
      if (i >= 0) objectType.fields[i] = replacement;
    }
  }

  /// Default resolver used when a graph-side property field has no
  /// `resolve:` attached but needs auth wrapping. Reads the property
  /// off the parent (a `GraphNode` / `GraphEdge` instance) by name.
  GraphQLFieldResolver<Object?, Object?> _graphPropertyMapResolver(
    String propertyName,
  ) {
    return (parent, _) {
      if (parent is GraphNode) {
        return parent[propertyName];
      }
      if (parent is GraphEdge) {
        return parent[propertyName];
      }
      if (parent is Map) {
        return parent[propertyName];
      }
      return null;
    };
  }

  GraphQLObjectField? _findFieldByName(
    GraphQLObjectType type,
    String name,
  ) {
    for (final f in type.fields) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// Builds the unified Query root, applying [collisionPolicy] when a
  /// SQL field name and a graph field name would otherwise collide.
  GraphQLObjectType _buildUnifiedQueryRoot({
    required List<ManagedEntity> sqlEntities,
    required Map<ManagedEntity, GraphQLObjectType> sqlRegistry,
    required List<GraphNodeEntity> nodeEntities,
    required List<GraphEdgeEntity> edgeEntities,
    required Map<GraphNodeEntity, GraphQLObjectType> nodeRegistry,
    required Map<GraphEdgeEntity, GraphQLObjectType> edgeRegistry,
    required Map<GraphNodeEntity, GraphQLUnionType> unionRegistry,
    required GraphSchemaConfig cfg,
    required ResolverHookSet? hookSet,
    required GraphResolverFactory? graphFactory,
    required FieldAuthPolicy? authPolicy,
    required QueryRootCollisionPolicy collisionPolicy,
  }) {
    // Compute SQL-side field names and graph-side field names in a
    // dry-run pass so collisions can be detected before fields are
    // committed to the type.
    final sqlNames = <String>{};
    for (final entity in sqlEntities) {
      final singular = _singularFieldName(entity);
      final plural = _pluralFieldName(singular);
      sqlNames.add(singular);
      sqlNames.add(plural);
    }
    final graphNames = <String>{};
    for (final entity in nodeEntities) {
      final type = nodeRegistry[entity]!;
      final singular = _lowerFirst(type.name);
      final plural = _pluralFieldName(singular);
      graphNames.add(singular);
      graphNames.add(plural);
    }
    for (final entity in edgeEntities) {
      final type = edgeRegistry[entity]!;
      final plural = _pluralFieldName(_lowerFirst(type.name));
      graphNames.add(plural);
    }

    final colliding = sqlNames.intersection(graphNames);
    if (colliding.isNotEmpty &&
        collisionPolicy == QueryRootCollisionPolicy.error) {
      throw StateError(
        'SchemaBuilder.fromPersistence: query-root field names collide '
        'between the SQL and graph halves: ${colliding.toList()..sort()}. '
        'Pick a non-error QueryRootCollisionPolicy or rename one of the '
        'colliding entities.',
      );
    }

    String renameSql(String name) =>
        colliding.contains(name) &&
                collisionPolicy == QueryRootCollisionPolicy.prefixRelational
            ? 'r_$name'
            : name;
    String renameGraph(String name) =>
        colliding.contains(name) &&
                collisionPolicy == QueryRootCollisionPolicy.prefixGraph
            ? 'g_$name'
            : name;

    final fields = <GraphQLObjectField<dynamic, dynamic>>[];

    // SQL Query-root fields ---------------------------------------------
    for (final entity in sqlEntities) {
      final type = sqlRegistry[entity]!;
      final singular = renameSql(_singularFieldName(entity));
      final plural = renameSql(_pluralFieldName(_singularFieldName(entity)));

      final listResolver = hookSet?.queryListResolver(entity);
      final byPkResolver = hookSet?.queryByPkResolver(entity);
      final listArgs = _buildListArgsFor(entity);
      fields.add(
        GraphQLObjectField(
          plural,
          GraphQLListType(type.nonNullable()).nonNullable(),
          resolve: listResolver,
          arguments: listArgs,
          description:
              'Returns every ${entity.name} (relational source).',
        ),
      );
      final pkAttr = entity.primaryKeyAttribute;
      if (pkAttr != null) {
        final pkScalar = _scalarFor(pkAttr);
        fields.add(
          GraphQLObjectField(
            singular,
            type,
            resolve: byPkResolver,
            arguments: [
              GraphQLFieldInput(
                pkAttr.name,
                pkScalar.nonNullable(),
                description: 'Primary key of the ${entity.name} to fetch.',
              ),
            ],
            description: 'Returns the ${entity.name} with the given '
                '${pkAttr.name}, or null if none exists.',
          ),
        );
      }
    }

    // Graph Query-root fields -------------------------------------------
    for (final entity in nodeEntities) {
      final type = nodeRegistry[entity]!;
      final union = unionRegistry[entity];
      final singular = renameGraph(_lowerFirst(type.name));
      final plural = renameGraph(_pluralFieldName(_lowerFirst(type.name)));

      // List-all
      GraphQLFieldResolver<Object?, Object?>? listResolver =
          graphFactory == null
              ? null
              : (_, args) => graphFactory.list(entity: entity, args: args);
      if (authPolicy != null && listResolver != null) {
        final auth = authPolicy.authFor(entity);
        if (auth != null) {
          listResolver = wrapResolverWithAuth(listResolver, auth);
        }
      }
      fields.add(
        GraphQLObjectField<dynamic, dynamic>(
          plural,
          GraphQLListType((union ?? type).nonNullable()).nonNullable(),
          resolve: listResolver,
          description: 'Returns every ${type.name} (graph source).',
        ),
      );

      // By-id
      GraphQLFieldResolver<Object?, Object?>? byIdResolver =
          graphFactory == null
              ? null
              : (_, args) => graphFactory.byId(entity: entity, args: args);
      if (authPolicy != null && byIdResolver != null) {
        final auth = authPolicy.authFor(entity);
        if (auth != null) {
          byIdResolver = wrapResolverWithAuth(byIdResolver, auth);
        }
      }
      fields.add(
        GraphQLObjectField<dynamic, dynamic>(
          singular,
          (union ?? type),
          resolve: byIdResolver,
          arguments: [
            GraphQLFieldInput(
              'id',
              graphQLString.nonNullable(),
              description:
                  'Store-assigned id of the ${type.name} to fetch.',
            ),
          ],
          description: 'Returns the ${type.name} with the given id '
              '(graph source), or null if none exists.',
        ),
      );
    }
    for (final entity in edgeEntities) {
      final type = edgeRegistry[entity]!;
      final plural = renameGraph(_pluralFieldName(_lowerFirst(type.name)));
      fields.add(
        GraphQLObjectField<dynamic, dynamic>(
          plural,
          GraphQLListType(type.nonNullable()).nonNullable(),
          resolve: graphFactory == null
              ? null
              : (_, args) => graphFactory.edgeList(entity: entity, args: args),
          description: 'Returns every ${type.name} edge record (graph '
              'source).',
        ),
      );
    }

    return GraphQLObjectType(
      'Query',
      'Unified Conduit GraphQL query root, derived from a Persistence '
          'umbrella. SQL fields and graph fields share this root; '
          'source tags on each ObjectType identify which half emitted '
          'it.',
    )..fields.addAll(fields);
  }
}

/// Result type for [SchemaBuilder.fromPersistence]: pairs the emitted
/// [GraphQLSchema] with the side-channel maps callers need to introspect
/// which half of the umbrella produced which type.
class PersistenceSchema {
  PersistenceSchema._({
    required this.schema,
    required this.sqlObjectTypes,
    required this.graphObjectTypes,
    required this.sourceTags,
  });

  /// The unified [GraphQLSchema] ready to hand to [GraphQLController].
  final GraphQLSchema schema;

  /// Map of relational entity name → emitted [GraphQLObjectType].
  /// Empty when the umbrella has no SQL store.
  final Map<String, GraphQLObjectType> sqlObjectTypes;

  /// Map of graph entity (label) name → emitted [GraphQLObjectType].
  /// Empty when the umbrella has no graph store.
  final Map<String, GraphQLObjectType> graphObjectTypes;

  /// Source tag (`'sql'` / `'graph'`) keyed by [GraphQLObjectType].
  final Map<GraphQLObjectType, String> sourceTags;

  /// Returns `'sql'`, `'graph'`, or `null` for [type].
  String? sourceFor(GraphQLObjectType type) => sourceTags[type];
}
