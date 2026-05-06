/// Direction of a graph relationship in pattern queries and traversals.
///
/// Cypher equivalents:
///
/// - [outgoing]   — `(a)-[:REL]->(b)`
/// - [incoming]   — `(a)<-[:REL]-(b)`
/// - [undirected] — `(a)-[:REL]-(b)`
enum GraphRelationshipDirection { outgoing, incoming, undirected }
