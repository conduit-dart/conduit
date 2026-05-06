// Pure-Dart tests for `Neo4jPersistentStore` — no Neo4j required.
//
// Exercises the surfaces that don't need a live Bolt connection:
// constructor validation, factory registration / lookup error paths,
// and the data-model binding contract.
//
// The end-to-end exercise (CREATE/MATCH/traverse round-trips) lives in
// `integration_test.dart`, gated on CONDUIT_NEO4J_AVAILABLE.

import 'package:conduit_graph/conduit_graph.dart';
import 'package:conduit_graph_neo4j/conduit_graph_neo4j.dart';
import 'package:test/test.dart';

class User extends GraphNode<User> {
  User() : super(labels: [GraphLabel('User')]);
}

void main() {
  group('Neo4jPersistentStore — constructor validation', () {
    test('rejects non-bolt URI scheme', () {
      expect(
        () => Neo4jPersistentStore(Uri.parse('neo4j://localhost:7687')),
        throwsArgumentError,
      );
      expect(
        () => Neo4jPersistentStore(Uri.parse('http://localhost:7687')),
        throwsArgumentError,
      );
    });

    test('accepts a bolt:// URI without auth', () {
      final store =
          Neo4jPersistentStore(Uri.parse('bolt://localhost:7687'));
      expect(store.username, isNull);
      expect(store.password, isNull);
      expect(store.database, 'neo4j');
    });

    test('honors username/password/database parameters', () {
      final store = Neo4jPersistentStore(
        Uri.parse('bolt://localhost:7687'),
        username: 'neo4j',
        password: 'secret',
        database: 'social',
      );
      expect(store.username, 'neo4j');
      expect(store.password, 'secret');
      expect(store.database, 'social');
    });
  });

  group('Neo4jPersistentStore — data-model binding', () {
    test('bindDataModel attaches a model', () {
      final store =
          Neo4jPersistentStore(Uri.parse('bolt://localhost:7687'));
      expect(store.dataModel, isNull);
      final model = GraphDataModel();
      store.bindDataModel(model);
      expect(store.dataModel, same(model));
    });

    test('rebinding the same model is a no-op', () {
      final model = GraphDataModel();
      final store = Neo4jPersistentStore(
        Uri.parse('bolt://localhost:7687'),
        dataModel: model,
      );
      store.bindDataModel(model);
      expect(store.dataModel, same(model));
    });

    test('binding a different model throws', () {
      final store = Neo4jPersistentStore(
        Uri.parse('bolt://localhost:7687'),
        dataModel: GraphDataModel(),
      );
      expect(
        () => store.bindDataModel(GraphDataModel()),
        throwsStateError,
      );
    });
  });

  group('Neo4jPersistentStore — factory registry', () {
    test('registerNodeFactory accepts a typed factory', () {
      final store =
          Neo4jPersistentStore(Uri.parse('bolt://localhost:7687'));
      // Just exercise the registration call — the read path that
      // would *use* the factory needs a live Bolt connection, which
      // is covered by the integration tests.
      store.registerNodeFactory<User>(User.new);
      // No assertion needed; absence of an exception is the contract.
      expect(store, isNotNull);
    });
  });
}
