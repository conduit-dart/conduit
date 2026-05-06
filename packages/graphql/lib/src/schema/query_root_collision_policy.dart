/// Policy for resolving query-root field-name collisions when
/// [SchemaBuilder.fromPersistence] unifies a relational schema with
/// a graph schema.
///
/// G4 explicitly raised a [StateError] when graph + relational walkers
/// emitted the same name in the same builder. G5 keeps that strict
/// behavior as the default but lets cross-source callers opt in to a
/// rename strategy via this enum.
library;

/// What to do when a graph entity and a relational entity both want
/// the same query-root field name.
enum QueryRootCollisionPolicy {
  /// Throw a [StateError] at schema build time. Default — preserves
  /// G4's existing behavior; calling code must opt into a softer mode.
  error,

  /// Prefix graph entities with `g_` when their name collides with a
  /// relational entity. Relational entities keep their original name.
  prefixGraph,

  /// Prefix relational entities with `r_` when their name collides
  /// with a graph entity. Graph entities keep their original name.
  prefixRelational,
}
