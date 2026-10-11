import 'dart:io';

import 'package:conduit_postgresql/conduit_postgresql.dart';
import 'package:test/test.dart';

import 'not_tests/postgres_test_config.dart';

/// Checks that the test database has PostGIS, for the geography work in
/// #234. Linux CI, Woodpecker, ci/docker-compose.yaml and the AI runner
/// provision a PostGIS image and set `CONDUIT_POSTGIS=true`; macOS and
/// Windows CI use a stock Postgres and skip PostGIS tests.
void main() {
  final enabled = Platform.environment['CONDUIT_POSTGIS'] == 'true';

  group('PostGIS', () {
    late PostgreSQLPersistentStore store;

    setUp(() => store = PostgresTestConfig().persistentStore());
    tearDown(() => store.close());

    test('the extension can be enabled and is version 3', () async {
      await store.execute('CREATE EXTENSION IF NOT EXISTS postgis');
      final rows = await store.execute('SELECT postgis_lib_version()') as List;
      expect(rows.single.single, startsWith('3.'));
    });

    test('computes geodesic distance on geography points', () async {
      // San Francisco to Los Angeles is about 559 km on the spheroid.
      final rows = await store.execute(
        "SELECT ST_Distance("
        "'SRID=4326;POINT(-122.4194 37.7749)'::geography, "
        "'SRID=4326;POINT(-118.2437 34.0522)'::geography)",
      ) as List;
      final meters = rows.single.single as double;
      expect(meters, closeTo(559000, 2000));
    });
  }, skip: enabled ? false : 'CONDUIT_POSTGIS is not true (no PostGIS here)');
}
