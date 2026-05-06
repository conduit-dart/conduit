/// Type-system foundation for an Object-Graph Mapper (OGM).
///
/// `conduit_graph` is a **parallel** hierarchy to the Conduit SQL ORM
/// — not an adapter. Graph databases need:
///
/// - first-class typed edges (with their own properties — SQL FKs
///   cannot represent these)
/// - multi-label nodes
/// - pattern-based queries instead of `QueryPredicate.format` strings
/// - a schemaless property bag by default
///
/// Forcing those concepts onto `ManagedObject` would create a graph
/// adapter that pretends to be SQL. Instead, we expose:
///
/// - `GraphNode<T>` — analogue of `ManagedObject<T>`
/// - `GraphEdge<From, To>` — typed, generic-enforced endpoints, with
///   a property bag
/// - `GraphPersistentStore` — backend contract; ships an always-on
///   `cypher()` escape hatch from day one
/// - `GraphContext` + `GraphDataModel` — registry & dispatch
/// - `GraphPattern` / `GraphQuery` — closure-built, dialect-agnostic
///   query DSL that compiles to a structured AST (not a SQL
///   predicate string)
///
/// The Neo4j backend is the follow-up phase (P6b); this package ships
/// only the type system and abstract store contract.
library;

// Types
export 'src/types/graph_backing.dart';
export 'src/types/graph_edge.dart';
export 'src/types/graph_label.dart';
export 'src/types/graph_node.dart';
export 'src/types/graph_property_type.dart';
export 'src/types/graph_relationship_direction.dart';

// Errors
export 'src/errors/graph_exception.dart';

// Query DSL
export 'src/query/graph_filter.dart';
export 'src/query/graph_pattern.dart';
export 'src/query/graph_query.dart';

// Store
export 'src/store/graph_persistent_store.dart';

// Context
export 'src/context/graph_context.dart';
export 'src/context/graph_data_model.dart';
