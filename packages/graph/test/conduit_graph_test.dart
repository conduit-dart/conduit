import 'package:conduit_graph/conduit_graph.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test fixtures: tiny social graph (User)-[:Friend]->(User), (User)-[:Authored]->(Post).
// ---------------------------------------------------------------------------

class User extends GraphNode<User> {
  User({String? name, int? age})
      : super(labels: [GraphLabel('User')]) {
    if (name != null) this['name'] = name;
    if (age != null) this['age'] = age;
  }

  String? get name => this['name'] as String?;
  set name(String? v) => this['name'] = v;

  int? get age => this['age'] as int?;
  set age(int? v) => this['age'] = v;
}

class Post extends GraphNode<Post> {
  Post({String? title}) : super(labels: [GraphLabel('Post')]) {
    if (title != null) this['title'] = title;
  }

  String? get title => this['title'] as String?;
  set title(String? v) => this['title'] = v;
}

class Friend extends GraphEdge<User, User> {
  Friend({required super.from, required super.to, DateTime? since})
      : super(label: const GraphLabel.unchecked('Friend')) {
    if (since != null) this['since'] = since;
  }

  DateTime? get since => this['since'] as DateTime?;
  set since(DateTime? v) => this['since'] = v;
}

class Authored extends GraphEdge<User, Post> {
  Authored({required super.from, required super.to})
      : super(label: const GraphLabel.unchecked('Authored'));
}

// ---------------------------------------------------------------------------
// Fake backend — records calls so tests can assert intent without a DB.
// ---------------------------------------------------------------------------

class _FakeGraphPersistentStore implements GraphPersistentStore {
  final List<GraphPattern<dynamic>> matchCalls = [];
  final List<GraphQuery<dynamic>> executeCalls = [];
  final List<GraphNode<dynamic>> createCalls = [];
  final List<GraphEdge<dynamic, dynamic>> createEdgeCalls = [];
  final List<({String query, Map<String, Object?> params})> cypherCalls = [];
  final List<({GraphNode<dynamic> from, Type kind, GraphRelationshipDirection dir})>
      traverseCalls = [];

  // Programmable return values.
  List<GraphNode<dynamic>> matchReturn = [];
  List<GraphNode<dynamic>> executeReturn = [];
  List<GraphNode<dynamic>> traverseReturn = [];
  List<Map<String, Object?>> cypherReturn = [];

  int _nextNodeId = 1;
  int _nextEdgeId = 1;
  bool closed = false;

  @override
  Future<List<N>> match<N extends GraphNode<N>>(GraphPattern<N> pattern) async {
    matchCalls.add(pattern);
    return matchReturn.cast<N>();
  }

  @override
  Future<List<N>> executeQuery<N extends GraphNode<N>>(GraphQuery<N> query) async {
    executeCalls.add(query);
    return executeReturn.cast<N>();
  }

  @override
  Future<N> create<N extends GraphNode<N>>(N node) async {
    node.id = _nextNodeId++;
    createCalls.add(node);
    return node;
  }

  @override
  Future<E> createEdge<E extends GraphEdge<dynamic, dynamic>>(E edge) async {
    edge.id = _nextEdgeId++;
    createEdgeCalls.add(edge);
    return edge;
  }

  @override
  Future<List<N>> traverse<N extends GraphNode<N>>(
    GraphNode<dynamic> from,
    Type edgeKind, {
    GraphRelationshipDirection direction = GraphRelationshipDirection.outgoing,
  }) async {
    traverseCalls.add((from: from, kind: edgeKind, dir: direction));
    return traverseReturn.cast<N>();
  }

  @override
  Future<List<Map<String, Object?>>> cypher(
    String rawQuery, {
    Map<String, Object?> params = const {},
  }) async {
    cypherCalls.add((query: rawQuery, params: params));
    return cypherReturn;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GraphLabel', () {
    test('rejects empty names', () {
      expect(() => GraphLabel(''), throwsArgumentError);
    });

    test('equality is by name', () {
      expect(GraphLabel('User'), equals(GraphLabel('User')));
      expect(GraphLabel('User'), isNot(equals(GraphLabel('user'))));
    });
  });

  group('GraphNode', () {
    test('instantiation requires at least one label', () {
      expect(
        () => _NoLabelNode(),
        throwsArgumentError,
      );
    });

    test('property get / set go through the backing', () {
      final u = User(name: 'alice', age: 30);
      expect(u.name, 'alice');
      expect(u.age, 30);
      expect(u['name'], 'alice');

      u['email'] = 'a@example.com';
      expect(u.hasProperty('email'), isTrue);
      expect(u.removeProperty('email'), 'a@example.com');
      expect(u.hasProperty('email'), isFalse);
    });

    test('properties view is unmodifiable', () {
      final u = User(name: 'alice');
      expect(() => u.properties['name'] = 'bob', throwsUnsupportedError);
    });

    test('readFromMap replaces the entire property bag', () {
      final u = User(name: 'alice', age: 30);
      u.readFromMap({'name': 'bob'});
      expect(u.name, 'bob');
      expect(u.hasProperty('age'), isFalse);
    });

    test('asMap snapshot includes labels and properties', () {
      final u = User(name: 'alice');
      u.id = 42;
      final snap = u.asMap();
      expect(snap['id'], 42);
      expect(snap['labels'], ['User']);
      expect((snap['properties'] as Map)['name'], 'alice');
    });
  });

  group('GraphEdge', () {
    test('carries from / to / properties', () {
      final a = User(name: 'alice')..id = 1;
      final b = User(name: 'bob')..id = 2;
      final f = Friend(from: a, to: b, since: DateTime.utc(2024, 1, 15));

      expect(f.from, same(a));
      expect(f.to, same(b));
      expect(f.label, equals(GraphLabel('Friend')));
      expect(f.since, DateTime.utc(2024, 1, 15));
      expect(f['since'], isA<DateTime>());
    });

    test('endpoints are compile-time-typed by generics', () {
      // This test exists mostly as documentation; the real
      // enforcement is the fact that the next line would not compile:
      //   Friend(from: Post(), to: User());
      final a = User(name: 'a');
      final p = Post(title: 't');
      final authored = Authored(from: a, to: p);
      expect(authored.from, same(a));
      expect(authored.to, same(p));
    });
  });

  group('GraphPattern', () {
    test('builds an anchor with no relationships by default', () {
      final p = GraphPattern<User>.build((u) {}, variable: 'u');
      expect(p.root.variable, 'u');
      expect(p.root.label.name, 'User');
      expect(p.root.relationships, isEmpty);
    });

    test('connectedTo records direction and edge label', () {
      final p = GraphPattern<User>.build(
        (u) => u.connectedTo<Friend>(
          direction: GraphRelationshipDirection.outgoing,
        ),
      );
      expect(p.root.relationships, hasLength(1));
      final r = p.root.relationships.first;
      expect(r.edgeLabel.name, 'Friend');
      expect(r.edgeType, Friend);
      expect(r.direction, GraphRelationshipDirection.outgoing);
    });

    test('connectedTo can pin terminal label/type/variable', () {
      final p = GraphPattern<User>.build(
        (u) => u.connectedTo<Authored>(
          toLabel: GraphLabel('Post'),
          toType: Post,
          toVariable: 'p',
        ),
      );
      final r = p.root.relationships.first;
      expect(r.toLabel?.name, 'Post');
      expect(r.toType, Post);
      expect(r.toVariable, 'p');
    });
  });

  group('GraphQuery filter AST', () {
    test('where compiles a closure to a structured filter', () {
      final q = GraphQuery<User>(
        pattern: GraphPattern<User>.build((_) {}),
      ).where((u) => u['age'].greaterThan(21));

      final f = q.filter;
      expect(f, isA<GraphPropertyFilter>());
      final pf = f! as GraphPropertyFilter;
      expect(pf.property, 'age');
      expect(pf.operator, GraphFilterOperator.greaterThan);
      expect(pf.value, 21);
    });

    test('chained where ANDs predicates together', () {
      final q = GraphQuery<User>(pattern: GraphPattern<User>.build((_) {}))
          .where((u) => u['age'].greaterThan(21))
          .where((u) => u['name'].equalTo('alice'));

      final f = q.filter;
      expect(f, isA<GraphCompoundFilter>());
      final cf = f! as GraphCompoundFilter;
      expect(cf.combinator, GraphFilterCombinator.and);
      expect(cf.children, hasLength(2));
    });

    test('compound expressions support OR via the filter API', () {
      final q = GraphQuery<User>(pattern: GraphPattern<User>.build((_) {}))
          .where(
        (u) => u['age'].lessThan(18).or(u['age'].greaterThan(65)),
      );

      final f = q.filter;
      expect(f, isA<GraphCompoundFilter>());
      final cf = f! as GraphCompoundFilter;
      expect(cf.combinator, GraphFilterCombinator.or);
    });

    test('limitTo / offsetBy reject negatives', () {
      final q = GraphQuery<User>(pattern: GraphPattern<User>.build((_) {}));
      expect(() => q.limitTo(-1), throwsA(isA<GraphInvalidQuery>()));
      expect(() => q.offsetBy(-1), throwsA(isA<GraphInvalidQuery>()));
    });

    test('orderByProperty appends terms in order', () {
      final q = GraphQuery<User>(pattern: GraphPattern<User>.build((_) {}))
          .orderByProperty('name')
          .orderByProperty('age', direction: GraphSortDirection.descending);
      expect(q.orderBy.map((o) => o.property), ['name', 'age']);
      expect(q.orderBy.last.direction, GraphSortDirection.descending);
    });

    test('detached fetch (no executor) throws', () {
      final q = GraphQuery<User>(pattern: GraphPattern<User>.build((_) {}));
      expect(q.fetch, throwsA(isA<GraphInvalidQuery>()));
    });
  });

  group('GraphContext + GraphDataModel', () {
    test('registers node and edge types', () {
      final ctx = GraphContext.withTypes(
        persistentStore: _FakeGraphPersistentStore(),
        registerNodes: (m) {
          m.registerNode<User>();
          m.registerNode<Post>();
        },
        registerEdges: (m) {
          m.registerEdge<Friend, User, User>();
          m.registerEdge<Authored, User, Post>();
        },
      );

      expect(ctx.dataModel.isRegistered(User), isTrue);
      expect(ctx.dataModel.isRegistered(Friend), isTrue);
      expect(ctx.dataModel.nodeEntityFor(User).label.name, 'User');
      expect(ctx.dataModel.edgeEntityFor(Authored).fromType, User);
      expect(ctx.dataModel.edgeEntityFor(Authored).toType, Post);
    });

    test('looking up an unregistered type throws GraphInvalidQuery', () {
      final ctx = GraphContext.withTypes(
        persistentStore: _FakeGraphPersistentStore(),
      );
      expect(
        () => ctx.dataModel.nodeEntityFor(User),
        throwsA(isA<GraphInvalidQuery>()),
      );
    });

    test('match builds a runnable query bound to the store', () async {
      final fake = _FakeGraphPersistentStore();
      final ctx = GraphContext.withTypes(
        persistentStore: fake,
        registerNodes: (m) => m.registerNode<User>(),
      );

      fake.executeReturn = [User(name: 'alice')];

      final results = await ctx.graph
          .match<User>((u) => u.connectedTo<Friend>())
          .where((u) => u['age'].greaterThan(21))
          .fetch();

      expect(fake.executeCalls, hasLength(1));
      final q = fake.executeCalls.single as GraphQuery<User>;
      expect(q.pattern.root.label.name, 'User');
      expect(q.pattern.root.relationships.single.edgeLabel.name, 'Friend');
      expect(q.filter, isA<GraphPropertyFilter>());
      expect(results.single.name, 'alice');
    });

    test('insertNode + insertEdge round-trip through the store', () async {
      final fake = _FakeGraphPersistentStore();
      final ctx = GraphContext(GraphDataModel(), fake);

      final alice = await ctx.insertNode(User(name: 'alice'));
      final bob = await ctx.insertNode(User(name: 'bob'));
      final f = await ctx.insertEdge(Friend(from: alice, to: bob));

      expect(alice.id, 1);
      expect(bob.id, 2);
      expect(f.id, 1);
      expect(fake.createCalls, hasLength(2));
      expect(fake.createEdgeCalls.single, same(f));
    });

    test('cypher escape hatch is surfaced on context and store', () async {
      final fake = _FakeGraphPersistentStore()
        ..cypherReturn = [
          {'n.name': 'alice'}
        ];
      final ctx = GraphContext(GraphDataModel(), fake);

      final rows = await ctx.cypher(
        'MATCH (n:User) WHERE n.age > \$min RETURN n.name',
        params: {'min': 21},
      );

      expect(fake.cypherCalls.single.query, contains('MATCH (n:User)'));
      expect(fake.cypherCalls.single.params, {'min': 21});
      expect(rows.single['n.name'], 'alice');
    });

    test('traverse delegates direction + edge kind to the store', () async {
      final fake = _FakeGraphPersistentStore();
      final ctx = GraphContext(GraphDataModel(), fake);
      final alice = User(name: 'alice')..id = 1;

      await ctx.traverse<User>(alice, Friend,
          direction: GraphRelationshipDirection.incoming);

      expect(fake.traverseCalls.single.kind, Friend);
      expect(
        fake.traverseCalls.single.dir,
        GraphRelationshipDirection.incoming,
      );
    });

    test('close is delegated to the underlying store', () async {
      final fake = _FakeGraphPersistentStore();
      final ctx = GraphContext(GraphDataModel(), fake);
      await ctx.close();
      expect(fake.closed, isTrue);
    });
  });

  group('GraphPropertyType inference', () {
    test('maps common Dart values to storage classes', () {
      expect(inferGraphPropertyType('hi'), GraphPropertyType.string);
      expect(inferGraphPropertyType(true), GraphPropertyType.bool);
      expect(inferGraphPropertyType(42), GraphPropertyType.integer);
      expect(inferGraphPropertyType(3.14), GraphPropertyType.double);
      expect(inferGraphPropertyType(DateTime.now()), GraphPropertyType.datetime);
      expect(inferGraphPropertyType([1, 2]), GraphPropertyType.list);
      expect(inferGraphPropertyType({'a': 1}), GraphPropertyType.map);
      expect(inferGraphPropertyType(null), isNull);
    });
  });

  group('Errors', () {
    test('exception types are distinct GraphException subclasses', () {
      expect(GraphConnectionError('x'), isA<GraphException>());
      expect(GraphConstraintViolation('x'), isA<GraphException>());
      expect(GraphNotFoundError('x'), isA<GraphException>());
      expect(GraphInvalidQuery('x'), isA<GraphException>());
    });

    test('toString includes message and cause when present', () {
      final e = GraphConnectionError('boom', cause: 'inner');
      expect(e.toString(), contains('boom'));
      expect(e.toString(), contains('inner'));
    });
  });
}

// Helper for the "no labels" test — bypasses `User` constructor's defaulting.
class _NoLabelNode extends GraphNode<_NoLabelNode> {
  _NoLabelNode() : super(labels: const []);
}
