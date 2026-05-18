// Postgres-backed integration test for the G3 resolver factory.
//
// Tagged `integration` so the default `dart test` run skips it; the
// CI matrix that has Postgres available runs it via
// `dart test -t integration`. Locally:
//
//   docker compose -f ../../ci/docker-compose.yaml up -d
//   POSTGRES_HOST=localhost POSTGRES_PORT=15432 \
//     POSTGRES_USER=conduit_test_user POSTGRES_PASSWORD=conduit! \
//     POSTGRES_DB=conduit_test_db dart test -t integration
//
// Per the dialect-annotation contract from #267, this file is gated
// to the postgres dialect — running it under SQLite or MySQL would
// hit `UnimplementedError` from those stores' `newQuery` paths.
//
// Per-fixture queries asserted here:
//   1. List query: `{ users { id email } }` returns every seeded user.
//   2. List with filter: `where: { isActive: { eq: true } }` filters to
//      active users.
//   3. List with sort + pagination: `orderBy: [...], limit: ..., offset: ...`.
//   4. By-PK: `{ user(id: ...) { id email } }`.
//   5. N+1 mitigation: `{ users { id posts { id title } } }` over 50
//      users with ~5 posts each fans out to exactly 2 SQL round-trips
//      (one for users, one batched for posts).

@Tags(['integration'])
library;

import 'dart:io';

// We need both `SchemaBuilder`s in this test:
//   * `package:conduit_graphql`'s `SchemaBuilder` for the GraphQL
//     schema derivation (aliased as `GqlSchemaBuilder` below).
//   * `package:conduit_core`'s `SchemaBuilder` for the DDL emitter
//     (the migration helper that produces `CREATE TEMPORARY TABLE`
//     statements). This is the default-named one in the imported
//     namespace.
import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_graphql/conduit_graphql.dart' as gql
    show SchemaBuilder, SqlResolverFactory, dataLoaderRegistryArgKey;
import 'package:conduit_graphql/conduit_graphql.dart'
    hide SchemaBuilder, SqlResolverFactory;
import 'package:conduit_postgresql/conduit_postgresql.dart';
import 'package:conduit_test/conduit_test.dart';
import 'package:test/test.dart';

import '../fixtures/blog_model.dart';

/// Connection settings — same defaults as
/// `packages/postgresql/test/not_tests/postgres_test_config.dart`.
const _defaultHost = 'localhost';
const _defaultPort = 15432;
const _defaultUser = 'conduit_test_user';
const _defaultPassword = 'conduit!';
const _defaultDb = 'conduit_test_db';

String _envOr(String key, String fallback) {
  final v = Platform.environment[key]?.trim();
  return (v == null || v.isEmpty) ? fallback : v;
}

int _envIntOr(String key, int fallback) {
  final v = Platform.environment[key]?.trim();
  if (v == null || v.isEmpty) return fallback;
  return int.tryParse(v) ?? fallback;
}

void main() {
  setUpAll(() {
    skipIfDialectMismatch(onlyOn: const OnlyOn([Dialect.postgres]));
  });

  late ManagedDataModel dataModel;
  late _CountingPostgresStore store;
  late ManagedContext context;
  late gql.SqlResolverFactory factory;
  late GraphQLSchema schema;

  setUp(() async {
    dataModel = ManagedDataModel([User, Post, Comment, Tag, PostTag]);
    store = _CountingPostgresStore(
      _envOr('POSTGRES_USER', _defaultUser),
      _envOr('POSTGRES_PASSWORD', _defaultPassword),
      _envOr('POSTGRES_HOST', _defaultHost),
      _envIntOr('POSTGRES_PORT', _defaultPort),
      _envOr('POSTGRES_DB', _defaultDb),
    );
    context = ManagedContext(dataModel, store);
    factory = gql.SqlResolverFactory(context)
      // Match the schema's `bigIntegerAsString: false` choice — the
      // attribute resolver must NOT stringify big-int values when the
      // schema is shipping them as Int!.
      ..stringifyBigInts = false;

    schema = gql.SchemaBuilder(
      // Treat big-integer PKs as Int (the fixture's PKs fit in 32 bits).
      // The default `String` projection for big-ints is correct for
      // schema introspection in production but forces every value to
      // round-trip through string serialization, which the test would
      // have to mirror manually.
      bigIntegerAsString: false,
      generateFilterArgs: true,
      generateSortArgs: true,
      generatePaginationArgs: true,
      attributeResolver: factory.attributeResolverFor,
      relationshipResolver: factory.relationshipResolverFor,
      queryListResolver: factory.listResolverFor,
      queryByPkResolver: factory.byPkResolverFor,
    ).fromManagedDataModel(dataModel);

    // (Re)create tables. Postgres TEMP tables go through the same
    // SchemaBuilder path the migration runner uses.
    final commands = _commandsFromDataModel(dataModel, temporary: true);
    for (final cmd in commands) {
      await store.execute(cmd);
    }
  });

  tearDown(() async {
    await context.close();
  });

  test('list query returns every seeded row', () async {
    await _seedThreeUsers(context);
    final response = await _execute(schema, factory, '{ users { id email } }');
    final users = (response['data'] as Map)['users'] as List;
    expect(users, hasLength(3));
    expect(
      users.map((u) => (u as Map)['email']).toSet(),
      equals({'a@b.com', 'c@d.com', 'e@f.com'}),
    );
  });

  test('list query with where: filter narrows the result set', () async {
    final entity = dataModel.entityForType(User);
    // Seed two active and one inactive user via the ORM so we don't
    // depend on table-name casing for hand-rolled SQL updates.
    for (final (email, active) in [
      ('a@b.com', false),
      ('c@d.com', true),
      ('e@f.com', true),
    ]) {
      final q = Query.forEntity(entity, context)
        ..valueMap = {'email': email, 'isActive': active};
      await q.insert();
    }
    store.queryCount = 0;
    final response = await _execute(
      schema,
      factory,
      r'''
        { users(where: { isActive: { eq: true } }) { email } }
      ''',
    );
    final users = (response['data'] as Map)['users'] as List;
    expect(users, hasLength(2));
    expect(
      users.map((u) => (u as Map)['email']).toSet(),
      equals({'c@d.com', 'e@f.com'}),
    );
  });

  test('list query with orderBy + limit + offset paginates correctly',
      () async {
    // Seed five rows so offset/limit have something to bite into.
    for (var i = 0; i < 5; i++) {
      final q = Query.forEntity(dataModel.entityForType(User), context)
        ..valueMap = {'email': 'user$i@x.com'};
      await q.insert();
    }
    final response = await _execute(
      schema,
      factory,
      r'''
        { users(orderBy: [{field: email, direction: ASC}],
                limit: 2, offset: 1) { email } }
      ''',
    );
    final users = (response['data'] as Map)['users'] as List;
    expect(users, hasLength(2));
    // ASC by email starting at offset 1 -> user1, user2.
    expect(users.map((u) => (u as Map)['email']).toList(),
        equals(['user1@x.com', 'user2@x.com']));
  });

  test('by-pk fetches a single row, returning null on miss', () async {
    final insertQ = Query.forEntity(
      dataModel.entityForType(User),
      context,
    )..valueMap = {'email': 'pk@b.com'};
    final inserted = await insertQ.insert();
    final pk = inserted['id'] as int;

    final hit = await _execute(
      schema,
      factory,
      '{ user(id: $pk) { email } }',
    );
    expect(((hit['data'] as Map)['user'] as Map)['email'], equals('pk@b.com'));

    final miss = await _execute(
      schema,
      factory,
      '{ user(id: 999999999) { email } }',
    );
    expect((miss['data'] as Map)['user'], isNull);
  });

  test(
    'N+1 mitigation: 50 users with 5 posts each = 2 SQL round-trips',
    () async {
      // Seed 50 users with 5 posts each (250 posts total).
      final userQueryEntity = dataModel.entityForType(User);
      final postQueryEntity = dataModel.entityForType(Post);
      final userIds = <int>[];
      for (var i = 0; i < 50; i++) {
        final uq = Query.forEntity(userQueryEntity, context)
          ..valueMap = {'email': 'u$i@x.com'};
        final u = await uq.insert();
        final uid = u['id'] as int;
        userIds.add(uid);
        for (var j = 0; j < 5; j++) {
          final pq = Query.forEntity(postQueryEntity, context)
            ..valueMap = {
              'title': 'p$i-$j',
              'body': 'b',
              'viewCount': 0,
              'rating': 1.0,
              'author': {'id': uid},
            };
          await pq.insert();
        }
      }

      // Now zero the counter and run the GraphQL query.
      store.queryCount = 0;
      final response = await _execute(
        schema,
        factory,
        '{ users { id posts { id title } } }',
      );

      final users = (response['data'] as Map)['users'] as List;
      expect(users, hasLength(50));
      final allPosts = users
          .expand((u) => (u as Map)['posts'] as List)
          .toList();
      expect(allPosts, hasLength(250));

      // The whole nested query should fan out to exactly 2 SQL round
      // trips: one SELECT for the users, one batched
      // `WHERE author_id IN (...)` for the posts.
      expect(
        store.queryCount,
        equals(2),
        reason:
            'N+1 mitigation: expected 2 SQL queries (1 users + 1 batched '
            'posts), got ${store.queryCount}.',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

// -- Helpers ---------------------------------------------------------------

Future<void> _seedThreeUsers(ManagedContext context) async {
  final entity = context.dataModel!.entityForType(User);
  for (final email in ['a@b.com', 'c@d.com', 'e@f.com']) {
    final q = Query.forEntity(entity, context)
      ..valueMap = {'email': email};
    await q.insert();
  }
}

/// Executes [query] against [schema] using the supplied dataloader-aware
/// resolver factory, and returns the raw result map.
Future<Map<String, dynamic>> _execute(
  GraphQLSchema schema,
  gql.SqlResolverFactory factory,
  String query,
) async {
  final executor = GraphQL(schema);
  final registry = factory.newRegistry();
  try {
    final dynamic result = await executor.parseAndExecute(
      query,
      globalVariables: <String, dynamic>{
        gql.dataLoaderRegistryArgKey: registry,
      },
    );
    return {'data': result};
  } finally {
    registry.clear();
  }
}

List<String> _commandsFromDataModel(
  ManagedDataModel dataModel, {
  bool temporary = false,
}) {
  final targetSchema = Schema.fromDataModel(dataModel);
  final builder = SchemaBuilder.toSchema(
    PostgreSQLPersistentStore(null, null, null, _defaultPort, null),
    targetSchema,
    isTemporary: temporary,
  );
  return builder.commands;
}

/// Postgres store wrapper that counts every `executeQuery` call so the
/// N+1 mitigation test can assert on round-trip count without reaching
/// into the upstream driver.
///
/// We override `executeQuery` because it's the path the ORM's
/// `Query<T>.fetch()` runs through (via the table builder); plain
/// `execute` is used for DDL and SET statements at session start.
/// Counting only `executeQuery` keeps the counter focused on the SQL
/// the resolver-driven query path emits.
class _CountingPostgresStore extends PostgreSQLPersistentStore {
  _CountingPostgresStore(
    super.username,
    super.password,
    super.host,
    super.port,
    super.dbName,
  );

  int queryCount = 0;

  @override
  Future<dynamic> executeQuery(
    String formatString,
    Map<String, dynamic>? values,
    int timeoutInSeconds, {
    PersistentStoreQueryReturnType? returnType =
        PersistentStoreQueryReturnType.rows,
  }) {
    queryCount++;
    return super.executeQuery(
      formatString,
      values,
      timeoutInSeconds,
      returnType: returnType,
    );
  }
}
