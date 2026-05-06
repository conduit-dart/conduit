# conduit_graph

Type-system foundation for an Object-Graph Mapper (OGM) on top of [Conduit](https://github.com/conduit-dart/conduit).

This package ships **only the type system + abstract store contract**. The Neo4j backend that consumes it is the follow-up phase (P6b) and is not part of this release.

## Why a parallel hierarchy, not a generalization of the SQL ORM

Conduit's `ManagedObject<T>`, `ManagedRelationshipType` (`hasOne` / `hasMany` / `belongsTo`), `Schema*`, and `QueryPredicate.format` are SQL-bound. Force-fitting graphs into them creates a graph adapter that pretends to be SQL — wrong abstraction. Graph backends need:

- **First-class typed edges with edge-properties.** SQL foreign keys cannot represent a property *on the relationship itself* (`(:User)-[:Friend {since: …}]->(:User)`). This is the load-bearing distinction.
- **Multi-label nodes.** First-class in Neo4j; awkward in SQL.
- **Pattern-based queries** instead of `QueryPredicate.format` strings.
- **Schemaless properties by default.** Graph DBs are flexible by nature; we deliberately do not bring `Schema*` over.

So `conduit_graph` is a **parallel** hierarchy. `GraphNode<T>` rhymes with `ManagedObject<T>` but does not inherit from it. `GraphPersistentStore` rhymes with `PersistentStore` but does not inherit from it. Apps that need both can hold a `ManagedContext` and a `GraphContext` side by side on `ApplicationChannel`.

## Four primary surfaces

| Surface | Role |
|--|--|
| `GraphNode<T>` | A node — labels + property bag, no foreign keys |
| `GraphEdge<From, To>` | A typed edge — generic-enforced endpoints, with its own property bag |
| `GraphPersistentStore` | Backend contract: `match`, `create`, `createEdge`, `traverse`, `cypher`, `close` |
| `GraphPattern` / `GraphQuery` | Closure-built, dialect-agnostic query DSL that compiles to a structured AST |

Plus `GraphContext` + `GraphDataModel` for type registration and dispatch, and `GraphException` + subclasses for errors.

## Worked example

```dart
import 'package:conduit_graph/conduit_graph.dart';

class User extends GraphNode<User> {
  User({String? name, int? age}) : super(labels: [GraphLabel('User')]) {
    if (name != null) this['name'] = name;
    if (age != null) this['age'] = age;
  }
  String? get name => this['name'] as String?;
  int? get age => this['age'] as int?;
}

class Friend extends GraphEdge<User, User> {
  Friend({required User from, required User to, DateTime? since})
      : super(label: GraphLabel('Friend'), from: from, to: to) {
    if (since != null) this['since'] = since;
  }
}

Future<void> main() async {
  final store = MyInMemoryStore(); // implements GraphPersistentStore
  final ctx = GraphContext.withTypes(
    persistentStore: store,
    registerNodes: (m) => m..registerNode<User>(),
    registerEdges: (m) => m..registerEdge<Friend, User, User>(),
  );

  final alice = await ctx.insertNode(User(name: 'alice', age: 30));
  final bob = await ctx.insertNode(User(name: 'bob', age: 28));
  await ctx.insertEdge(Friend(from: alice, to: bob, since: DateTime.now()));

  // Closure-built pattern query — Cypher-shaped, dialect-agnostic.
  final adultFriends = await ctx.graph
      .match<User>(
        (u) => u.connectedTo<Friend>(
          direction: GraphRelationshipDirection.outgoing,
        ),
      )
      .where((u) => u['age'].greaterThan(21))
      .fetch();
}
```

The `where(…)` closure compiles to a structured `GraphFilterExpression` AST — **not** a `QueryPredicate.format` string. Backends render it in their native dialect. The Neo4j backend in P6b emits `MATCH (u:User)-[:Friend]->(:User) WHERE u.age > $p0 RETURN u`.

## The `cypher()` escape hatch is mandatory

The closure DSL won't cover everything (recursive paths, vendor procedures, projections you can't express as a filter). Every `GraphPersistentStore` exposes a raw query method from day one:

```dart
final rows = await ctx.cypher(
  r'MATCH (n:User) WHERE n.age > $min RETURN n.name, n.age',
  params: {'min': 21},
);
```

This is a deliberate design choice — surfacing the escape hatch immediately keeps users from hitting a wall the first time the DSL falls short.

## What we deliberately don't ship in v0

- **No migration system.** Graph migrations are out of scope; users run raw Cypher scripts.
- **No `Schema*` enforcement.** `GraphPropertyType` labels properties for serialization but does not validate them.
- **No backend.** This package is the abstraction; bring your own `GraphPersistentStore` or wait for P6b.

## What's next

P6b — `conduit_neo4j`, a `GraphPersistentStore` backed by the Bolt protocol. It will consume the AST that `GraphQuery.fetch()` emits and round-trip results back into typed `GraphNode<T>` subclasses.
