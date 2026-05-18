import 'dart:convert';
import 'dart:io';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fixtures/hello_schema.dart';

/// Spins up an HttpServer with a single GraphQLController mounted at
/// `/graphql`. This is the in-process variant — no isolate, no
/// `Application` overhead — for fast unit tests of the controller's
/// HTTP envelope behavior. The end-to-end isolate path lives in
/// `graphql_e2e_test.dart`.
Future<HttpServer> _startServer(GraphQLSchema schema) async {
  final router = Router();
  router.route('/graphql').link(() => GraphQLController(schema));
  router.didAddToChannel();

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.map(Request.new).listen(router.receive);
  return server;
}

Uri _u(HttpServer s, [Map<String, String>? q]) => Uri(
      scheme: 'http',
      host: 'localhost',
      port: s.port,
      path: '/graphql',
      queryParameters: q,
    );

Future<http.Response> _post(
  HttpServer s,
  Object body, {
  String contentType = 'application/json',
}) {
  return http.post(
    _u(s),
    headers: {'content-type': contentType},
    body: body is String ? body : json.encode(body),
  );
}

void main() {
  late HttpServer server;

  setUpAll(() {
    hierarchicalLoggingEnabled = true;
    Logger('conduit')
      ..level = Level.ALL
      ..onRecord.listen((r) {
        // ignore: avoid_print
        print('[conduit] ${r.level.name}: ${r.message} ${r.error ?? ''}\n${r.stackTrace ?? ''}');
      });
  });

  setUp(() async {
    server = await _startServer(helloSchema);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('POST { hello } returns data.hello == "world"', () async {
    final res = await _post(server, {'query': '{ hello }'});
    expect(res.statusCode, 200);
    final body = json.decode(res.body);
    expect(body, {
      'data': {'hello': 'world'}
    });
  });

  test('POST query with variables resolves correctly', () async {
    final res = await _post(server, {
      'query': r'query Echo($m: String!) { echo(message: $m) }',
      'variables': {'m': 'hi'},
    });
    expect(res.statusCode, 200);
    final body = json.decode(res.body);
    expect(body, {
      'data': {'echo': 'hi'}
    });
  });

  test('POST malformed JSON body returns 400', () async {
    final res = await _post(server, '{not json,');
    expect(res.statusCode, 400);
  });

  test('POST query with parse error returns 400 with Syntax message',
      () async {
    final res = await _post(server, {'query': '{ hello'});
    expect(res.statusCode, 400);
    final body = json.decode(res.body) as Map<String, dynamic>;
    final errors = body['errors'] as List;
    expect(errors, isNotEmpty);
    expect(errors.first['message'] as String, contains('Syntax'));
  });

  test(
      'POST query referencing undefined field returns 400 with field name in error',
      () async {
    final res = await _post(server, {'query': '{ nonexistentField }'});
    expect(res.statusCode, 400);
    final body = json.decode(res.body) as Map<String, dynamic>;
    final errors = body['errors'] as List;
    expect(errors, isNotEmpty);
    expect(errors.first['message'] as String, contains('nonexistentField'));
  });

  test(
      'POST mutation that throws returns 200 with errors array (per spec)',
      () async {
    final res = await _post(server, {'query': '{ boom }'});
    // Per the GraphQL-over-HTTP spec, a resolver that throws is still
    // a *processed* request — the result map carries `errors` and the
    // failed field is null. HTTP status stays 200.
    expect(res.statusCode, 200);
    final body = json.decode(res.body) as Map<String, dynamic>;
    final errors = body['errors'] as List;
    expect(errors, isNotEmpty);
    expect((errors.first as Map)['message'], isNotEmpty);
    expect((body['data'] as Map?)?['boom'], isNull);
  });

  test('GET ?query={hello} returns 200 with data.hello', () async {
    final res = await http.get(_u(server, {'query': '{ hello }'}));
    expect(res.statusCode, 200);
    final body = json.decode(res.body);
    expect(body, {
      'data': {'hello': 'world'}
    });
  });

  test('GET attempting a mutation returns 405', () async {
    final res =
        await http.get(_u(server, {'query': 'mutation { shout(message: "hi") }'}));
    expect(res.statusCode, 405);
    expect(res.headers['allow'], contains('POST'));
    final body = json.decode(res.body) as Map<String, dynamic>;
    expect(body['errors'], isNotEmpty);
  });

  test('GET ?variables=invalid-json returns 400', () async {
    final res = await http.get(_u(server, {
      'query': '{ hello }',
      'variables': 'not-json',
    }));
    expect(res.statusCode, 400);
    final body = json.decode(res.body) as Map<String, dynamic>;
    expect(body['errors'], isNotEmpty);
  });

  test('Content-Type application/graphql raw body parses correctly',
      () async {
    final res = await _post(
      server,
      '{ hello }',
      contentType: 'application/graphql',
    );
    expect(res.statusCode, 200);
    final body = json.decode(res.body);
    expect(body, {
      'data': {'hello': 'world'}
    });
  });

  test('Introspection: { __schema { queryType { name } } } returns "Query"',
      () async {
    final res = await _post(server, {
      'query': '{ __schema { queryType { name } } }',
    });
    expect(res.statusCode, 200);
    final body = json.decode(res.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    final schemaField = data['__schema'] as Map<String, dynamic>;
    final queryType = schemaField['queryType'] as Map<String, dynamic>;
    expect(queryType['name'], 'Query');
  });

  test('POST mutation succeeds (POST allows mutations)', () async {
    final res = await _post(server, {
      'query': r'mutation S($m: String!) { shout(message: $m) }',
      'variables': {'m': 'hello'},
    });
    expect(res.statusCode, 200);
    final body = json.decode(res.body);
    expect(body, {
      'data': {'shout': 'HELLO'}
    });
  });

  test('POST without query field returns 400', () async {
    final res = await _post(server, {'operationName': 'Foo'});
    expect(res.statusCode, 400);
    final body = json.decode(res.body) as Map<String, dynamic>;
    expect(body['errors'], isNotEmpty);
  });

  test('POST with non-object variables returns 400', () async {
    final res = await _post(server, {
      'query': '{ hello }',
      'variables': 'not-an-object',
    });
    expect(res.statusCode, 400);
    final body = json.decode(res.body) as Map<String, dynamic>;
    expect(body['errors'], isNotEmpty);
  });

  test(
      'Accept: application/graphql-response+json returns matching content type',
      () async {
    final res = await http.post(
      _u(server),
      headers: {
        'content-type': 'application/json',
        'accept': 'application/graphql-response+json',
      },
      body: json.encode({'query': '{ hello }'}),
    );
    expect(res.statusCode, 200);
    expect(res.headers['content-type'],
        contains('application/graphql-response+json'));
  });

  test(
      'Operation selection: operationName picks the right operation',
      () async {
    final res = await _post(server, {
      'query': '''
query A { hello }
query B { echo(message: "from-B") }
''',
      'operationName': 'B',
    });
    expect(res.statusCode, 200);
    final body = json.decode(res.body);
    expect(body, {
      'data': {'echo': 'from-B'}
    });
  });
}
