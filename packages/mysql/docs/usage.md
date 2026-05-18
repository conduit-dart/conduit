# `conduit_mysql`

MySQL / MariaDB backend for the Conduit ORM. v0 surface mirrors
`conduit_sqlite`: schema management + migrations + raw `execute`. The
ORM `newQuery<T>` path is deferred (same blocker as SQLite — the
predicate builders need to be extracted from `conduit_postgresql` into
core).

## Install

```yaml
# pubspec.yaml
dependencies:
  conduit_mysql: ^6.0.0
```

The driver is `package:mysql_dart` 1.2+, native Dart, tested against
MySQL 5.7 / 8 and MariaDB 10 / 11.

## Connection string

```
mysql://user:password@host:3306/database
```

The default port (3306) is filled in if omitted. The driver accepts
both `:name` and positional `?` placeholders; this backend uses
positional `?` to match `MysqlSqlDialect.parameterPlaceholder` and the
predicate AST's positional render path.

## Programmatic construction

```dart
import 'package:conduit_mysql/conduit_mysql.dart';

final store = MysqlPersistentStore(
  'root', 'hunter2', '127.0.0.1', 3306, 'mydb',
);
```

## Capabilities

- Schema management + migrations.
- Raw `execute` / `executeQuery` with positional `?` parameters.
- Transactions.
- MariaDB compatibility (the same driver works for both; the store
  records `isMariaDB` for callers that need to branch).

## Limitations

- **`newQuery<T>` is `UnimplementedError`.** Same story as SQLite;
  tracked alongside the AST migration in `conduit_core`.
- **No schema generation portability for `JSONB`.** MySQL maps
  `ManagedPropertyType.document` to `JSON`; behavior aligns with
  Postgres for `Document` round-trips but operators differ
  (`->`, `->>` vs `@>`, `?`).
- **No `RETURNING` clause.** Inserts that need the generated PK must
  follow up with `SELECT LAST_INSERT_ID()` (or rely on the driver's
  `affectedRows`). Postgres-only tests should be marked with
  `@SkipOn([Dialect.mysql])` to opt out.
- **Case sensitivity** depends on the table's collation. `LIKE BINARY`
  is the portable case-sensitive form.

## Canonical example

See `packages/mysql/test/` for direct exercises of the dialect and
schema generator. End-to-end multi-backend tests live in
`packages/test_harness/test/integration/multi_backend_test.dart` —
extend that file with a MySQL leg gated on a real MySQL being
available in the test environment when you stand one up.
