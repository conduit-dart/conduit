/// SQLite backend for the Conduit ORM.
///
/// **Scope: schema management + migrations + raw SQL execution + the
/// full `Query<T>` ORM path.** Now that conduit's query builders live in
/// the dialect-agnostic core (`QueryBuilder`/`ColumnBuilder`), `newQuery<T>`
/// composes INSERT / UPDATE / DELETE / SELECT off the shared builders:
/// CRUD, predicates, `belongsTo`/`hasMany` joins, paging, `reduce`, and
/// `Document` (JSON-as-TEXT) columns all work — see `test/orm_test.dart`.
///
/// In addition to running the ORM, the schema + migration half closes
/// the test-harness gap: apps can run migrations against an in-memory
/// SQLite database without standing up Postgres in Docker.
///
/// **Two remaining limitations**, both documented in `doc/usage.md`:
///  * *AOT codegen.* The `conduit_build_runner` `ManagedObjectBuilder` is
///    Phase-1 (single-table, no `@Relate`), so apps with relationships
///    run against SQLite under the JIT/mirrors runtime, not AOT.
///  * *`ALTER COLUMN`.* SQLite cannot alter a column's nullability,
///    uniqueness, default, or delete-rule in place; those migration ops
///    throw `UnsupportedError` rather than emit a table-rebuild.
library;

export 'package:conduit_sqlite/src/sqlite_persistent_store.dart';
export 'package:conduit_sqlite/src/sqlite_schema_generator.dart';
export 'package:conduit_sqlite/src/sqlite_sql_dialect.dart';
