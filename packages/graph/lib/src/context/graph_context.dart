import '../query/graph_pattern.dart';
import '../query/graph_query.dart';
import '../store/graph_persistent_store.dart';
import '../types/graph_edge.dart';
import '../types/graph_label.dart';
import '../types/graph_node.dart';
import '../types/graph_relationship_direction.dart';
import 'graph_data_model.dart';

/// Top-level handle for graph-backed work.
///
/// Analogue of conduit core's `ManagedContext`: holds a backing
/// [GraphPersistentStore] plus the [GraphDataModel] registry of node
/// and edge types. Lives on `ApplicationChannel` alongside
/// `ManagedContext` for apps that use both SQL and graph storage.
class GraphContext {
  GraphContext(this.dataModel, this.persistentStore);

  /// Convenience constructor — registers types via [registerNodes] /
  /// [registerEdges] callbacks instead of pre-built [GraphDataModel].
  factory GraphContext.withTypes({
    required GraphPersistentStore persistentStore,
    void Function(GraphDataModel model)? registerNodes,
    void Function(GraphDataModel model)? registerEdges,
  }) {
    final model = GraphDataModel();
    registerNodes?.call(model);
    registerEdges?.call(model);
    return GraphContext(model, persistentStore);
  }

  final GraphDataModel dataModel;
  final GraphPersistentStore persistentStore;

  /// Entry point for the closure-built query DSL.
  ///
  /// ```dart
  /// final adults = await context.graph.match<User>(
  ///   (u) => u.connectedTo<Friend>(direction: GraphRelationshipDirection.outgoing),
  /// ).where((u) => u['age'].greaterThan(21)).fetch();
  /// ```
  late final GraphQueryEntry graph = GraphQueryEntry._(this);

  /// Persist a node through the backing store.
  Future<N> insertNode<N extends GraphNode<N>>(N node) =>
      persistentStore.create(node);

  /// Persist an edge through the backing store.
  Future<E> insertEdge<E extends GraphEdge<dynamic, dynamic>>(E edge) =>
      persistentStore.createEdge<E>(edge);

  /// Walk an edge type from [from] and return the nodes on the far side.
  Future<List<N>> traverse<N extends GraphNode<N>>(
    GraphNode<dynamic> from,
    Type edgeKind, {
    GraphRelationshipDirection direction =
        GraphRelationshipDirection.outgoing,
  }) =>
      persistentStore.traverse<N>(from, edgeKind, direction: direction);

  /// Always-on raw-Cypher escape hatch — convenience pass-through to
  /// [GraphPersistentStore.cypher].
  Future<List<Map<String, Object?>>> cypher(
    String rawQuery, {
    Map<String, Object?> params = const {},
  }) =>
      persistentStore.cypher(rawQuery, params: params);

  /// Close the backing store. Safe to call more than once.
  Future<void> close() => persistentStore.close();
}

/// Sub-handle used as the entry point for the query DSL.
///
/// Lets callers write `context.graph.match<User>(…)` (mirrors how
/// `Query<User>(context)` reads in the SQL ORM).
final class GraphQueryEntry {
  GraphQueryEntry._(this._context);

  final GraphContext _context;

  /// Build a runnable [GraphQuery] from a closure-built pattern.
  GraphQuery<N> match<N extends GraphNode<N>>(
    void Function(GraphPatternNode<N>) builder, {
    String variable = 'n',
    GraphLabel? label,
  }) {
    final entity = _context.dataModel.nodeEntities[N];
    final pattern = GraphPattern<N>.build(
      builder,
      variable: variable,
      label: label ?? entity?.label,
      nodeType: N,
    );
    return GraphQuery<N>(
      pattern: pattern,
      executor: _context.persistentStore.executeQuery,
    );
  }
}
