/// Dialect-specific SQL generation surface.
///
/// `PersistentStore` is the framework-facing seam for swapping ORM backends,
/// but most of the *generation* of SQL — column DDL types, parameter
/// placeholder syntax, identifier quoting, naming conventions, table-existence
/// queries, error code translation — varies between SQL backends. A
/// `SqlDialect` instance is the per-backend strategy that handles that
/// generation; backends compose a `PersistentStore` subclass with a
/// `SqlDialect` to land a working backend.
///
/// Defaults on this class lean toward **standard / ANSI SQL** so a subclass
/// only has to override the bits where it diverges. The Postgres
/// implementation in `package:conduit_postgresql` is a useful reference;
/// SQLite and MySQL implementations mostly come down to overriding the
/// type-map, parameter syntax, and version-table name.
///
/// This class is a value: instances should be cheap to construct and
/// allocation-free on the hot path. Concrete implementations should not
/// hold connection state — that lives on the `PersistentStore`.
library;

abstract class SqlDialect {
  const SqlDialect();

  /// Short name used to suffix the version table and to differentiate
  /// dialects in error messages and logs. e.g. 'postgres', 'sqlite',
  /// 'mysql', 'cockroach'.
  String get name;

  // -- Type mapping -----------------------------------------------------------

  /// Map a Conduit `ManagedPropertyType.toString()` (one of `integer`,
  /// `bigInteger`, `string`, `datetime`, `boolean`, `double`, `document`) to
  /// the dialect-specific column-definition type string.
  ///
  /// Returning `null` signals "not a supported type for this dialect" —
  /// callers handle by raising a clear schema error.
  String? columnDefinitionType(String typeString, {required bool autoincrement});

  // -- Parameter placeholder syntax -------------------------------------------

  /// How to refer to a named parameter inside a SQL string. Default is
  /// `@name` (Postgres named-parameter convention). MySQL/SQLite
  /// implementations typically override to `?` (positional) or `:name`
  /// (named).
  String parameterPlaceholder(String name) => '@$name';

  // -- Comparison + matching operators ----------------------------------------

  /// Operator for case-sensitive pattern match. Standard SQL: `LIKE`.
  String get caseSensitiveLikeOperator => 'LIKE';

  /// Operator for case-insensitive pattern match. Standard SQL has no
  /// equivalent; SQLite's `LIKE` is case-insensitive by default; MySQL
  /// uses `LIKE` with a case-insensitive collation; Postgres has `ILIKE`.
  /// Default echoes `LIKE`; backends override as needed.
  String get caseInsensitiveLikeOperator => 'LIKE';

  /// Standard SQL: `IS NULL`. Postgres also accepts the shorthand `ISNULL`
  /// — which the current PG path uses. Override if backend differs.
  String get isNullOperator => 'IS NULL';
  String get isNotNullOperator => 'IS NOT NULL';

  // -- DDL conventions --------------------------------------------------------

  /// Standard SQL: `ALTER TABLE`. Postgres uses `ALTER TABLE ONLY` for
  /// constraint modifications to avoid recursing into inheritance children
  /// — that's the only known divergence.
  String get alterTableForConstraintModification => 'ALTER TABLE';

  /// Suggested name for a unique constraint backing a single column.
  String uniqueKeyName(String tableName, String columnName) =>
      '${tableName}_${columnName}_key';

  /// Suggested name for a foreign-key constraint.
  String foreignKeyName(String tableName, String columnName) =>
      '${tableName}_${columnName}_fkey';

  /// Suggested name for an index on a single column.
  String indexName(String tableName, String columnName) =>
      '${tableName}_${columnName}_idx';

  // -- Schema-version bookkeeping --------------------------------------------

  /// The table conduit creates to track applied migration versions.
  /// Suffixed by [name] so concurrent multi-dialect applications don't
  /// collide on the same physical database (rare, but cheap insurance).
  String get versionTableName => '_conduit_version_$name';

  /// Returns SQL that, when executed with a single named parameter
  /// `tableName`, yields one row whose first column is non-null when the
  /// table exists.
  ///
  /// Postgres uses `SELECT to_regclass(@tableName:text)`; SQLite reads
  /// `sqlite_master`; MySQL queries `information_schema.tables`. Each
  /// dialect's exact form is its own concern.
  String tableExistsQuery();

  // -- LIKE-pattern escaping --------------------------------------------------

  /// Escapes wildcard characters in a user-supplied LIKE pattern so they
  /// match literally. Default escapes `\\`, `%`, and `_` with a leading
  /// backslash, which is the Postgres / SQLite / MySQL convention when
  /// the default ESCAPE character is in effect.
  String escapeLikePattern(String input) {
    return input.replaceAllMapped(
      RegExp(r'(\\|%|_)'),
      (m) => '\\${m[0]}',
    );
  }
}
