import 'package:conduit_core/conduit_core.dart';
import 'package:postgres/postgres.dart';

/// PostgreSQL-flavored SQL generation. The default `SqlDialect` already
/// matches Postgres conventions for most things — this subclass overrides
/// the divergences (`ILIKE` for case-insensitive matching, `ALTER TABLE
/// ONLY` for constraint mods, `to_regclass()` for table-existence checks,
/// the historical `ISNULL`/`NOTNULL` shorthand, and the column-type map).
class PostgresSqlDialect extends SqlDialect {
  const PostgresSqlDialect();

  @override
  String get name => 'postgres';

  /// Map a `ManagedPropertyType` into the postgres-driver `Type`
  /// constant used by `TypedValue` for parameter binding. Mirrors the
  /// historical `ColumnBuilder.typeMap` table that lived in
  /// `packages/postgresql/lib/src/builders/column.dart` — the
  /// dialect-agnostic builders no longer carry this mapping.
  static const Map<ManagedPropertyType, Type> _typedValueMap = {
    ManagedPropertyType.integer: Type.integer,
    ManagedPropertyType.bigInteger: Type.bigInteger,
    ManagedPropertyType.string: Type.text,
    ManagedPropertyType.datetime: Type.timestampWithoutTimezone,
    ManagedPropertyType.boolean: Type.boolean,
    ManagedPropertyType.doublePrecision: Type.double,
    ManagedPropertyType.document: Type.jsonb,
  };

  /// Wrap a Dart value into a `TypedValue` so the postgres driver
  /// knows how to bind it. The historical query builders did this
  /// inline; the lift moved the wrapping behind this dialect hook so
  /// the builders stay dialect-agnostic.
  ///
  /// `null` types fall back to the value as-is (the driver will
  /// infer); `null` values are wrapped with the right type so the
  /// driver doesn't choke on an untyped NULL.
  @override
  Object? encodeValue(Object? value, ManagedPropertyType? type) {
    final pgType = type == null ? null : _typedValueMap[type];
    if (pgType == null) {
      return value;
    }
    return TypedValue(pgType, value);
  }

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
