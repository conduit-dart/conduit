import 'package:conduit_core/conduit_core.dart';

/// PostgreSQL-flavored SQL generation. The default `SqlDialect` already
/// matches Postgres conventions for most things — this subclass overrides
/// the divergences (`ILIKE` for case-insensitive matching, `ALTER TABLE
/// ONLY` for constraint mods, `to_regclass()` for table-existence checks,
/// the historical `ISNULL`/`NOTNULL` shorthand, and the column-type map).
class PostgresSqlDialect extends SqlDialect {
  const PostgresSqlDialect();

  @override
  String get name => 'postgres';

  // -- Type mapping (formerly hardcoded in PostgreSQLSchemaGenerator) --------

  @override
  String? columnDefinitionType(
    String typeString, {
    required bool autoincrement,
  }) {
    switch (typeString) {
      case 'integer':
        return autoincrement ? 'SERIAL' : 'INT';
      case 'bigInteger':
        return autoincrement ? 'BIGSERIAL' : 'BIGINT';
      case 'string':
        return 'TEXT';
      case 'datetime':
        return 'TIMESTAMP';
      case 'boolean':
        return 'BOOLEAN';
      case 'double':
        return 'DOUBLE PRECISION';
      case 'document':
        return 'JSONB';
    }
    return null;
  }

  // -- Operators where Postgres differs from standard SQL --------------------

  /// Postgres extension to standard SQL.
  @override
  String get caseInsensitiveLikeOperator => 'ILIKE';

  /// Postgres shorthand. Also accepts standard `IS NULL` — preserved here
  /// for historical compatibility with existing query output.
  @override
  String get isNullOperator => 'ISNULL';

  @override
  String get isNotNullOperator => 'NOTNULL';

  /// Postgres-specific. Avoids recursing into inheritance children when
  /// modifying constraints — irrelevant for backends without table
  /// inheritance.
  @override
  String get alterTableForConstraintModification => 'ALTER TABLE ONLY';

  // -- Schema-version bookkeeping --------------------------------------------

  /// Preserved verbatim from the original `PostgreSQLSchemaGenerator` so
  /// existing databases keep finding their version table.
  @override
  String get versionTableName => '_conduit_version_pgsql';

  /// `to_regclass(<schema>.<table>::text)` returns the OID of the named
  /// table, or `NULL` if it doesn't exist. The query mirrors the existing
  /// `_createVersionTableIfNecessary` behavior.
  @override
  String tableExistsQuery() =>
      'SELECT to_regclass(${parameterPlaceholder("tableName")}:text)';
}
