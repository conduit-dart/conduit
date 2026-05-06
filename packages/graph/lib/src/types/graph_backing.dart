/// Pluggable storage for the property bag carried by [GraphNode] and
/// [GraphEdge].
///
/// Mirrors the role conduit core's `ManagedBacking` plays for
/// `ManagedObject`: the property reads and writes go through a backing
/// rather than directly into the node/edge subclass, so a backend can
/// swap in a different implementation (lazy, partial-projection,
/// dirty-tracking, …) without changing user code.
///
/// In v0 we ship one implementation — [GraphMapBacking], a plain
/// in-memory map. Backends are free to provide their own.
abstract class GraphBacking {
  /// The current property bag.
  ///
  /// Backends may treat this as a live view or as a snapshot — callers
  /// must not assume mutating the returned map mutates the backing.
  Map<String, Object?> get contents;

  /// Reads a property by name.
  Object? valueForProperty(String name);

  /// Writes a property by name.
  void setValueForProperty(String name, Object? value);

  /// Removes a property by name. Returns the previous value, if any.
  Object? removeProperty(String name);

  /// True iff [name] is present in the property bag.
  bool hasProperty(String name);
}

/// Plain in-memory [GraphBacking].
///
/// Default backing for newly constructed nodes and edges. Stores
/// properties in a `LinkedHashMap` so iteration order is stable
/// (insertion order) — matters for renderers that emit deterministic
/// query strings.
class GraphMapBacking implements GraphBacking {
  GraphMapBacking([Map<String, Object?>? initial])
      : _contents = <String, Object?>{...?initial};

  final Map<String, Object?> _contents;

  @override
  Map<String, Object?> get contents => _contents;

  @override
  Object? valueForProperty(String name) => _contents[name];

  @override
  void setValueForProperty(String name, Object? value) {
    _contents[name] = value;
  }

  @override
  Object? removeProperty(String name) => _contents.remove(name);

  @override
  bool hasProperty(String name) => _contents.containsKey(name);
}
