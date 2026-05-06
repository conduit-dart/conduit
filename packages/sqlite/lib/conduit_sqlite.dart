/// SQLite backend for the Conduit ORM.
///
/// **v0 scope: schema management + migrations + raw SQL execution.** The
/// full ORM query path (`Query<T>` → predicates → joins → mapped
/// results) is deferred until conduit's query builders move out of the
/// postgresql package into core; until then, `newQuery<T>` throws
/// `UnimplementedError`.
///
/// Why ship before the ORM path is wired: the schema + migration half
/// is what closes the test-harness gap — apps can run migrations
/// against an in-memory SQLite database without standing up Postgres in
/// Docker.
library;

export 'package:conduit_sqlite/src/sqlite_persistent_store.dart';
export 'package:conduit_sqlite/src/sqlite_schema_generator.dart';
export 'package:conduit_sqlite/src/sqlite_sql_dialect.dart';
