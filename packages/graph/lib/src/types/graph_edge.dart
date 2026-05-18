import 'graph_backing.dart';
import 'graph_label.dart';
import 'graph_node.dart';

/// A typed graph edge — first-class value with its own property bag.
///
/// **Edge-properties are the reason this is a separate type system.**
/// Foreign-key rows in a SQL ORM cannot represent properties on the
/// relationship itself; graph databases can, and applications routinely
/// rely on it (e.g. `(:User)-[:Friend {since: 2024-01-15}]->(:User)`).
///
/// Generic parameters are the **node types**, not labels — so the
/// compiler enforces that you wire endpoints of the right shape:
///
/// ```dart
/// class Friend extends GraphEdge<User, User> {
///   Friend({required User from, required User to})
///       : super(label: GraphLabel('Friend'), from: from, to: to);
///
///   DateTime get since => this['since'] as DateTime;
///   set since(DateTime v) => this['since'] = v;
/// }
///
/// // Compile-time error: Group is not a User.
/// // Friend(from: someGroup, to: someUser);
/// ```
///
/// An edge carries a single label (graph DBs typically don't allow
/// multi-label edges, in contrast to nodes) and a [GraphBacking] for
/// its properties.
abstract class GraphEdge<From extends GraphNode<From>,
    To extends GraphNode<To>> {
  GraphEdge({
    required this.label,
    required this.from,
    required this.to,
    GraphBacking? backing,
    this.id,
  }) : backing = backing ?? GraphMapBacking();

  /// The edge label / relationship type.
  final GraphLabel label;

  /// The source node.
  final From from;

  /// The target node.
  final To to;

  /// The property backing — read/write goes through this.
  final GraphBacking backing;

  /// The store-assigned id of this edge, or `null` if it has not been
  /// persisted. Backends are responsible for setting this on
  /// `createEdge`.
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

  /// Snapshot of this edge as a plain map: `{ id, label, from, to,
  /// properties }`. Convenience for serialization / debugging.
  Map<String, Object?> asMap() => <String, Object?>{
        if (id != null) 'id': id,
        'label': label.name,
        'from': from.id,
        'to': to.id,
        'properties': Map<String, Object?>.from(backing.contents),
      };

  @override
  String toString() => '$runtimeType(${from.runtimeType}'
      '-[:${label.name}]->${to.runtimeType}, id=$id, '
      'properties=${backing.contents})';
}
