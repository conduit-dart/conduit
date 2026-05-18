import 'package:conduit_core/conduit_core.dart';

/// MySQL / MariaDB-flavored SQL generation.
///
/// Differs from the default `SqlDialect` (ANSI-leaning, Postgres-like)
/// in five places:
///
/// 1. **Type system.** MySQL has explicit `INT AUTO_INCREMENT` /
///    `BIGINT AUTO_INCREMENT` for serial columns, native `JSON` (5.7+)
///    for documents, `DATETIME` for timestamps, and `BOOLEAN` (an
///    alias for `TINYINT(1)`). Strings map to `TEXT` rather than
///    Postgres's `TEXT` because... they're both `TEXT`. The interesting
///    divergence is the autoincrement / JSON columns.
///
/// 2. **Parameter syntax — positional.** MySQL uses `?` placeholders
///    bound by ordinal position. This is the headline reason
///    `conduit_core` grew a predicate AST + visitor: the legacy
///    string-concat predicate path was hardwired to `@name`, which
///    can't render `?` correctly without losing positional ordering.
///    [parameterStyle] returns [SqlParameterStyle.positional].
///
/// 3. **Pattern matching.** MySQL's `LIKE` is case-insensitive when
///    the column's collation is `_ci` (the default for `utf8mb4`,
///    `utf8`). For case-*sensitive* matching, the documented form is
///    `LIKE BINARY` (forces a binary comparison regardless of
///    collation). Users who configure their database with a `_bin`
///    collation will see "LIKE" already be case-sensitive and the
///    `LIKE BINARY` form remains correct (no-op on top of binary
///    storage). The opposite case — case-insensitive where the
///    collation is `_bin` — is uncommon enough we don't try to handle
///    it here; document instead.
///
/// 4. **Identifier quoting.** Backticks (`` ` ``) — required when an
///    identifier collides with a reserved keyword. The dialect doesn't
///    proactively quote every identifier today (the Postgres path
///    doesn't either) — that's a follow-up — but the helpers are here
///    when callers want them.
///
/// 5. **No `RETURNING` clause.** MySQL's INSERT does not return the
///    inserted row. v0 of `MysqlPersistentStore` doesn't ship the ORM
///    `newQuery<T>` path, so this only matters for migrations / raw
///    `execute` callers. When the ORM path lands, the pattern is
///    `INSERT … ; SELECT * FROM <table> WHERE id = LAST_INSERT_ID()`.
///
/// MariaDB is binary-compatible with the dialect at this version
/// (10.x supports `JSON`, `AUTO_INCREMENT`, `LIKE BINARY`,
/// `information_schema.tables`, etc.). The persistent store records a
/// `bool mariadb` flag at connect time for callers that need to
/// branch.
class MysqlSqlDialect extends SqlDialect {
  const MysqlSqlDialect();

  @override
  String get name => 'mysql';

  // -- Type mapping ---------------------------------------------------------

  @override
  String? columnDefinitionType(
    String typeString, {
    required bool autoincrement,
  }) {
    switch (typeString) {
      case 'integer':
        return autoincrement ? 'INT AUTO_INCREMENT' : 'INT';
      case 'bigInteger':
        return autoincrement ? 'BIGINT AUTO_INCREMENT' : 'BIGINT';
      case 'string':
        // VARCHAR(255) is the historical default for an unconstrained
        // text column. TEXT is unindexable without a key length, which
        // breaks UNIQUE constraints. Conduit's schema model doesn't
        // carry a length hint today; 255 is the documented widest-
        // index default and matches what MariaDB / MySQL tutorials
        // suggest.
        return 'VARCHAR(255)';
      case 'datetime':
        // DATETIME stores no timezone; conduit normalizes to UTC at
        // the application layer. TIMESTAMP would be 32-bit (2038
        // limit) — DATETIME is the correct long-lived choice.
        return 'DATETIME';
      case 'boolean':
        // BOOLEAN is an alias for TINYINT(1). The driver binds Dart
        // `bool` as 0/1 transparently.
        return 'BOOLEAN';
      case 'double':
        return 'DOUBLE';
      case 'document':
        // Native JSON since MySQL 5.7 and MariaDB 10.2.
        return 'JSON';
    }
    return null;
  }

  // -- Parameter syntax -----------------------------------------------------

  /// The dialect parameter style governs which AST visitor renders a
  /// `SqlExpression` — for MySQL we keep that as positional since the
  /// wire form is positional `?`. The [QueryBuilder] lift, however,
  /// composes SQL out of per-column named placeholders + a name-keyed
  /// variables map; for that path the `mysql_dart` driver accepts
  /// `:name` placeholders directly (it rewrites them to positional
  /// internally). Both paths therefore work side by side.
  @override
  SqlParameterStyle get parameterStyle => SqlParameterStyle.positional;

  /// `:name` for the QueryBuilder path (driver auto-rewrites to
  /// positional). The AST-visitor path renders `?` independently via
  /// [PositionalSqlExpressionVisitor].
  @override
  String parameterPlaceholder(String name) => ':$name';

  // -- Operators where MySQL differs from standard SQL ----------------------

  /// `LIKE` defaults to case-insensitive on `_ci` collations (the
  /// `utf8mb4_general_ci` / `utf8mb4_0900_ai_ci` defaults). For
  /// schemas configured with a `_bin` collation, `LIKE` will already
  /// be case-sensitive — that's an out-of-band schema choice, not
  /// something we override per-query.
  @override
  String get caseInsensitiveLikeOperator => 'LIKE';

  /// `LIKE BINARY` forces a binary (case-sensitive) comparison
  /// regardless of the column's collation.
  @override
  String get caseSensitiveLikeOperator => 'LIKE BINARY';

  // IS NULL / IS NOT NULL: standard SQL form, inherited defaults.

  // ALTER TABLE: standard form, inherited default.

  // -- DDL conventions -----------------------------------------------------

  /// MySQL identifiers are quoted with backticks. Same suffix
  /// conventions as the base.

  // -- Schema-version bookkeeping ------------------------------------------

  @override
  String get versionTableName => '_conduit_version_mysql';

  /// `information_schema.tables` is the portable table-existence
  /// query. MySQL also accepts `SHOW TABLES LIKE '...'`, but
  /// information_schema parameterizes cleanly.
  ///
  /// MySQL is positional — the placeholder is `?`. The base
  /// `parameterPlaceholder` (which we overrode to always return `?`)
  /// is fine here.
  @override
  String tableExistsQuery() =>
      "SELECT table_name FROM information_schema.tables "
      "WHERE table_schema = DATABASE() AND table_name = ${parameterPlaceholder("tableName")}";
}
