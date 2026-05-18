/// Schema-derivation configuration for the **graph** side
/// (`SchemaBuilder.fromGraphDataModel`).
///
/// Why this exists: a `GraphNode` does **not** statically declare its
/// properties — `conduit_graph` ships a runtime property bag, not a
/// columnar entity description like `ManagedObject`. Without a way to
/// pre-declare property types, a derived GraphQL schema would either
/// have to introspect every persisted node at startup (expensive and
/// non-deterministic) or surface an empty type. Neither is viable.
///
/// [GraphSchemaConfig] is the user-facing override point that fills
/// the gap: callers declare, per `GraphNode` Dart type, the typed
/// properties, multi-label union members, and whether the node opts
/// into schemaless property handling. Anything not declared here is
/// simply not surfaced (which mirrors the behavior of the SQL walker
/// when an entity has no attributes — never lie about what's there).
library;

import 'package:conduit_graph/conduit_graph.dart';

import '../auth/field_authorize.dart';

/// Declared shape of a single typed property on a [GraphNode] or
/// [GraphEdge].
///
/// Mirrors the role `ManagedAttributeDescription` plays for the SQL
/// walker. Both fields are required:
///
/// - [name] is the wire name surfaced in the GraphQL schema.
/// - [type] is the storage class (the same enum the graph package
///   itself uses for runtime introspection).
///
/// [isNullable] follows the convention G2 uses on the SQL side:
/// `false` lifts to a `NonNullable` wrapper in the emitted schema.
/// Defaults to `false` because typed graph properties are usually
/// declared precisely *because* the application treats them as
/// guaranteed-present. Pass `true` for properties that may be absent.
class GraphPropertyDescriptor {
  const GraphPropertyDescriptor({
    required this.name,
    required this.type,
    this.isNullable = false,
    this.description,
    this.auth,
  });

  /// Property name as it appears in the graph store and in the
  /// emitted GraphQL field.
  final String name;

  /// Storage class. Drives the scalar mapping inside the schema
  /// builder.
  final GraphPropertyType type;

  /// True if the property may be absent from the bag at read time.
  /// `false` (the default) emits the GraphQL field as non-null.
  final bool isNullable;

  /// Optional human-readable description surfaced in the SDL.
  final String? description;

  /// Optional G5 field-auth declaration. When non-null, the resolver
  /// emitted for this property is wrapped in a scope-checking closure
  /// keyed on a [GraphPropertyAuthKey] derived from the declaring
  /// node/edge type and [name]. See
  /// `lib/src/auth/field_authorize.dart` and
  /// `docs/persistence/graphql-cross-source.md` for the full pattern.
  ///
  /// Asymmetry note: on the SQL side `@FieldAuthorize` is attached to
  /// the `ManagedObject` source; on the graph side it lives here
  /// because `GraphNode` does not currently support per-property
  /// annotations.
  final FieldAuthorize? auth;
}

/// Per-node-type schema configuration.
///
/// All four lists default to empty / disabled, so adding a config for
/// a single node does **not** disturb how the rest of the graph data
/// model lowers — only the keyed type changes shape.
class GraphNodeSchemaConfig {
  const GraphNodeSchemaConfig({
    this.properties = const [],
    this.unionLabels = const [],
    this.hasSchemalessProperties = false,
  });

  /// Typed declared properties. Surfaces one GraphQL field per entry.
  ///
  /// `id` and `labels` are added by the builder; do not declare them
  /// here.
  final List<GraphPropertyDescriptor> properties;

  /// Additional labels this node carries beyond its primary
  /// [GraphNodeEntity.label]. When non-empty, the builder emits a
  /// `GraphQLUnionType` of the corresponding object types instead of
  /// a single `GraphQLObjectType`.
  ///
  /// Convention: each entry is the wire **type name** (matches the
  /// label name by default — the builder treats label and type-name
  /// interchangeably). When two labels round-trip to the same Dart
  /// node class, they share the same property declarations.
  final List<String> unionLabels;

  /// When `true`, the emitted GraphQL object type carries an extra
  /// `properties: JSON!` field surfacing the entire schemaless
  /// property bag as a JSON-encoded string. Per the G4 plan
  /// requirement: "Schemaless property handling explicitly opt-in
  /// (declared on each `GraphNode` subclass)."
  ///
  /// Defaults to `false` — typed-only mode is the default so the
  /// derived schema is precise and inspectable.
  final bool hasSchemalessProperties;
}

/// Per-edge-type schema configuration.
class GraphEdgeSchemaConfig {
  const GraphEdgeSchemaConfig({
    this.properties = const [],
  });

  /// Typed declared edge properties. Edge-property-as-connection
  /// fields surface one GraphQL field per entry alongside the
  /// `from:` / `to:` endpoints.
  final List<GraphPropertyDescriptor> properties;
}

/// Top-level schema-derivation config for the graph side.
///
/// Pass an instance to [SchemaBuilder.fromGraphDataModel] to declare
/// per-node and per-edge property shapes. Construct empty for the
/// minimum-viable schema (id + labels per node; from/to per edge).
class GraphSchemaConfig {
  GraphSchemaConfig({
    Map<Type, GraphNodeSchemaConfig> nodes = const {},
    Map<Type, GraphEdgeSchemaConfig> edges = const {},
    this.exposeGraphEdgesAsConnections = false,
  })  : _nodes = Map.unmodifiable(nodes),
        _edges = Map.unmodifiable(edges);

  final Map<Type, GraphNodeSchemaConfig> _nodes;
  final Map<Type, GraphEdgeSchemaConfig> _edges;

  /// Per-node-type config (lookup by Dart type).
  Map<Type, GraphNodeSchemaConfig> get nodes => _nodes;

  /// Per-edge-type config (lookup by Dart type).
  Map<Type, GraphEdgeSchemaConfig> get edges => _edges;

  /// When `true`, every node type with declared outgoing edges also
  /// gets an extra `<edgePlural>: [<EdgeType>!]!` field on its object
  /// type, exposing the **edge** record (with edge properties) rather
  /// than just the destination node. Defaults to `false`: only the
  /// `<destinationPlural>: [<DestType>!]!` traversal field is
  /// emitted, which keeps the schema lean for the common case.
  ///
  /// Per the G4 plan: "Pick one and document — recommendation: emit
  /// BOTH, gated by a `SchemaBuilder.exposeGraphEdgesAsConnections =
  /// true` flag, default false (only the destination-node list
  /// surfaces unless explicitly enabled)."
  final bool exposeGraphEdgesAsConnections;

  /// Lookup helper. Returns an empty config if the type is unknown
  /// (so callers don't have to null-check).
  GraphNodeSchemaConfig nodeConfig(Type type) =>
      _nodes[type] ?? const GraphNodeSchemaConfig();

  GraphEdgeSchemaConfig edgeConfig(Type type) =>
      _edges[type] ?? const GraphEdgeSchemaConfig();
}
