import 'package:conduit_core/conduit_core.dart';
import 'package:graphql_schema2/graphql_schema2.dart';

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
}
