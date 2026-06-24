# conduit_sqlite

SQLite ORM backend for [Conduit](https://github.com/conduit-dart/conduit).
Embedded and in-process — closes the test-harness gap by enabling
no-Docker test fixtures, and supports edge / single-file deployments.

See [`doc/usage.md`](doc/usage.md) for the integration walkthrough.

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
