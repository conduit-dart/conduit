// Structural tests for [SchemaBuilder.fromPersistence].
//
// Verifies the unified emission path produces:
//   * every SQL ObjectType reachable via the side-channel sqlObjectTypes
//   * every graph ObjectType reachable via the side-channel graphObjectTypes
//   * a single Query root with both halves' fields
//   * source tags on every emitted ObjectType
//   * the requested QueryRootCollisionPolicy when names collide

// Hide conduit_core's SchemaBuilder (a database-migration helper) so
// the schema-derivation SchemaBuilder from conduit_graphql resolves
// without an `as` prefix.
import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:test/test.dart';

import '_helpers/fake_persistence.dart';
import 'fixtures/cross_source_fixture.dart';

void main() {
  group('fromPersistence — unified Query root', () {
    late PersistenceSchema persistenceSchema;

    setUpAll(() {
      final persistence = buildFakePersistence(
        sqlModel: buildCrossSourceSqlModel(),
        graphModel: buildCrossSourceGraphModel(),
      );
      persistenceSchema = SchemaBuilder().fromPersistence(
        persistence,
        graphConfig: buildCrossSourceGraphConfig(),
      );
    });

    test('emits both SQL and graph object types', () {
      expect(persistenceSchema.sqlObjectTypes.keys, contains('User'));
      expect(persistenceSchema.graphObjectTypes.keys, contains('Profile'));
      expect(persistenceSchema.graphObjectTypes.keys, contains('Friendship'));
    });

    test('Query root holds fields from both halves', () {
      final query = persistenceSchema.schema.queryType!;
      final names = query.fields.map((f) => f.name).toSet();
      // SQL side
      expect(names, contains('user'));
      expect(names, contains('users'));
      // Graph side
      expect(names, contains('profile'));
      expect(names, contains('profiles'));
      expect(names, contains('friendships'));
    });

    test('source tags expose which half emitted each ObjectType', () {
      final userType = persistenceSchema.sqlObjectTypes['User']!;
      final profileType = persistenceSchema.graphObjectTypes['Profile']!;
      final friendshipType =
          persistenceSchema.graphObjectTypes['Friendship']!;
      expect(persistenceSchema.sourceFor(userType), equals('sql'));
      expect(persistenceSchema.sourceFor(profileType), equals('graph'));
      expect(persistenceSchema.sourceFor(friendshipType), equals('graph'));
    });

    test('SQL-only umbrella still emits a unified schema', () {
      final p = buildFakePersistence(sqlModel: buildCrossSourceSqlModel());
      final result = SchemaBuilder().fromPersistence(p);
      expect(result.sqlObjectTypes.keys, contains('User'));
      expect(result.graphObjectTypes, isEmpty);
      expect(
        result.schema.queryType!.fields.map((f) => f.name).toSet(),
        containsAll(['user', 'users']),
      );
    });

    test('graph-only umbrella still emits a unified schema', () {
      final p = buildFakePersistence(
        graphModel: buildCrossSourceGraphModel(),
      );
      final result = SchemaBuilder().fromPersistence(
        p,
        graphConfig: buildCrossSourceGraphConfig(),
      );
      expect(result.sqlObjectTypes, isEmpty);
      expect(result.graphObjectTypes.keys, contains('Profile'));
      expect(
        result.schema.queryType!.fields.map((f) => f.name).toSet(),
        containsAll(['profile', 'profiles']),
      );
    });

    test('ArgumentError when neither half is configured', () {
      final p = buildFakePersistence();
      expect(
        () => SchemaBuilder().fromPersistence(p),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('fromPersistence — collision policy', () {
    test('error policy throws when SQL and graph names collide', () {
      final p = buildFakePersistence(
        sqlModel: buildCollisionSqlModel(),
        graphModel: buildCollisionGraphModel(),
      );
      expect(
        () => SchemaBuilder().fromPersistence(
          p,
          graphConfig: buildCollisionGraphConfig(),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('prefixGraph renames graph fields when collisions occur', () {
      final p = buildFakePersistence(
        sqlModel: buildCollisionSqlModel(),
        graphModel: buildCollisionGraphModel(),
      );
      final result = SchemaBuilder().fromPersistence(
        p,
        graphConfig: buildCollisionGraphConfig(),
        collisionPolicy: QueryRootCollisionPolicy.prefixGraph,
      );
      final names = result.schema.queryType!.fields.map((f) => f.name).toSet();
      // SQL side keeps original names
      expect(names, contains('account'));
      expect(names, contains('accounts'));
      // Graph side gets prefixed
      expect(names, contains('g_account'));
      expect(names, contains('g_accounts'));
    });

    test('prefixRelational renames SQL fields when collisions occur', () {
      final p = buildFakePersistence(
        sqlModel: buildCollisionSqlModel(),
        graphModel: buildCollisionGraphModel(),
      );
      final result = SchemaBuilder().fromPersistence(
        p,
        graphConfig: buildCollisionGraphConfig(),
        collisionPolicy: QueryRootCollisionPolicy.prefixRelational,
      );
      final names = result.schema.queryType!.fields.map((f) => f.name).toSet();
      // SQL side gets prefixed
      expect(names, contains('r_account'));
      expect(names, contains('r_accounts'));
      // Graph side keeps original names
      expect(names, contains('account'));
      expect(names, contains('accounts'));
    });

    test('non-colliding names are untouched even under prefix policy', () {
      final p = buildFakePersistence(
        sqlModel: buildCrossSourceSqlModel(),
        graphModel: buildCrossSourceGraphModel(),
      );
      final result = SchemaBuilder().fromPersistence(
        p,
        graphConfig: buildCrossSourceGraphConfig(),
        collisionPolicy: QueryRootCollisionPolicy.prefixGraph,
      );
      final names = result.schema.queryType!.fields.map((f) => f.name).toSet();
      // No collisions in this fixture, so no prefixes are introduced.
      expect(names, contains('user'));
      expect(names, contains('profile'));
      expect(names.where((n) => n.startsWith('g_')), isEmpty);
    });
  });
}
