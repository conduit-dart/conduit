import '../query/graph_pattern.dart';
import '../query/graph_query.dart';
import '../types/graph_edge.dart';
import '../types/graph_node.dart';
import '../types/graph_relationship_direction.dart';

/// Backend-agnostic persistence contract for graph data.
///
/// **Not** a subclass of conduit core's `PersistentStore` — this is a
/// parallel hierarchy. The SQL `PersistentStore` is bound to columns,
/// foreign keys, and `QueryPredicate.format` strings; none of that
/// vocabulary fits a graph backend cleanly. Forcing inheritance would
/// produce a graph adapter that pretends to be SQL.
///
/// In v0 the only backing implementation in the wild is the upcoming
/// Neo4j backend (see Phase 6b). The Cypher escape hatch ([cypher])
/// is intentionally surfaced here from day one so users are never
/// boxed in by the closure DSL.
abstract class GraphPersistentStore {
  /// Pattern-based read.
  ///
  /// Implementations should accept a [GraphPattern] built via the
  /// `GraphContext.graph.match()` helpers.
  Future<List<N>> match<N extends GraphNode<N>>(GraphPattern<N> pattern);

  /// Execute a fully-built [GraphQuery] (pattern + where/limit/order).
  ///
  /// `GraphQuery.fetch()` delegates here.
  Future<List<N>> executeQuery<N extends GraphNode<N>>(GraphQuery<N> query);

  /// Persist a node. The store is responsible for assigning [GraphNode.id].
  Future<N> create<N extends GraphNode<N>>(N node);

  /// Persist an edge. The store is responsible for assigning
  /// [GraphEdge.id]. Both endpoints must already exist in the store
  /// (their `id` fields must be set) — implementations should throw
  /// `GraphNotFoundError` otherwise.
  ///
  /// `E` is left as a single generic that defaults to the runtime
  /// type of [edge]; the concrete `From` / `To` of the edge are
  /// available via `edge.from` and `edge.to` if the backend needs
  /// them. We deliberately do **not** declare a three-parameter
  /// `<E extends GraphEdge<From, To>, From, To>` signature here
  /// because Dart cannot infer all three from a single argument
  /// without an explicit type list at every call site.
  Future<E> createEdge<E extends GraphEdge<dynamic, dynamic>>(E edge);

  /// Walk outgoing/incoming edges of a particular kind from [from]
  /// and return the nodes on the far side.
  Future<List<N>> traverse<N extends GraphNode<N>>(
    GraphNode<dynamic> from,
    Type edgeKind, {
    GraphRelationshipDirection direction =
        GraphRelationshipDirection.outgoing,
  });

  /// **Always-on raw-Cypher escape hatch.**
  ///
  /// The closure DSL won't cover everything (recursive paths,
  /// procedure calls, vendor extensions). Surfacing this from day one
  /// keeps users from hitting a wall — they can drop into raw query
  /// code without forking the framework.
  ///
  /// [params] are passed through as named bind parameters. Returned
  /// rows are unbound `Map<String, Object?>` records; mapping back
  /// into typed nodes is the caller's responsibility.
  Future<List<Map<String, Object?>>> cypher(
    String rawQuery, {
    Map<String, Object?> params = const {},
  });

  /// Close the underlying connection / driver. Must be safe to call
  /// more than once.
  Future<void> close();
}
