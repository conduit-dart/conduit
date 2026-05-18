# conduit_graph_neo4j

Neo4j (Bolt v4.x) backend for [`conduit_graph`](../graph) — the type-system foundation for the Conduit Object-Graph Mapper.

This package implements `GraphPersistentStore` against a self-contained Bolt v4.x client. It does not depend on any third-party Bolt or Neo4j driver — the only Dart Neo4j drivers on pub.dev today (`dart_neo4j`, `dart_bolt`) are GPL-3.0, which is incompatible with Conduit's BSD-3-Clause license. The Bolt client lives entirely in `lib/src/bolt/`.

## What this ships

- **`Neo4jPersistentStore`** — a drop-in `GraphPersistentStore`. Constructor takes a `bolt://host:port` URI plus optional basic-auth credentials and target database.
- **Cypher emitter** — lowers the dialect-agnostic `GraphPattern` / `GraphQuery` AST shipped by `conduit_graph` into a Cypher string + a parameter map. Filter values are always bound through `$pN` parameters, never interpolated.
- **Bolt v4.x client** — `BoltConnection` / `BoltTransaction` / `BoltResult`, plus `PackStreamEncoder` / `PackStreamDecoder`. Public surface for users who need raw access; most callers will go through `Neo4jPersistentStore`.

## Worked example

```dart
import 'package:conduit_graph/conduit_graph.dart';
import 'package:conduit_graph_neo4j/conduit_graph_neo4j.dart';

class User extends GraphNode<User> {
  User({String? name, int? age}) : super(labels: [GraphLabel('User')]) {
    if (name != null) this['name'] = name;
    if (age != null) this['age'] = age;
  }
}

class Friend extends GraphEdge<User, User> {
  Friend({required super.from, required super.to})
      : super(label: const GraphLabel.unchecked('Friend'));
}

Future<void> main() async {
  final store = Neo4jPersistentStore(
    Uri.parse('bolt://localhost:7687'),
    username: 'neo4j',
    password: 'secret',
  )..registerNodeFactory<User>(User.new);

  final ctx = GraphContext.withTypes(
    persistentStore: store,
    registerNodes: (m) => m.registerNode<User>(),
    registerEdges: (m) => m.registerEdge<Friend, User, User>(),
  );
  store.bindDataModel(ctx.dataModel);

  // Create + edge.
  final alice = await ctx.insertNode(User(name: 'alice', age: 30));
  final bob = await ctx.insertNode(User(name: 'bob', age: 28));
  await ctx.insertEdge(Friend(from: alice, to: bob));

  // Closure-built pattern query.
  final adultFriends = await ctx.graph
      .match<User>(
        (u) => u.connectedTo<Friend>(toLabel: GraphLabel('User')),
      )
      .where((u) => u['age'].greaterThan(21))
      .fetch();

  // Always-on raw-Cypher escape hatch.
  final rows = await ctx.cypher(
    r'MATCH (u:User)-[:Friend]->(o:User) WHERE u.age > $min RETURN u, o',
    params: {'min': 21},
  );

  await ctx.close();
}
```

## Hydration: registering node factories

`GraphPersistentStore.match` / `executeQuery` need to construct typed `GraphNode<T>` instances when reading rows back. `conduit_graph` does not (yet) carry a no-arg factory in its data model, so this backend asks you to register one explicitly:

```dart
store.registerNodeFactory<User>(User.new);
```

You only need to do this for node types you intend to *read*. `cypher()` returns raw `Map<String, Object?>` rows and does not require a factory.

## Known limitations (v0)

- **Single connection, no pool.** Every store instance owns one TCP socket; concurrent calls serialize through it. Pool work is queued for a later phase.
- **`bolt://` only.** No clustering / routing (`neo4j://`), no `bolt+s://` TLS. If you need encryption today, terminate it at a sidecar (e.g. an SSH tunnel).
- **No causal consistency.** Bookmarks are not implemented; consistency is "same connection" only.
- **No migration system.** `conduit_graph` does not ship a `Schema*` analogue, so there is nothing to lower here. Use raw Cypher scripts.
- **No streaming pipelines.** Each statement is a strict `RUN` + `PULL` round-trip; multiple concurrent in-flight RUNs are not supported.
- **Bolt 4.x only.** We negotiate one of `4.4 / 4.3 / 4.1 / 4.0`. Bolt 5.x adds a separate LOGON/LOGOFF auth dance which is out of scope for v0.
- **No DateTime structs.** `DateTime` parameters are auto-marshaled as ISO-8601 strings; the server's temporal struct types are surfaced on read as raw `BoltStructure` values for the caller to map.
- **One filter anchor.** The `where(...)` closure currently filters against the pattern's anchor node only. Multi-hop filtering (e.g. constraints on a terminal node) needs DSL extension upstream in `conduit_graph` first.

All of these are documented as future work.

## Bolt protocol scope

The Bolt client implements the subset listed at the top of `lib/src/bolt/bolt_connection.dart`:

- TCP connect + handshake (magic preamble, four version offers)
- Chunked message framing (2-byte size + body, terminated by `00 00`)
- PackStream encode/decode for Null, Bool, Int (TINY/8/16/32/64), Float, String, List, Dictionary, Structure
- Messages: HELLO, RUN, PULL, BEGIN, COMMIT, ROLLBACK, RESET, GOODBYE on the request side; SUCCESS, RECORD, FAILURE, IGNORED on the summary side

## Running the integration tests

```bash
docker run --rm -d \
  -p 7687:7687 -p 7474:7474 \
  -e NEO4J_AUTH=neo4j/testpass \
  --name conduit-graph-neo4j-it \
  neo4j:5.20

export CONDUIT_NEO4J_AVAILABLE=1
export CONDUIT_NEO4J_USER=neo4j
export CONDUIT_NEO4J_PASS=testpass

dart test test/integration_test.dart
```

Without `CONDUIT_NEO4J_AVAILABLE`, the integration tests are skipped (they show as `skip:` in the test runner output) and `dart test` stays green for unit-only runs.
