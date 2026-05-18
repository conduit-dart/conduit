/// A graph label.
///
/// Wraps a [String] so labels are not naked strings at API boundaries.
/// Multi-label nodes are first-class in graph databases like Neo4j; a
/// node carries a [List] of these.
///
/// Labels are case-sensitive and must be non-empty. By convention they
/// match the corresponding Dart type name (e.g. `User`, `Friend`), but
/// nothing in this package enforces that — the convention exists so a
/// renderer can derive a default label from a [Type].
final class GraphLabel {
  /// Creates a label. Throws [ArgumentError] if [name] is empty.
  GraphLabel(this.name) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'graph label must be non-empty');
    }
  }

  /// `const`-friendly alternate constructor — skips the non-empty
  /// check. Use only when the literal `name` is known to be valid at
  /// authoring time (e.g. for default labels in subclass
  /// constructors).
  const GraphLabel.unchecked(this.name);

  /// The label string as it appears in the underlying graph store.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is GraphLabel && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'GraphLabel($name)';
}
