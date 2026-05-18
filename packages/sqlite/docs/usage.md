# `conduit_sqlite`

SQLite backend for the Conduit ORM. Embedded / in-process — closes the
test-harness gap by enabling fixture databases without standing up
Docker.

## Install

```yaml
# pubspec.yaml
dependencies:
  conduit_sqlite: ^6.0.0
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

- Schema management + migrations (full DDL surface — create/drop
  table, add/drop/rename column, add/drop indexes).
- Raw `execute` / `executeQuery` with named parameters (`:name`).
- Transactions with `SAVEPOINT` for nesting.
- Foreign-key enforcement is enabled on open (`PRAGMA foreign_keys = ON`).

## Limitations

- **`newQuery<T>` is `UnimplementedError`.** The full ORM query path
  (predicate construction, joins, returning rows as `ManagedObject`s)
  requires the postgresql package's query builders to be extracted
  into core; that refactor is tracked separately. For now, use raw
  `execute` for arbitrary queries against SQLite.
- No `RETURNING` clause (use `last_insert_rowid()` after an insert).
- No native UUID type — store UUIDs as text.
- `ILIKE` is not supported; use `LIKE` (SQLite is case-insensitive
  by default for ASCII; use `LIKE BINARY` semantics via `COLLATE`
  for case-sensitive matches).

See the broader multi-backend ORM roadmap for `newQuery<T>` progress.

## Canonical example

The integration test under
`packages/test_harness/test/integration/multi_backend_test.dart`
exercises the schema-builder + raw-execute path against an in-memory
SQLite store. Use it as the reference for hooking SQLite into a
`TestHarness<T>` subclass:

```dart
class MyHarness extends TestHarness<MyChannel> with TestHarnessORMMixin {
  MyHarness() {
    persistence = () => SqlitePersistentStore.memory();
  }
  @override
  ManagedContext? get context => channel?.context;
}
```
