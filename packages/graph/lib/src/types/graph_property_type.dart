/// Storage classes for graph properties.
///
/// Analogue of conduit core's `ManagedPropertyType` — but **labeling
/// only**, not schema enforcement. Graph databases are flexible by
/// nature; this enum exists so a backend can serialize Dart values
/// faithfully (e.g. emit ISO-8601 for [datetime], JSON for [map]) and
/// so a node/edge type can self-describe its properties for codegen
/// and tooling. There is no `nullable` / `unique` / `indexed` flag set
/// — those concepts belong to a schema layer that we deliberately do
/// not ship in v0.
enum GraphPropertyType {
  /// A UTF-8 string.
  string,

  /// A 64-bit signed integer.
  integer,

  /// A 64-bit IEEE-754 double.
  double,

  /// A boolean.
  bool,

  /// A timestamp. Backends typically serialize to ISO-8601 / epoch ms.
  datetime,

  /// A homogeneous list of any of the scalar storage classes above.
  list,

  /// A string-keyed map. Backends typically serialize to JSON.
  map,
}

/// Best-effort inference of a [GraphPropertyType] from a runtime value.
///
/// Returns `null` if [value] is `null` or its runtime type is not one
/// of the supported storage classes — callers should treat that as
/// "leave the property type unspecified" rather than as a failure.
GraphPropertyType? inferGraphPropertyType(Object? value) {
  if (value == null) return null;
  if (value is String) return GraphPropertyType.string;
  if (value is bool) return GraphPropertyType.bool;
  if (value is int) return GraphPropertyType.integer;
  if (value is double) return GraphPropertyType.double;
  if (value is DateTime) return GraphPropertyType.datetime;
  if (value is List) return GraphPropertyType.list;
  if (value is Map) return GraphPropertyType.map;
  return null;
}
