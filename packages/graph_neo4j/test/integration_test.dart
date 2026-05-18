// Integration tests against a real Neo4j running on bolt://localhost:7687.
//
// Gated on the CONDUIT_NEO4J_AVAILABLE env var; skipped otherwise.
// `dart test` (no env) will still load this file, but every test
// inside will be marked `skip:` so the suite turns green without a
// running server.
//
// To run locally:
//
//     docker run --rm -p 7687:7687 -p 7474:7474 \
//       -e NEO4J_AUTH=neo4j/testpass \
//       neo4j:5.20
//     export CONDUIT_NEO4J_AVAILABLE=1
//     export CONDUIT_NEO4J_USER=neo4j
//     export CONDUIT_NEO4J_PASS=testpass
//     dart test test/integration_test.dart

import 'dart:io';

import 'package:conduit_graph/conduit_graph.dart';
import 'package:conduit_graph_neo4j/conduit_graph_neo4j.dart';
import 'package:test/test.dart';

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

void main() {
  final available = Platform.environment['CONDUIT_NEO4J_AVAILABLE'];
  final skip = (available == null || available.isEmpty)
      ? 'Set CONDUIT_NEO4J_AVAILABLE=1 to run; needs a Bolt-reachable Neo4j '
          'on bolt://localhost:7687.'
      : null;

  late Neo4jPersistentStore store;
  late GraphContext ctx;

  setUp(() async {
    if (skip != null) return;
    final user = Platform.environment['CONDUIT_NEO4J_USER'];
    final pass = Platform.environment['CONDUIT_NEO4J_PASS'];
    final hostPort =
        Platform.environment['CONDUIT_NEO4J_URI'] ?? 'bolt://localhost:7687';
    store = Neo4jPersistentStore(
      Uri.parse(hostPort),
      username: user,
      password: pass,
    )..registerNodeFactory<User>(User.new);
    ctx = GraphContext.withTypes(
      persistentStore: store,
      registerNodes: (m) => m.registerNode<User>(),
      registerEdges: (m) => m.registerEdge<Friend, User, User>(),
    );
    store.bindDataModel(ctx.dataModel);
    // Clean any state from previous runs against the same DB.
    await store.cypher(
      'MATCH (n:User) WHERE n.name STARTS WITH \$prefix DETACH DELETE n',
      params: {'prefix': '__conduit_test_'},
    );
  });

  tearDown(() async {
    if (skip != null) return;
    await store.cypher(
      'MATCH (n:User) WHERE n.name STARTS WITH \$prefix DETACH DELETE n',
      params: {'prefix': '__conduit_test_'},
    );
    await ctx.close();
  });

  test('create + match round-trips a single node', () async {
    final created = await ctx.insertNode(
      User(name: '__conduit_test_alice', age: 30),
    );
    expect(created.id, isNotNull);

    final found = await ctx.cypher(
      'MATCH (n:User {name: \$name}) RETURN n',
      params: {'name': '__conduit_test_alice'},
    );
    expect(found, hasLength(1));
  }, skip: skip);

  test('create two nodes + edge, then traverse', () async {
    final alice = await ctx.insertNode(User(name: '__conduit_test_alice'));
    final bob = await ctx.insertNode(User(name: '__conduit_test_bob'));
    await ctx.insertEdge(Friend(from: alice, to: bob));

    final friends = await ctx.traverse<User>(alice, Friend);
    expect(friends, hasLength(1));
    expect(friends.first['name'], '__conduit_test_bob');
  }, skip: skip);

  test('cypher escape hatch with parameters', () async {
    await ctx.insertNode(User(name: '__conduit_test_carol', age: 42));
    final rows = await ctx.cypher(
      'MATCH (n:User) WHERE n.age > \$min AND n.name STARTS WITH \$prefix '
      'RETURN n.name AS name, n.age AS age',
      params: {'min': 30, 'prefix': '__conduit_test_'},
    );
    expect(rows, isNotEmpty);
    expect(rows.first.containsKey('name'), isTrue);
  }, skip: skip);
}
