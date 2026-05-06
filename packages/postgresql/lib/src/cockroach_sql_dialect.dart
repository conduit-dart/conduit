import 'postgres_sql_dialect.dart';

/// CockroachDB-flavored SQL generation. Cockroach is Postgres-wire-
/// compatible at the protocol layer (apps using `package:postgres`
/// connect, authenticate, and execute parameterized SQL identically),
/// so the existing [PostgresSqlDialect] is the right starting point
/// — this subclass overrides only the small DDL divergences.
///
/// Known divergences this dialect handles:
///
/// - **`IS NULL` / `IS NOT NULL`.** Postgres accepts the shorthand
///   `expr ISNULL` / `expr NOTNULL`; CockroachDB does not (it expects
///   the standard SQL form). The base `PostgresSqlDialect` emits the
///   shorthand for historical compatibility; this subclass restores
///   the standard form.
/// - **Version-table name.** Suffix changes from `_conduit_version_pgsql`
///   to `_conduit_version_cockroach` so the same physical database can
///   host applications targeting both dialects without colliding on
///   the bookkeeping table. (The default `PostgresSqlDialect` already
///   namespaces by dialect name; we just want the cockroach suffix.)
///
/// Known divergences this dialect does NOT handle (still source-side
/// concerns, not framework concerns):
///
/// - `SERIAL` / `BIGSERIAL` semantics. Cockroach maps both to `INT8`
///   with a `unique_rowid()` default, returning 64-bit globally-unique
///   IDs — Postgres' `SERIAL` is `INT4` with a sequence. Apps that
///   require small/sequential IDs in Cockroach should use
///   `INT DEFAULT unique_rowid()` explicitly in their migrations rather
///   than rely on `SERIAL`. Conduit's auto-increment column emission
///   uses `SERIAL` regardless — works in both, behaves slightly
///   differently in Cockroach.
/// - `ALTER TABLE ONLY` is accepted by Cockroach (no-op without table
///   inheritance), so the inherited override is fine.
///
/// Apps wanting Cockroach should construct their persistent store like
/// so:
///
/// ```dart
/// final store = PostgreSQLPersistentStore(
///   user, password, host, port, db,
///   dialect: const CockroachSqlDialect(),
/// );
/// ```
///
/// Reference: see `packages/postgresql/docs/cockroach.md` for runtime
/// caveats not expressible at the dialect layer (transaction retry,
/// SERIAL semantics, schema-introspection differences).
class CockroachSqlDialect extends PostgresSqlDialect {
  const CockroachSqlDialect();

  @override
  String get name => 'cockroach';

  @override
  String get isNullOperator => 'IS NULL';

  @override
  String get isNotNullOperator => 'IS NOT NULL';

  /// Override of the inherited `_conduit_version_pgsql` so multi-dialect
  /// applications hitting the same physical database don't collide.
  @override
  String get versionTableName => '_conduit_version_cockroach';
}
