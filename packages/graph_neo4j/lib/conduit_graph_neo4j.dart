/// Neo4j (Bolt v4.x) backend for the `conduit_graph` type system.
///
/// Implements `GraphPersistentStore` against a self-contained Bolt
/// client — no GPL `dart_neo4j` dep, no third-party Bolt library
/// (we examined `dart_neo4j` 1.2.1 and `dart_bolt` 1.2.1; both are
/// GPL-3.0 and incompatible with Conduit's BSD-3-Clause licensing).
///
/// Surface
/// -------
/// - [Neo4jPersistentStore] — drop-in `GraphPersistentStore` impl.
///   Construct with a `bolt://host:port` URI; supply
///   username/password for basic-auth, or omit them for an
///   anonymous connection.
///
/// Bolt protocol primitives are also re-exported (under
/// `src/bolt/bolt.dart`) for callers that need raw access — most
/// users will go through `Neo4jPersistentStore` and the closure DSL
/// from `conduit_graph` instead.
library;

export 'src/cypher_emitter.dart'
    show CypherEmitter, CypherStatement, emitPattern, emitQuery;
export 'src/neo4j_persistent_store.dart' show Neo4jPersistentStore;

// Bolt internals (advanced use).
export 'src/bolt/bolt.dart';
