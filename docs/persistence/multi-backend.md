# Multi-Backend Persistence

Conduit ships two persistence hierarchies:

- The **relational ORM** (`ManagedObject` / `ManagedContext` / `PersistentStore`) — the original Conduit ORM, with backends for Postgres, MySQL, SQLite, and CockroachDB.
- The **graph OGM** (`GraphNode` / `GraphContext` / `GraphPersistentStore`) — a parallel hierarchy in `package:conduit_graph`, with a Neo4j backend in `package:conduit_graph_neo4j`.

The two are **deliberately separate type hierarchies**. SQL columns + foreign keys + `QueryPredicate.format` strings do not map cleanly to first-class typed edges, multi-label nodes, and pattern queries. Forcing one onto the other would yield an adapter that pretends to be the other backend.

For apps that legitimately need both — a SQL-of-record domain plus a graph for relationship-heavy workloads — the `Persistence` umbrella in `package:conduit_core` is the binding object.

## When to use which

Rules of thumb, not laws:

| Workload | Pick |
| -------- | ---- |
| Tabular records with stable schema, FK joins, transactional writes | SQL |
| Reporting / aggregations, indexed lookups, OLTP-style updates | SQL |
| Authoritative source of truth for entities (users, orders, posts) | SQL |
| Multi-hop traversals (friends-of-friends, supply chain, lineage) | Graph |
| Variable-shape relationships with their own properties (typed edges) | Graph |
| Pattern matching (find subgraphs by shape) | Graph |
| Recommendations driven by graph topology (collaborative filtering, PageRank) | Graph |

A common architecture: SQL holds the canonical entities, graph holds a denormalized projection for traversal. Writes go to SQL first, then a job (outbox + worker, CDC, or eventual-consistency replicator) updates the graph. Reads pick whichever side is faster for the question being asked.

## The Persistence umbrella

```dart
import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_graph/conduit_graph.dart';
import 'package:conduit_graph_neo4j/conduit_graph_neo4j.dart';
import 'package:conduit_postgresql/conduit_postgresql.dart';

class MyChannel extends ApplicationChannel {
  @override
  Future<void> prepare() async {
    persistence = Persistence<GraphPersistentStore>(
      sql: PostgreSQLPersistentStore.fromConnectionInfo(
        'user', 'pass', 'localhost', 5432, 'mydb',
      ),
      graph: Neo4jPersistentStore(Uri.parse('bolt://localhost:7687')),
    );

    // SQL context — the helper builds and assigns it.
    attachPersistence(
      persistence! as Persistence<GraphPersistentStore>,
      sqlModel: ManagedDataModel.fromCurrentMirrorSystem(),
    );

    // Graph context — wire it directly; conduit_core does not depend
    // on conduit_graph, so the helper does not know about GraphContext.
    persistence!.graphContext = GraphContext(
      GraphDataModel()..registerNode<User>(...),
      persistence!.graph as GraphPersistentStore,
    );
  }

  @override
  Future<void> close() async {
    await persistence?.close();
    await super.close();
  }
}
```

### SQL-only

```dart
persistence = Persistence(
  sql: PostgreSQLPersistentStore.fromConnectionInfo(...),
);
attachPersistence(persistence!, sqlModel: ManagedDataModel.fromCurrentMirrorSystem());
```

`persistence!.hasGraph` is `false`; `persistence!.graph` throws `StateError`.

### Graph-only

```dart
persistence = Persistence<GraphPersistentStore>(
  graph: Neo4jPersistentStore(Uri.parse('bolt://localhost:7687')),
);
persistence!.graphContext = GraphContext(
  GraphDataModel()..registerNode<User>(...),
  persistence!.graph as GraphPersistentStore,
);
```

`persistence!.hasSql` is `false`; `persistence!.sql` throws `StateError`.

### Both

See the channel example at the top of this file.

### Capability-driven controllers

Controllers can probe configuration at runtime and degrade gracefully:

```dart
class FeedController extends ResourceController {
  FeedController(this.p);
  final Persistence<GraphPersistentStore> p;

  @Operation.get('userId')
  Future<Response> getFeed(@Bind.path('userId') int userId) async {
    final user = await p.sqlContext!.fetchObjectWithID<User>(userId);
    if (p.hasGraph) {
      // Augment with friend-of-friend recommendations.
      final recs = await (p.graphContext! as GraphContext)
          .graph
          .match<User>((u) => u.connectedTo<Friend>())
          .fetch();
      return Response.ok({'user': user, 'recs': recs});
    }
    return Response.ok({'user': user});
  }
}
```

## Cross-store queries are user code

The umbrella does not coordinate writes across backends. There is no `Persistence.transaction(...)` and there will not be one — coordinating a SQL commit with a graph commit is XA / two-phase commit territory, and faking that with a wrapper would silently lie about atomicity.

If your domain needs both writes to succeed atomically, pick a pattern:

- **Outbox table on SQL.** Write the SQL change and an outbox row in the same SQL transaction; a worker drains the outbox into the graph. Failure modes are bounded: the SQL is durable, the graph catches up.
- **CDC.** Stream the SQL WAL to a transformer that writes to the graph. Same idea, different mechanism.
- **Accept eventual consistency explicitly.** Document that the graph trails SQL by some bounded delay and design queries accordingly.

Do **not** wrap a SQL `transaction()` and a graph write in a `Future.wait` and call it transactional. It is not.

## Failure modes

### One backend partially down

Both stores are independent connections. If Postgres is healthy and Neo4j is not (or vice versa), `hasSql` / `hasGraph` are still `true` (they reflect *configuration*, not liveness). Your controllers will see connection errors at query time. Patterns:

- **Fail fast.** Let the error surface as a 5xx. Simple, easy to debug.
- **Graceful degradation.** Catch the graph error and fall back to a SQL-only response. Useful when graph data is recommend-y rather than load-bearing.
- **Health checks.** Add a `/healthz` route that pings both backends and reports per-backend status. Use it in your load balancer / orchestrator.

### Connection retry

`PersistentStore` and `GraphPersistentStore` implementations have their own connection-retry semantics. The umbrella does not impose one. Tune at the backend level (`PostgreSQLPersistentStore` connection-pool settings, `Neo4jPersistentStore` driver options).

### Shutdown ordering

`Persistence.close()` closes both stores. If one `close()` throws, the umbrella attempts the other anyway and rethrows the first error after both have been awaited. Override `ApplicationChannel.close()` and call `await persistence?.close()` before `super.close()` so connection pools drain before the message hub shuts down.

## Escape hatches

### Raw Cypher

`GraphContext.cypher(...)` (forwarded from `GraphPersistentStore.cypher`) takes raw Cypher text plus named bind parameters and returns `List<Map<String, Object?>>`. Use it for:

- Recursive paths the closure DSL does not express
- Procedure calls (`CALL apoc.*`, `CALL gds.*`)
- Vendor-specific extensions
- Performance tuning beyond what the DSL emits

```dart
final rows = await (persistence!.graphContext! as GraphContext).cypher(
  'MATCH (a:User {id: \$id})-[:KNOWS*1..3]-(b:User) RETURN b',
  params: {'id': 42},
);
```

### Raw SQL

`PersistentStore.execute(...)` accepts arbitrary SQL with substitution values. Same discipline applies — escape hatch, not the default path.

## What `Persistence` does not do

- Cross-backend transactionality (out of scope; see above).
- Schema management across both backends. The relational migration tooling (`conduit db`) only knows about SQL. Graph schema (constraints, indexes) is managed via the graph backend's tooling or via `cypher()` calls in startup code.
- Connection-pool sizing, retry policies, or circuit breakers. Those belong on the backend implementations.

If a future capability fits the umbrella's "single object holding both backends" charter and does not silently lie about atomicity, it is welcome. If it crosses into XA / 2PC territory, it is not.
