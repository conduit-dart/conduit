# `conduit_sqlite`

SQLite backend for the Conduit ORM. Embedded / in-process — closes the
test-harness gap by enabling fixture databases without standing up
Docker.

## Install

```yaml
# pubspec.yaml
dependencies:
  conduit_sqlite: ^7.0.0
```

The package depends on `package:sqlite3` (which loads the system
`libsqlite3` at runtime). On Linux/macOS the system library is
typically present; on Windows you may need to ship a `sqlite3.dll`
alongside your binary — see the `sqlite3` package README.

## Connection string

```
sqlite::memory:                       # in-memory database, gone on close
sqlite:///absolute/path/to/file.db    # absolute file path
sqlite://relative/path/file.db        # path relative to CWD
```

Recognised by `parseConnectionString` in `conduit/src/connection_string.dart`.

## Programmatic construction

```dart
import 'package:conduit_sqlite/conduit_sqlite.dart';

final memStore = SqlitePersistentStore.memory();
final fileStore = SqlitePersistentStore.file('/tmp/conduit.db');
```

## Capabilities

- **Full `Query<T>` ORM path** via `newQuery<T>`: insert / insertMany,
  fetch / fetchOne, update / updateOne, delete, `reduce` aggregates, and
  the standard predicate matchers (`equalTo`, `lessThan`, `oneOf`,
  `contains`, `isNull`, …), sorting, and `fetchLimit` / `offset` paging.
- **Relationship joins** — `belongsTo` (`join(object:)`) and `hasMany`
  `ManagedSet` eager-fetch (`join(set:)`).
- **`Document` columns** stored as JSON text: the payload is JSON-encoded
  on write and decoded on read, so `Document` round-trips Maps, Lists,
  and scalars.
- Schema management + migrations (full DDL surface — create/drop
  table, add/drop/rename column, add/drop indexes).
- Raw `execute` / `executeQuery` with named parameters (`:name`).
- Transactions with `SAVEPOINT` for nesting.
- Foreign-key enforcement is enabled on open (`PRAGMA foreign_keys = ON`).

## Limitations

- **AOT codegen is not yet wired for relational models.** The
  `conduit_build_runner` `ManagedObjectBuilder` is Phase-1 (single-table,
  no `@Relate`), so apps that use relationships must run against SQLite
  under the JIT / mirrors runtime (`dart run`, `dart test`) rather than an
  AOT build. Single-table models AOT-compile fine.
- **In-place `ALTER COLUMN` is unsupported.** SQLite cannot alter a
  column's nullability, uniqueness, default value, or delete-rule in
  place; those migration operations throw `UnsupportedError` instead of
  emitting the "create temp table + copy + drop + rename" rebuild. Run
  such migrations against Postgres, or write the rebuild manually.
- Sub-document predicate operators (Postgres `jsonb` `->` / `->>` path
  queries) are not available — `Document` columns store and return whole
  payloads only.
- No `RETURNING` clause server-side (the backend selects the row back by
  primary key after an insert / update — handled transparently).
- No native UUID type — store UUIDs as text.
- `ILIKE` is not supported; use `LIKE` (SQLite is case-insensitive
  by default for ASCII; use a `COLLATE BINARY` clause for case-sensitive
  matches).

## Canonical example

The ORM regression suite under `packages/sqlite/test/orm_test.dart`
exercises the full `newQuery<T>` path (CRUD, predicates, joins, paging,
`Document`, reduce) against an in-memory store. The integration test
under `packages/test_harness/test/integration/multi_backend_test.dart`
additionally exercises the schema-builder + raw-execute path. Use either
as the reference for hooking SQLite into a `TestHarness<T>` subclass:

```dart
class MyHarness extends TestHarness<MyChannel> with TestHarnessORMMixin {
  MyHarness() {
    persistence = () => SqlitePersistentStore.memory();
  }
  @override
  ManagedContext? get context => channel?.context;
}
```
