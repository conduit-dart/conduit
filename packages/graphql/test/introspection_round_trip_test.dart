// Introspection round-trip: feeds the derived blog schema into the
// G1 `GraphQLController` (no controller changes — just a schema swap)
// and verifies that an `__schema { types ... }` query returns every
// derived ObjectType, plus that custom scalars surface via field-level
// introspection.
//
// This is the seam test for G3: as long as G3's resolver hookup
// preserves the schema's introspection surface, the controller mount
// remains untouched.

import 'dart:convert';
import 'dart:io';

import 'package:conduit_core/conduit_core.dart' hide SchemaBuilder;
import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fixtures/blog_model.dart';

Future<HttpServer> _startServer(GraphQLSchema schema) async {
  final router = Router();
  router.route('/graphql').link(() => GraphQLController(schema));
  router.didAddToChannel();

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.map(Request.new).listen(router.receive);
  return server;
}

Uri _u(HttpServer s) => Uri(
      scheme: 'http',
      host: 'localhost',
      port: s.port,
      path: '/graphql',
    );

void main() {
  late HttpServer server;

  setUpAll(() async {
    final dataModel = ManagedDataModel([User, Post, Comment, Tag, PostTag]);
    final schema = SchemaBuilder().fromManagedDataModel(dataModel);
    server = await _startServer(schema);
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  test('__schema query returns every derived ObjectType', () async {
    final response = await http.post(
      _u(server),
      headers: {'content-type': 'application/json'},
      body: json.encode({
        'query': '{ __schema { types { name kind } } }',
      }),
    );

    expect(response.statusCode, 200);
    final body = json.decode(response.body) as Map<String, dynamic>;
    expect(body.containsKey('errors'), isFalse,
        reason: 'unexpected errors: ${body['errors']}');

    final types = (body['data'] as Map)['__schema']['types'] as List;
    final names = types.map<String>((t) => (t as Map)['name'] as String).toSet();

    // Every derived entity type must be present.
    for (final entity in ['User', 'Post', 'Comment', 'Tag', 'PostTag']) {
      expect(names, contains(entity),
          reason: 'derived ObjectType $entity missing from introspection');
    }

    // Query root.
    expect(names, contains('Query'));

    // Standard scalars referenced through fields.
    expect(names, contains('String'));
    expect(names, contains('Int'));
    expect(names, contains('Float'));
    expect(names, contains('Boolean'));

    // Confirm at least the entity OBJECT kind is reported correctly.
    final userType = types
        .map((t) => t as Map)
        .firstWhere((t) => t['name'] == 'User');
    expect(userType['kind'], equals('OBJECT'));
  });

  test('custom DateTime scalar is visible via field-level introspection', () async {
    // graphql_server2 v6.5.0 has a known limitation where bare custom
    // scalars are not added to `__schema { types }` (see
    // CollectTypes._fetchAllTypesFromType — the scalar branch falls
    // through without adding to the traversed set). Custom scalars
    // ARE still attached to fields that reference them, though, so
    // `__type(name: "User") { fields { type { ofType { name } } } }`
    // will surface "DateTime" correctly. This test pins that behavior
    // so we know exactly what introspection contract clients can rely
    // on today.
    final response = await http.post(
      _u(server),
      headers: {'content-type': 'application/json'},
      body: json.encode({
        'query': r'''
          {
            __type(name: "User") {
              fields {
                name
                type {
                  kind name
                  ofType { kind name }
                }
              }
            }
          }
        ''',
      }),
    );
    expect(response.statusCode, 200);
    final body = json.decode(response.body) as Map<String, dynamic>;
    expect(body['errors'], isNull);
    final fields = ((body['data'] as Map)['__type'] as Map)['fields'] as List;
    final createdAt =
        fields.map((f) => f as Map).firstWhere((f) => f['name'] == 'createdAt');
    final type = createdAt['type'] as Map;
    // createdAt is nullable in our model (defaultValue 'now()' makes
    // it nullable in the schema), so type.kind should be SCALAR with
    // name "DateTime" directly.
    expect(type['kind'], equals('SCALAR'));
    expect(type['name'], equals('DateTime'));
  });

  test('field-level introspection on User exposes derived fields', () async {
    final response = await http.post(
      _u(server),
      headers: {'content-type': 'application/json'},
      body: json.encode({
        'query': r'''
          {
            __type(name: "User") {
              name
              fields {
                name
                type {
                  kind
                  name
                  ofType { kind name ofType { kind name ofType { name } } }
                }
              }
            }
          }
        ''',
      }),
    );
    expect(response.statusCode, 200);
    final body = json.decode(response.body) as Map<String, dynamic>;
    expect(body['errors'], isNull);

    final userType = (body['data'] as Map)['__type'] as Map;
    expect(userType['name'], 'User');
    final fields = userType['fields'] as List;
    final fieldNames = fields
        .map<String>((f) => (f as Map)['name'] as String)
        .toSet();

    // Scalar fields are present.
    expect(fieldNames, contains('id'));
    expect(fieldNames, contains('email'));
    expect(fieldNames, contains('createdAt'));
    // hasMany relationship is present.
    expect(fieldNames, contains('posts'));
    // Output-side transient is present.
    expect(fieldNames, contains('displayName'));
    // Input-only transient must NOT be present.
    expect(fieldNames.contains('rawName'), isFalse);
  });

  test('Query root introspection lists 10 fields', () async {
    final response = await http.post(
      _u(server),
      headers: {'content-type': 'application/json'},
      body: json.encode({
        'query': r'{ __type(name: "Query") { fields { name } } }',
      }),
    );
    expect(response.statusCode, 200);
    final body = json.decode(response.body) as Map<String, dynamic>;
    expect(body['errors'], isNull);

    final fields = ((body['data'] as Map)['__type'] as Map)['fields'] as List;
    expect(fields, hasLength(10));
  });
}
