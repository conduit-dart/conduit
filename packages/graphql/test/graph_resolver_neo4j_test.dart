// Integration tests against a real Neo4j running on bolt://localhost:7687.
//
// Gated on the CONDUIT_NEO4J_AVAILABLE env var (matching the
// convention in `packages/graph_neo4j/test/integration_test.dart`).
// `dart test` (no env) loads the file but every test is marked
// `skip:` so the suite turns green without a running server.
//
// To run locally:
//
//     docker run --rm -p 7687:7687 -p 7474:7474 \
//       -e NEO4J_AUTH=neo4j/testpass \
//       neo4j:5.20
//     export CONDUIT_NEO4J_AVAILABLE=1
//     export CONDUIT_NEO4J_USER=neo4j
//     export CONDUIT_NEO4J_PASS=testpass
//     dart test test/graph_resolver_neo4j_test.dart
//
// Tags: integration. CI excludes integration by default.

@Tags(['integration'])
library;

import 'dart:io';

import 'package:conduit_graph/conduit_graph.dart';
import 'package:conduit_graph_neo4j/conduit_graph_neo4j.dart';
import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:test/test.dart';

import 'fixtures/social_graph.dart';

void main() {
  final available = Platform.environment['CONDUIT_NEO4J_AVAILABLE'];
  final skip = (available == null || available.isEmpty)
      ? 'Set CONDUIT_NEO4J_AVAILABLE=1 to run; needs a Bolt-reachable Neo4j '
          'on bolt://localhost:7687.'
      : null;

  late Neo4jPersistentStore store;
  late GraphContext context;
  late GraphQLSchema schema;
  late GraphQL engine;

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
    )
      ..registerNodeFactory<User>(User.new)
      ..registerNodeFactory<Post>(Post.new);

    final dataModel = buildSocialGraphDataModel();
    context = GraphContext(dataModel, store);
    store.bindDataModel(dataModel);

    // Clean any state from previous runs against the same DB.
    await store.cypher(
      'MATCH (n) WHERE n.name STARTS WITH \$prefix '
      'OR n.title STARTS WITH \$prefix DETACH DELETE n',
      params: {'prefix': '__conduit_g4_test_'},
    );

    final factory = GraphResolverFactory(context)
      ..registerNodeType<User>()
      ..registerNodeType<Post>();

    schema = SchemaBuilder().fromGraphDataModel(
      dataModel,
      config: buildSocialGraphSchemaConfig(exposeEdges: true),
      resolverFactory: factory,
    );
    engine = GraphQL(schema);
  });

  tearDown(() async {
    if (skip != null) return;
    await store.cypher(
      'MATCH (n) WHERE n.name STARTS WITH \$prefix '
      'OR n.title STARTS WITH \$prefix DETACH DELETE n',
      params: {'prefix': '__conduit_g4_test_'},
    );
    await context.close();
  });

  test(
    '`{ users { id name } }` returns nodes from a seeded fixture',
    () async {
      final alice = User()..['name'] = '__conduit_g4_test_alice';
      final bob = User()..['name'] = '__conduit_g4_test_bob';
      await context.insertNode(alice);
      await context.insertNode(bob);

      final result = await engine.parseAndExecute(
        '{ users { id name } }',
      );
      expect(result, isA<Map>());
      final data = (result as Map)['users'];
      expect(data, isA<List>());
      // Filter out any preexisting User nodes that don't match the
      // test prefix (the cleanup hook only catches our own prefix).
      final ours = (data as List)
          .where((row) => (row as Map)['name']
              .toString()
              .startsWith('__conduit_g4_test_'))
          .toList();
      expect(ours, hasLength(2));
      final names = ours
          .map((row) => (row as Map)['name'] as String)
          .toSet();
      expect(
        names,
        equals({'__conduit_g4_test_alice', '__conduit_g4_test_bob'}),
      );
    },
    skip: skip,
  );

  test(
    'traversal resolves connected nodes via `friends` field',
    () async {
      final alice = User()..['name'] = '__conduit_g4_test_alice';
      final bob = User()..['name'] = '__conduit_g4_test_bob';
      await context.insertNode(alice);
      await context.insertNode(bob);
      await context.insertEdge(Friend(from: alice, to: bob));

      // The schema's `User.users` field is the User -[Friend]-> User
      // traversal (named after the destination plural). We query by
      // id to start at alice; then walk the friend edge.
      final result = await engine.parseAndExecute(
        'query Q(\$id: String!) {'
        ' user(id: \$id) {'
        '  ... on User { name users { name } }'
        ' }'
        '}',
        variableValues: {'id': '${alice.id}'},
      );
      expect(result, isA<Map>());
      final user = (result as Map)['user'] as Map;
      expect(user['name'], equals('__conduit_g4_test_alice'));
      final friends = user['users'] as List;
      expect(friends, hasLength(1));
      expect(
        (friends.first as Map)['name'],
        equals('__conduit_g4_test_bob'),
      );
    },
    skip: skip,
  );

  test(
    'edge connection (when exposed) surfaces edge properties via friends list',
    () async {
      final alice = User()..['name'] = '__conduit_g4_test_alice';
      final bob = User()..['name'] = '__conduit_g4_test_bob';
      await context.insertNode(alice);
      await context.insertNode(bob);
      final friend = Friend(from: alice, to: bob)
        ..since = DateTime.utc(2024, 1, 15);
      await context.insertEdge(friend);

      // Query the top-level `friends` Query-root edge list.
      final result = await engine.parseAndExecute(
        '{ friends { id since from { id } to { id } } }',
      );
      expect(result, isA<Map>());
      final edges = ((result as Map)['friends'] as List).cast<Map>();
      // Filter to ones that involve our prefixed nodes.
      final ours = edges.where((e) {
        final fromId = ((e['from'] as Map)['id']).toString();
        final toId = ((e['to'] as Map)['id']).toString();
        return fromId == '${alice.id}' && toId == '${bob.id}';
      }).toList();
      expect(ours, isNotEmpty);
      expect(ours.first['since'], isNotNull);
    },
    skip: skip,
  );
}
