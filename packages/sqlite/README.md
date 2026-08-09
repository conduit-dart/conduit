# conduit_sqlite

SQLite backend for the [Conduit](https://github.com/conduit-dart/conduit)
ORM. Embedded and in-process (via `package:sqlite3`) — enables no-Docker
test fixtures and edge / single-file deployments.

## Install

```yaml
dependencies:
  conduit_sqlite: ^7.0.0
```

`package:sqlite3` loads the system `libsqlite3` at runtime; on Windows you
may need to ship `sqlite3.dll` alongside your binary.

## Use

```dart
import 'package:conduit_sqlite/conduit_sqlite.dart';

final memStore = SqlitePersistentStore.memory();
final fileStore = SqlitePersistentStore.file('/tmp/conduit.db');
```

Connection-string forms: `sqlite::memory:`,
`sqlite:///absolute/path/file.db`, `sqlite://relative/path/file.db`.

## Status

Published from the Conduit 7.0.0 release. The full `Query<T>` ORM path
is wired: CRUD, predicates, `belongsTo`/`hasMany` joins, paging,
`reduce`, and `Document` (JSON-as-TEXT) columns all work — alongside
schema management, migrations, and raw `execute`.

One caveat for relational apps: the `conduit_build_runner`
`ManagedObjectBuilder` is still Phase-1 (single-table, no `@Relate`), so
apps with relationships run against SQLite under the JIT/mirrors runtime
rather than AOT-compiled. See [`doc/usage.md`](doc/usage.md) for the full
capability + limitation matrix.
