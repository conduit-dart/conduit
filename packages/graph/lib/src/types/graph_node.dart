import 'graph_backing.dart';
import 'graph_label.dart';

/// A graph node — analogue of conduit core's `ManagedObject<T>`.
///
/// **Properties only, no foreign keys.** Edges are first-class values
/// (see `GraphEdge`); a node never embeds a reference to another node.
/// This is the load-bearing distinction from the SQL ORM and the
/// reason conduit_graph is a parallel hierarchy rather than an adapter
/// over `ManagedObject`.
///
/// Each node carries:
///
/// - a [labels] list — multi-label nodes are first-class in Neo4j
/// - a [backing] — pluggable property storage (see [GraphBacking]);
///   the default is an in-memory [GraphMapBacking]
///
/// User code subclasses this for each node type:
///
/// ```dart
/// class User extends GraphNode<User> {
///   User() : super(labels: [GraphLabel('User')]);
///
///   String get name => this['name'] as String;
///   set name(String v) => this['name'] = v;
///
///   int get age => this['age'] as int;
///   set age(int v) => this['age'] = v;
/// }
/// ```
///
/// The generic `T` lets the query DSL (`GraphQuery<T>`) carry the
/// concrete node type through builder calls, the same way
/// `ManagedObject<T>` flows through `Query<T>`.
abstract class GraphNode<T extends GraphNode<T>> {
  GraphNode({
    required List<GraphLabel> labels,
    GraphBacking? backing,
    this.id,
  })  : labels = List.unmodifiable(labels),
        backing = backing ?? GraphMapBacking() {
    if (labels.isEmpty) {
      throw ArgumentError.value(
        labels,
        'labels',
        'a graph node must declare at least one label',
      );
    }
  }

  /// The labels attached to this node, in declaration order.
  final List<GraphLabel> labels;

  /// The property backing — read/write goes through this.
  final GraphBacking backing;

  /// The store-assigned id of this node, or `null` if it has not been
  /// persisted. Backends are responsible for setting this on `create`.
  Object? id;

  /// Convenience accessor — same as `backing.valueForProperty(name)`.
  Object? operator [](String name) => backing.valueForProperty(name);

  /// Convenience setter — same as `backing.setValueForProperty(name,
  /// value)`.
  void operator []=(String name, Object? value) =>
      backing.setValueForProperty(name, value);

  /// True iff [name] is present in the property bag.
  bool hasProperty(String name) => backing.hasProperty(name);

  /// Removes [name] from the property bag. Returns the prior value, if any.
  Object? removeProperty(String name) => backing.removeProperty(name);

  /// A read-only view of all properties.
  Map<String, Object?> get properties =>
      Map.unmodifiable(backing.contents);

  /// Replaces all properties with [values]. Existing keys not present
  /// in [values] are removed.
  void readFromMap(Map<String, Object?> values) {
    final keys = backing.contents.keys.toList();
    for (final k in keys) {
      backing.removeProperty(k);
    }
    values.forEach(backing.setValueForProperty);
  }

  /// Snapshot of this node as a plain map: `{ id, labels, properties
  /// }`. Convenience for serialization / debugging.
  Map<String, Object?> asMap() => <String, Object?>{
        if (id != null) 'id': id,
        'labels': labels.map((l) => l.name).toList(growable: false),
        'properties': Map<String, Object?>.from(backing.contents),
      };

  @override
  String toString() {
    final lbls = labels.map((l) => l.name).join(':');
    return '$runtimeType($lbls, id=$id, properties=${backing.contents})';
  }
}
