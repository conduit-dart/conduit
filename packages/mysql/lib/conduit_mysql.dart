/// MySQL / MariaDB backend for the Conduit ORM.
///
/// **v0 scope** parallels `conduit_sqlite`:
///   * `MysqlSqlDialect` — column-type map, identifier-quoting,
///     positional `?` parameters, `LIKE BINARY` for case-sensitive
///     pattern matching, and an `information_schema.tables`-based
///     table-existence query.
///   * `MysqlPersistentStore` — schema management (DDL via
///     `MysqlSchemaGenerator`), migrations, raw `execute` /
///     `executeQuery`, transactions. The full ORM `newQuery<T>` path
///     remains `UnimplementedError` until the predicate AST migration
///     in `conduit_core` is paired with an extraction of the query
///     builders from `conduit_postgresql`. SQLite is in the same boat;
///     unblocking is tracked in a follow-up.
///
/// MariaDB compatibility: the same driver works for both databases.
/// On connect, `MysqlPersistentStore` checks `SELECT VERSION()` and
/// records whether the server is MariaDB; that's exposed for callers
/// that need to branch but the dialect itself doesn't diverge in v0.
library;

export 'src/mysql_persistent_store.dart';
export 'src/mysql_schema_generator.dart';
export 'src/mysql_sql_dialect.dart';
