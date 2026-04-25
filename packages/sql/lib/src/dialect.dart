import 'package:meta/meta.dart';

/// What an ORM backend must answer about its own SQL.
///
/// One concrete subclass per supported database (Postgres, MySQL,
/// SQLite, …). The shared SQL builders in `conduit_sql` consult an
/// instance of this class for every dialect-specific decision: how
/// identifiers are quoted, how parameters are referenced, what DDL
/// type names mean, and which optional features (RETURNING, JSON,
/// upsert) are available.
///
/// **Phase 0 scaffold.** This interface defines the surface; the
/// shared builders that consume it are extracted from
/// `packages/postgresql/` in phase 1. See `docs/GENERAL_ORM.md`.
@experimental
abstract class Dialect {
  const Dialect();

  /// Human-readable name for diagnostics (`'postgres'`, `'mysql'`).
  String get name;

  /// Wrap an identifier (table name, column name) for the dialect's
  /// quoting rules. Postgres `"foo"`, MySQL `` `foo` ``,
  /// MSSQL `[foo]`.
  String quoteIdentifier(String identifier);

  /// Reference parameter [index] (1-based) inside a SQL string.
  /// Postgres `@name` / `$N`, MySQL `?`, SQLite `?N`.
  String parameterReference(int index, {String? name});

  /// DDL type for an auto-incrementing primary key column.
  /// Postgres `BIGSERIAL`, MySQL `BIGINT AUTO_INCREMENT`,
  /// SQLite `INTEGER PRIMARY KEY AUTOINCREMENT`.
  String autoIncrementColumnType();

  /// DDL type name for the given Conduit managed property type.
  ///
  /// `propertyType` is a stringified `ManagedPropertyType` value
  /// (e.g. `'integer'`, `'string'`, `'datetime'`, `'document'`).
  /// Returning `null` signals the property type is unsupported by
  /// this dialect, in which case the caller raises a clearer error
  /// than the database driver would.
  String? columnTypeFor(String propertyType);

  /// Boolean literal text for [value]. Postgres `TRUE`/`FALSE`;
  /// MySQL `1`/`0`.
  String booleanLiteral(bool value);

  /// Capability flags. The shared SQL builders branch on these to
  /// pick the right code path per backend.
  DialectCapabilities get capabilities;
}

/// Optional features a dialect may or may not implement.
///
/// Grows additively as the shared builders learn to use more dialect
/// features. Defaults are conservative — a brand-new adapter that
/// constructs `DialectCapabilities()` with no overrides gets the
/// most-portable behavior.
@immutable
class DialectCapabilities {
  const DialectCapabilities({
    this.supportsReturning = false,
    this.supportsUpsert = false,
    this.supportsJsonColumn = false,
    this.supportsCheckConstraints = false,
    this.maxIdentifierLength = 63,
  });

  /// True if INSERT/UPDATE/DELETE can return rows in a single
  /// round-trip (`RETURNING` clause). Postgres: yes. MySQL 8.0+:
  /// partial. SQLite: no — needs a follow-up `last_insert_rowid()`.
  final bool supportsReturning;

  /// True if the dialect has native upsert (`ON CONFLICT … DO …`,
  /// `ON DUPLICATE KEY UPDATE`).
  final bool supportsUpsert;

  /// True if a structured-JSON column type exists (`JSONB`, `JSON`).
  /// False forces the ORM to store JSON as text.
  final bool supportsJsonColumn;

  /// True if `CHECK` constraints are enforced. MySQL parses but
  /// historically did not enforce them.
  final bool supportsCheckConstraints;

  /// Maximum identifier length. Postgres 63. MySQL 64. SQLite 1MB
  /// in theory; treat as effectively unlimited.
  final int maxIdentifierLength;
}
