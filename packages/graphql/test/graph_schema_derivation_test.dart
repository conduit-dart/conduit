// Structural tests for `SchemaBuilder.fromGraphDataModel`.
//
// These tests verify the *shape* of the derived graph schema — the
// node + edge type list, the union over multi-label nodes, the
// edge-property fields on the connection type, and the schemaless
// opt-in. The byte-equality golden test lives alongside in
// `graph_golden_schema_test.dart`; the Neo4j-backed integration test
// is in `graph_resolver_neo4j_test.dart`.

import 'package:conduit_graph/conduit_graph.dart';
import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:test/test.dart';

import 'fixtures/social_graph.dart';

void main() {
  late GraphDataModel dataModel;
  late GraphSchemaConfig config;
  late GraphQLSchema schema;

  setUpAll(() {
    dataModel = buildSocialGraphDataModel();
    config = buildSocialGraphSchemaConfig();
    schema = SchemaBuilder().fromGraphDataModel(dataModel, config: config);
  });

  group('social-graph fixture', () {
    test('emits 2 node ObjectTypes + 3 edge ObjectTypes plus Query', () {
      final reachable = _reachableObjectTypes(schema);
      final names = reachable.map((t) => t.name).toSet();
      // Query, User, Account (union member of UserOrAccount), Post,
      // Friend, Authored, Liked.
      expect(
        names,
        containsAll(
          {'Query', 'User', 'Account', 'Post', 'Friend', 'Authored', 'Liked'},
        ),
      );
    });

    test('Query root has list-all + by-id per node and list per edge', () {
      final query = schema.queryType!;
      final names = query.fields.map((f) => f.name).toSet();
      // 2 nodes -> 4 node-rooted fields, 3 edges -> 3 edge-rooted fields.
      expect(
        names,
        equals({
          'users', 'user', // User
          'posts', 'post', // Post
          'friends', 'authoreds', 'likeds', // Edges (naive plural)
        }),
      );
    });

    test('list-all returns the union for multi-label nodes', () {
      final query = schema.queryType!;
      final users = query.fields.firstWhere((f) => f.name == 'users');
      // [UserOrAccount!]!
      expect(users.type.toString(), equals('[UserOrAccount!]!'));
    });

    test('by-id is nullable union with non-null id arg', () {
      final query = schema.queryType!;
      final user = query.fields.firstWhere((f) => f.name == 'user');
      expect(user.type.toString(), equals('UserOrAccount'));
      expect(user.inputs, hasLength(1));
      expect(user.inputs.first.name, equals('id'));
      expect(user.inputs.first.type.toString(), equals('String!'));
    });

    test('non-multi-label node lists return their bare type', () {
      final query = schema.queryType!;
      final posts = query.fields.firstWhere((f) => f.name == 'posts');
      expect(posts.type.toString(), equals('[Post!]!'));
    });
  });

  group('multi-label union', () {
    test('User surfaces as UserOrAccount union of [User, Account]', () {
      final unions = _reachableUnionTypes(schema);
      final user = unions.firstWhere((u) => u.name == 'UserOrAccount');
      expect(
        user.possibleTypes.map((t) => t.name).toSet(),
        equals({'User', 'Account'}),
      );
    });

    test('both union members carry the same property fields', () {
      final user = _objectByName(schema, 'User');
      final account = _objectByName(schema, 'Account');
      final userFields = user.fields.map((f) => f.name).toSet();
      final accountFields = account.fields.map((f) => f.name).toSet();
      expect(userFields, equals(accountFields));
      expect(userFields, contains('name'));
      expect(userFields, contains('age'));
    });
  });

  group('edge-property fields on connection types', () {
    test('Friend exposes since: DateTime alongside from/to', () {
      final friend = _objectByName(schema, 'Friend');
      final names = friend.fields.map((f) => f.name).toSet();
      expect(names, containsAll({'id', 'since', 'from', 'to'}));
      expect(_fieldType(schema, 'Friend', 'since'), equals('DateTime'));
      expect(_fieldType(schema, 'Friend', 'from'), equals('User!'));
      expect(_fieldType(schema, 'Friend', 'to'), equals('User!'));
    });

    test('Liked exposes score: String? (bigInteger guardrail)', () {
      // GraphPropertyType.integer -> String when bigIntegerAsString is true
      // (the default). Nullable because the descriptor declares it so.
      expect(_fieldType(schema, 'Liked', 'score'), equals('String'));
    });

    test('edge with no declared properties only has id + from + to', () {
      final authored = _objectByName(schema, 'Authored');
      final names = authored.fields.map((f) => f.name).toSet();
      expect(names, equals({'id', 'from', 'to'}));
    });
  });

  group('schemaless opt-in', () {
    test('Post (opted in) carries a properties: JSON! field', () {
      final post = _objectByName(schema, 'Post');
      final names = post.fields.map((f) => f.name).toSet();
      expect(names, contains('properties'));
      expect(_fieldType(schema, 'Post', 'properties'), equals('JSON!'));
    });

    test('User (not opted in) has no properties field', () {
      final user = _objectByName(schema, 'User');
      final names = user.fields.map((f) => f.name).toSet();
      expect(names.contains('properties'), isFalse);
    });
  });

  group('built-in node fields', () {
    test('every node type has id: String! and labels: [String!]!', () {
      // Force resolution of both types so the lookups exercise the
      // reachable-types walker.
      _objectByName(schema, 'Post');
      _objectByName(schema, 'User');
      expect(_fieldType(schema, 'Post', 'id'), equals('String!'));
      expect(_fieldType(schema, 'Post', 'labels'), equals('[String!]!'));
      expect(_fieldType(schema, 'User', 'id'), equals('String!'));
      expect(_fieldType(schema, 'User', 'labels'), equals('[String!]!'));
    });
  });

  group('traversal fields', () {
    test('User exposes destination-node lists for every outgoing edge', () {
      // User -[Friend]-> User: friends-style field.
      // User -[Authored]-> Post: posts-style field.
      // User -[Liked]-> Post: collides with Authored, so disambiguated.
      final user = _objectByName(schema, 'User');
      final names = user.fields.map((f) => f.name).toSet();
      // The first User->Post traversal field claims `posts`; the
      // second gets `posts2`.
      expect(names, contains('users')); // User -> User
      expect(names, contains('posts')); // first User -> Post traversal
      expect(names, contains('posts2')); // disambiguated second one
    });

    test('Post (no outgoing edges) has no traversal fields', () {
      final post = _objectByName(schema, 'Post');
      final names = post.fields.map((f) => f.name).toSet();
      // Just the typed fields + builtins; no edge-derived list fields.
      expect(names, equals({'id', 'labels', 'title', 'properties'}));
    });

    test('exposeGraphEdgesAsConnections=true adds parallel edge-record lists',
        () {
      final wired = SchemaBuilder().fromGraphDataModel(
        dataModel,
        config: buildSocialGraphSchemaConfig(exposeEdges: true),
      );
      final user = _objectByName(wired, 'User');
      final names = user.fields.map((f) => f.name).toSet();
      expect(names, contains('friends')); // edge connection
      expect(names, contains('authoreds')); // edge connection
      expect(names, contains('likeds')); // edge connection
    });
  });

  group('SchemaBuilder configuration', () {
    test('throws ArgumentError on empty model', () {
      final empty = GraphDataModel();
      expect(
        () => SchemaBuilder().fromGraphDataModel(empty),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('emits minimum-viable schema when no config is supplied', () {
      // No config means: no declared properties, no unions, no
      // schemaless opt-in, no edge-as-connection. Each node still has
      // id + labels + traversal fields, each edge still has id + from
      // + to.
      final bare = SchemaBuilder().fromGraphDataModel(dataModel);
      final user = _objectByName(bare, 'User');
      final names = user.fields.map((f) => f.name).toSet();
      // Builtin id + labels + 3 traversal fields (one per outgoing
      // edge, with collision disambiguation).
      expect(names, containsAll({'id', 'labels'}));
      // No declared properties surface.
      expect(names.contains('name'), isFalse);
      expect(names.contains('age'), isFalse);
    });

    test('throws StateError on Query-root field-name collision', () {
      // Two node entities with the same label produce the same
      // singular/plural field names.
      final clashy = GraphDataModel();
      clashy.registerNode<_NodeA>(label: GraphLabel('Thing'));
      clashy.registerNode<_NodeB>(label: GraphLabel('Thing'));
      expect(
        () => SchemaBuilder().fromGraphDataModel(clashy),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('nodeObjectTypeFor / edgeObjectTypeFor (single-entity convenience)',
      () {
    test('nodeObjectTypeFor returns a populated node type', () {
      final entity = dataModel.nodeEntities[Post]!;
      final type = SchemaBuilder().nodeObjectTypeFor(entity, config: config);
      expect(type.name, equals('Post'));
      final names = type.fields.map((f) => f.name).toSet();
      expect(names, containsAll({'id', 'labels', 'title', 'properties'}));
    });

    test('edgeObjectTypeFor returns id + edge properties (endpoints stubbed)',
        () {
      final entity = dataModel.edgeEntities[Friend]!;
      final type = SchemaBuilder().edgeObjectTypeFor(entity, config: config);
      expect(type.name, equals('Friend'));
      // No node registry means no from/to fields.
      final names = type.fields.map((f) => f.name).toSet();
      expect(names, containsAll({'id', 'since'}));
      expect(names.contains('from'), isFalse);
      expect(names.contains('to'), isFalse);
    });
  });
}

// -- Helpers ----------------------------------------------------------------

class _NodeA extends GraphNode<_NodeA> {
  _NodeA() : super(labels: const [GraphLabel.unchecked('Thing')]);
}

class _NodeB extends GraphNode<_NodeB> {
  _NodeB() : super(labels: const [GraphLabel.unchecked('Thing')]);
}

Set<GraphQLObjectType> _reachableObjectTypes(GraphQLSchema schema) {
  final out = <GraphQLObjectType>{};
  final stack = <GraphQLObjectType>[schema.queryType!];
  while (stack.isNotEmpty) {
    final t = stack.removeLast();
    if (!out.add(t)) continue;
    for (final f in t.fields) {
      _walkInto(f.type, out, stack);
    }
  }
  return out;
}

Set<GraphQLUnionType> _reachableUnionTypes(GraphQLSchema schema) {
  final unions = <GraphQLUnionType>{};
  final visitedObjects = <GraphQLObjectType>{};
  final stack = <GraphQLObjectType>[schema.queryType!];
  while (stack.isNotEmpty) {
    final t = stack.removeLast();
    if (!visitedObjects.add(t)) continue;
    for (final f in t.fields) {
      _collectUnionsFromType(f.type, unions, visitedObjects, stack);
    }
  }
  return unions;
}

void _collectUnionsFromType(
  GraphQLType type,
  Set<GraphQLUnionType> unions,
  Set<GraphQLObjectType> visited,
  List<GraphQLObjectType> stack,
) {
  GraphQLType current = type;
  while (true) {
    if (current is GraphQLNonNullableType) {
      current = current.ofType;
      continue;
    }
    if (current is GraphQLListType) {
      current = current.ofType;
      continue;
    }
    if (current is GraphQLObjectType) {
      stack.add(current);
      return;
    }
    if (current is GraphQLUnionType) {
      if (unions.add(current)) {
        for (final possible in current.possibleTypes) {
          stack.add(possible);
        }
      }
      return;
    }
    return;
  }
}

void _walkInto(
  GraphQLType type,
  Set<GraphQLObjectType> out,
  List<GraphQLObjectType> stack,
) {
  GraphQLType current = type;
  while (true) {
    if (current is GraphQLNonNullableType) {
      current = current.ofType;
      continue;
    }
    if (current is GraphQLListType) {
      current = current.ofType;
      continue;
    }
    if (current is GraphQLObjectType) {
      stack.add(current);
      return;
    }
    if (current is GraphQLUnionType) {
      for (final possible in current.possibleTypes) {
        stack.add(possible);
      }
      return;
    }
    return;
  }
}

GraphQLObjectType _objectByName(GraphQLSchema schema, String name) {
  final found = _reachableObjectTypes(schema).firstWhere(
    (t) => t.name == name,
    orElse: () => throw StateError(
      'Type $name not reachable from schema.queryType',
    ),
  );
  return found;
}

String _fieldType(GraphQLSchema schema, String typeName, String fieldName) {
  final t = _objectByName(schema, typeName);
  final f = t.fields.firstWhere(
    (f) => f.name == fieldName,
    orElse: () => throw StateError(
      'Field $typeName.$fieldName not present in schema',
    ),
  );
  return f.type.toString();
}
