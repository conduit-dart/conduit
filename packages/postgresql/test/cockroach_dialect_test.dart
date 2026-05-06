import 'package:conduit_postgresql/conduit_postgresql.dart';
import 'package:test/test.dart';

void main() {
  group('CockroachSqlDialect', () {
    const d = CockroachSqlDialect();
    const pg = PostgresSqlDialect();

    test('inherits Postgres column-type mapping (wire-compat)', () {
      // SERIAL/BIGSERIAL/JSONB/etc. are all valid on Cockroach (with
      // different semantics for SERIAL — see docs/cockroach.md).
      expect(d.columnDefinitionType('integer', autoincrement: true), 'SERIAL');
      expect(
        d.columnDefinitionType('bigInteger', autoincrement: true),
        'BIGSERIAL',
      );
      expect(d.columnDefinitionType('document', autoincrement: false), 'JSONB');
      expect(d.columnDefinitionType('datetime', autoincrement: false), 'TIMESTAMP');
    });

    test('inherits @name parameter syntax (wire-compat)', () {
      expect(d.parameterPlaceholder('foo'), '@foo');
      expect(d.parameterPlaceholder('foo'), pg.parameterPlaceholder('foo'));
    });

    test('overrides IS NULL/IS NOT NULL to standard SQL form', () {
      // Cockroach does not accept the Postgres ISNULL/NOTNULL shorthand.
      expect(d.isNullOperator, 'IS NULL');
      expect(d.isNotNullOperator, 'IS NOT NULL');
      // Confirm the override actually changes from the base.
      expect(d.isNullOperator, isNot(equals(pg.isNullOperator)));
    });

    test('inherits ILIKE for case-insensitive matching (wire-compat)', () {
      expect(d.caseInsensitiveLikeOperator, 'ILIKE');
    });

    test('inherits ALTER TABLE ONLY (Cockroach accepts as no-op)', () {
      expect(d.alterTableForConstraintModification, 'ALTER TABLE ONLY');
    });

    test('overrides version-table name to namespace by dialect', () {
      expect(d.versionTableName, '_conduit_version_cockroach');
      expect(d.versionTableName, isNot(equals(pg.versionTableName)));
    });

    test('inherits Postgres tableExistsQuery (to_regclass works on 21.1+)', () {
      expect(d.tableExistsQuery(), contains('to_regclass'));
    });
  });

  group('PostgreSQLPersistentStore dialect injection', () {
    test('default constructor uses PostgresSqlDialect', () {
      final store = PostgreSQLPersistentStore('u', 'p', 'h', 5432, 'd');
      expect(store.dialect, isA<PostgresSqlDialect>());
      expect(store.dialect.name, 'postgres');
    });

    test('accepts a Cockroach dialect override', () {
      final store = PostgreSQLPersistentStore(
        'u',
        'p',
        'h',
        5432,
        'd',
        dialect: const CockroachSqlDialect(),
      );
      expect(store.dialect, isA<CockroachSqlDialect>());
      expect(store.dialect.name, 'cockroach');
      expect(store.dialect.isNullOperator, 'IS NULL');
      expect(store.versionTableName, '_conduit_version_cockroach');
    });

    test('schema generator picks up the injected dialect', () {
      final store = PostgreSQLPersistentStore(
        'u',
        'p',
        'h',
        5432,
        'd',
        dialect: const CockroachSqlDialect(),
      );
      // versionTable name routed through the mixin's `versionTableName`
      // getter, which delegates to `dialect.versionTableName`.
      expect(store.versionTable.name, '_conduit_version_cockroach');
    });
  });
}
