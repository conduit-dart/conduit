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

Published from the Conduit 7.0.0 release. Schema management + migrations,
transactions (with `SAVEPOINT` nesting), and the raw execute path are
supported; foreign keys are enforced on open. The ORM `newQuery<T>` path is
not yet implemented (blocked on extracting query builders from
`conduit_postgresql` into core), and v1 is JIT-only — the
`conduit_build_runner` `ManagedObjectBuilder` does not yet support
`@Relate`, so non-trivial ORM apps cannot AOT-compile against this backend
until that lands. Details in [`doc/usage.md`](doc/usage.md).
