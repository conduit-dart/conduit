import '../types/graph_label.dart';
import '../types/graph_node.dart';
import '../types/graph_relationship_direction.dart';

/// A node-shaped step inside a [GraphPattern].
///
/// Wraps the user's anchor variable and any chained relationship
/// hops emitted by [GraphPatternNode.connectedTo].
class GraphPatternNode<N extends GraphNode<N>> {
  GraphPatternNode({
    required this.variable,
    required this.label,
    this.nodeType,
  });

  /// The query-binding variable name (e.g. `u` in `(u:User)`).
  final String variable;

  /// The label this pattern step matches.
  final GraphLabel label;

  /// The Dart [Type] this step resolves to, when known. The Neo4j
  /// backend uses this to map results back into typed nodes.
  final Type? nodeType;

  /// Outgoing/incoming/undirected hops captured on this node.
  final List<GraphPatternRelationship> _relationships = [];

  List<GraphPatternRelationship> get relationships =>
      List.unmodifiable(_relationships);

  /// Records a relationship from this node to a node of label
  /// [edgeLabel] (defaults to the runtime [Type] name of [E]).
  ///
  /// `connectedTo<Friend>(direction: outgoing)` captures the hop
  /// `(u)-[:Friend]->(:?)`. The terminal node label / type is filled
  /// in by the backend renderer when it lowers the pattern.
  GraphPatternNode<N> connectedTo<E>({
    GraphRelationshipDirection direction =
        GraphRelationshipDirection.outgoing,
    GraphLabel? edgeLabel,
    Type? toType,
    GraphLabel? toLabel,
    String? toVariable,
  }) {
    _relationships.add(
      GraphPatternRelationship(
        edgeLabel: edgeLabel ?? GraphLabel(E.toString()),
        edgeType: E,
        direction: direction,
        toLabel: toLabel,
        toType: toType,
        toVariable: toVariable,
      ),
    );
    return this;
  }

  @override
  String toString() {
    final rels = _relationships.isEmpty ? '' : ', $_relationships';
    return 'GraphPatternNode($variable:${label.name}$rels)';
  }
}

/// A relationship hop captured inside a [GraphPatternNode].
class GraphPatternRelationship {
  const GraphPatternRelationship({
    required this.edgeLabel,
    required this.direction,
    this.edgeType,
    this.toLabel,
    this.toType,
    this.toVariable,
  });

  /// Edge label (e.g. `Friend`).
  final GraphLabel edgeLabel;

  /// The Dart edge [Type], when known.
  final Type? edgeType;

  /// Direction of this hop.
  final GraphRelationshipDirection direction;

  /// Terminal node label, when the user pinned one.
  final GraphLabel? toLabel;

  /// Terminal node Dart type, when the user pinned one.
  final Type? toType;

  /// Terminal node binding variable, when the user pinned one.
  final String? toVariable;

  @override
  String toString() {
    return 'GraphPatternRelationship'
        '(${direction.name}, '
        ':${edgeLabel.name}'
        '${toLabel == null ? '' : ' -> :${toLabel!.name}'})';
  }
}

/// Closure-built node pattern.
///
/// Cypher-shaped: a single anchor node with zero or more chained
/// relationship hops. Compiles to a structured AST — the renderer for
/// each backend turns it into the target query string.
///
/// This type is the **only** public surface for building a pattern
/// from a closure; backends consume its [root].
class GraphPattern<N extends GraphNode<N>> {
  GraphPattern._(this.root);

  /// Build a pattern by calling [builder] with a fresh
  /// [GraphPatternNode] anchored on label [label] (or `T.toString()`).
  factory GraphPattern.build(
    void Function(GraphPatternNode<N>) builder, {
    String variable = 'n',
    GraphLabel? label,
    Type? nodeType,
  }) {
    final root = GraphPatternNode<N>(
      variable: variable,
      label: label ?? GraphLabel(N.toString()),
      nodeType: nodeType ?? N,
    );
    builder(root);
    return GraphPattern._(root);
  }

  /// The anchor node of the pattern.
  final GraphPatternNode<N> root;

  @override
  String toString() => 'GraphPattern(root=$root)';
}
