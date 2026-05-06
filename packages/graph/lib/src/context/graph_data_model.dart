import '../errors/graph_exception.dart';
import '../types/graph_edge.dart';
import '../types/graph_label.dart';
import '../types/graph_node.dart';

/// Description of a registered node type.
///
/// Mirrors the role conduit core's `ManagedEntity` plays in the SQL
/// ORM, but graph-flavored: a label and a Dart [Type], no column
/// definitions, no schema enforcement.
class GraphNodeEntity {
  GraphNodeEntity({required this.type, required this.label});

  /// The Dart node subclass.
  final Type type;

  /// The default label used when matching this type in a pattern.
  final GraphLabel label;

  @override
  String toString() => 'GraphNodeEntity($type, label=${label.name})';
}

/// Description of a registered edge type.
class GraphEdgeEntity {
  GraphEdgeEntity({
    required this.type,
    required this.label,
    this.fromType,
    this.toType,
  });

  /// The Dart edge subclass.
  final Type type;

  /// The default label used when matching this type in a pattern.
  final GraphLabel label;

  /// Source node Dart type, if known at registration time.
  final Type? fromType;

  /// Target node Dart type, if known at registration time.
  final Type? toType;

  @override
  String toString() =>
      'GraphEdgeEntity($type, label=${label.name}, $fromType -> $toType)';
}

/// Registry of node and edge types known to a [GraphContext].
///
/// Mirrors `ManagedDataModel` — the collection of entities the context
/// can resolve.
class GraphDataModel {
  GraphDataModel();

  final Map<Type, GraphNodeEntity> _nodes = {};
  final Map<Type, GraphEdgeEntity> _edges = {};

  /// Register a node type. The [label] defaults to the type's name.
  GraphNodeEntity registerNode<T extends GraphNode<T>>({
    GraphLabel? label,
  }) {
    final entity = GraphNodeEntity(
      type: T,
      label: label ?? GraphLabel(T.toString()),
    );
    _nodes[T] = entity;
    return entity;
  }

  /// Register an edge type. The [label] defaults to the type's name.
  GraphEdgeEntity registerEdge<
      E extends GraphEdge<From, To>,
      From extends GraphNode<From>,
      To extends GraphNode<To>>({
    GraphLabel? label,
  }) {
    final entity = GraphEdgeEntity(
      type: E,
      label: label ?? GraphLabel(E.toString()),
      fromType: From,
      toType: To,
    );
    _edges[E] = entity;
    return entity;
  }

  /// Look up a registered node type. Throws [GraphInvalidQuery] if
  /// unknown.
  GraphNodeEntity nodeEntityFor(Type type) {
    final entity = _nodes[type];
    if (entity == null) {
      throw GraphInvalidQuery(
        "node type '$type' is not registered with this GraphDataModel",
      );
    }
    return entity;
  }

  /// Look up a registered edge type. Throws [GraphInvalidQuery] if
  /// unknown.
  GraphEdgeEntity edgeEntityFor(Type type) {
    final entity = _edges[type];
    if (entity == null) {
      throw GraphInvalidQuery(
        "edge type '$type' is not registered with this GraphDataModel",
      );
    }
    return entity;
  }

  /// All registered node entities, keyed by Dart type.
  Map<Type, GraphNodeEntity> get nodeEntities => Map.unmodifiable(_nodes);

  /// All registered edge entities, keyed by Dart type.
  Map<Type, GraphEdgeEntity> get edgeEntities => Map.unmodifiable(_edges);

  /// True iff [type] has been registered as either a node or an edge.
  bool isRegistered(Type type) =>
      _nodes.containsKey(type) || _edges.containsKey(type);
}
