import 'package:conduit_core/conduit_core.dart';

/// SQLite-flavored SQL generation. Differs from the default `SqlDialect`
/// (ANSI-leaning, Postgres-like) in three places:
///
/// 1. **Type system.** SQLite has only 5 storage classes
///    (INTEGER, REAL, TEXT, BLOB, NULL). Conduit's `integer`, `bigInteger`,
///    `boolean` all map to `INTEGER`; `double` maps to `REAL`; everything
///    else (strings, JSON, datetimes) maps to `TEXT`. SQLite stores
///    datetimes as ISO-8601 text by convention; JSON as text with no
///    server-side validation (the `json1` extension parses it on access).
///
/// 2. **Auto-increment.** SQLite has implicit ROWID auto-increment for
///    any `INTEGER PRIMARY KEY` column; the explicit `AUTOINCREMENT`
///    keyword is rarely needed and slows inserts. Mapping a Conduit
///    auto-increment column to plain `INTEGER PRIMARY KEY` is the
///    idiomatic choice — but autoincrement-only columns (i.e., not
///    primary keys) are not supported by SQLite at all and would need to
///    be rejected at schema-validation time.
///
/// 3. **Parameter syntax.** The default Postgres-style `@name` is not
///    a SQLite placeholder. SQLite accepts `:name`, `@name`, `?NNN`, or
///    `?` — we standardize on `:name` for parity with the named-parameter
///    semantics used throughout the framework.
///
/// Constraint-modification (`ALTER TABLE`) is constrained in SQLite —
/// see `package:conduit_sqlite` docs. This dialect emits the standard
/// `ALTER TABLE` form; backends invoking actual column alterations
/// against SQLite need to fall back to the "create temp + copy +
/// rename" pattern, which the schema generator handles separately.
class SqliteSqlDialect extends SqlDialect {
  const SqliteSqlDialect();

  @override
  String get name => 'sqlite';

  // -- Type mapping ----------------------------------------------------------

  @override
  String? columnDefinitionType(
    String typeString, {
    required bool autoincrement,
  }) {
    switch (typeString) {
      case 'integer':
      case 'bigInteger':
        // SQLite uses dynamic typing; INTEGER covers both 4- and 8-byte
        // ranges. `INTEGER PRIMARY KEY` is the auto-increment idiom; the
        // schema generator handles the PRIMARY KEY suffix separately, so
        // we just emit INTEGER and let it compose.
        return 'INTEGER';
      case 'string':
        return 'TEXT';
      case 'datetime':
        // ISO-8601 text by Conduit convention. SQLite has no native
        // timestamp type; the existing `datetime()` SQL function reads
        // and writes ISO strings.
        return 'TEXT';
      case 'boolean':
        // 0/1 stored as INTEGER. The `bool` Dart values are bound as
        // 0/1 by the driver.
        return 'INTEGER';
      case 'double':
        return 'REAL';
      case 'document':
        // JSON stored as TEXT. The `json1` extension parses on access.
        return 'TEXT';
    }
    return null;
  }

  // -- Parameter syntax ------------------------------------------------------

  /// SQLite accepts `@name`, `:name`, `?NNN`, and `?`. We use `:name` for
  /// parity with the named-parameter semantics used elsewhere.
  @override
  String parameterPlaceholder(String name) => ':$name';

  // -- Operators where SQLite differs from standard / Postgres --------------

  /// SQLite's `LIKE` is case-insensitive by default for ASCII characters;
  /// it does not have an `ILIKE` operator. We emit `LIKE` for both
  /// case-sensitive and case-insensitive matches. Apps requiring
  /// strict case-sensitive `LIKE` should issue
  /// `PRAGMA case_sensitive_like = ON;` once at connection setup; per-query
  /// dialect divergence is not exposed here (would force a recompilation
  /// of every prepared statement).
  @override
  String get caseInsensitiveLikeOperator => 'LIKE';

  // SQLite uses standard `IS NULL` / `IS NOT NULL` (the inherited defaults
  // are correct).

  // SQLite's `ALTER TABLE` is the only form (no `ALTER TABLE ONLY`); the
  // inherited default is correct.

  // -- Schema-version bookkeeping --------------------------------------------

  @override
  String get versionTableName => '_conduit_version_sqlite';

  /// `sqlite_master` is the canonical metadata table. The query yields
  /// one row whose first column is the table name when it exists, or no
  /// rows otherwise — the existence-check call site reads
  /// `result.first.first != null`.
  @override
  String tableExistsQuery() =>
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name = ${parameterPlaceholder("tableName")}";
}
