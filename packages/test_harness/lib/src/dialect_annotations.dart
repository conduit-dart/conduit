/// Test fanout annotations for the multi-backend ORM rollout.
///
/// As `conduit_postgresql`, `conduit_sqlite`, `conduit_mysql`, and the
/// in-flight `conduit_cockroach` ship, the existing 291-test ORM
/// regression suite needs to **fanout across backends** — i.e., run
/// every dialect-agnostic ORM test against each backend's
/// `PersistentStore`, and skip backend-specific tests on the wrong
/// backend. The annotations defined here name the contract; the
/// runner that consumes them lands in a follow-up PR (it has to
/// teach `package:test`'s tag-filtering mechanism + a
/// `--dialect=<name>` switch to the harness).
///
/// **Usage in test files** (when wired):
///
/// ```dart
/// // Test only meaningful against Postgres' jsonb operators.
/// @OnlyOn([Dialect.postgres])
/// test('jsonb @> operator round-trips a Document', () { ... });
///
/// // Test that exercises a behavior MySQL doesn't support.
/// @SkipOn([Dialect.mysql], reason: 'MySQL has no RETURNING clause')
/// test('insert RETURNING captures generated PK without a follow-up SELECT',
///     () { ... });
/// ```
///
/// **Default semantics.** A test with no annotation runs against
/// every registered dialect — the most common case, and the goal of
/// the multi-backend migration.
///
/// We deliberately don't tie this to `package:test`'s `Tags`
/// machinery yet because (a) tag values are stringly-typed and easy
/// to fat-finger, and (b) we want the IDE-level type-check that
/// comes from a sealed enum. The runner can lower these to tags at
/// dispatch time.
library;

/// Catalog of dialects the test harness recognizes. Add to this list
/// when a new backend lands.
enum Dialect {
  /// `package:conduit_postgresql` (Phase 0; the original backend).
  postgres,

  /// `package:conduit_sqlite` (Phase 2). Schema + raw `execute` only
  /// in v0; ORM `newQuery<T>` deferred.
  sqlite,

  /// `package:conduit_mysql` (Phase 4). Same v0 surface as SQLite —
  /// schema + raw `execute`. ORM `newQuery<T>` deferred.
  mysql,

  /// `package:conduit_cockroach` (Phase 3, in review). Mostly a
  /// Postgres super-set; flagged separately for behavior-divergence
  /// gating.
  cockroach,
}

/// Run this test only against the listed dialects. If the runner
/// is not currently dispatching against any of the listed dialects,
/// the test is skipped with a clear reason.
class OnlyOn {
  const OnlyOn(this.dialects, {this.reason});

  final List<Dialect> dialects;
  final String? reason;
}

/// Skip this test when running against any of the listed dialects.
/// Use when the test exercises a feature the backend explicitly
/// doesn't support, or where a known bug is tracked separately.
class SkipOn {
  const SkipOn(this.dialects, {this.reason});

  final List<Dialect> dialects;
  final String? reason;
}

/// Convenience: shorthand for the most common case — a test that
/// only makes sense for Postgres because it touches a Postgres-only
/// feature (`ILIKE`, `JSONB`, `RETURNING`, `to_regclass`).
class PostgresOnly extends OnlyOn {
  const PostgresOnly({String? reason})
      : super(const [Dialect.postgres], reason: reason);
}
