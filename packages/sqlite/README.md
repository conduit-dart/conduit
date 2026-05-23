# conduit_sqlite

SQLite ORM backend for [Conduit](https://github.com/conduit-dart/conduit).
Embedded and in-process — closes the test-harness gap by enabling
no-Docker test fixtures, and supports edge / single-file deployments.

See [`doc/usage.md`](doc/usage.md) for the integration walkthrough.

## Status

Published from the Conduit 7.0.0 release. v1 is JIT-only: the
`conduit_build_runner` `ManagedObjectBuilder` does not yet support
`@Relate`, so non-trivial ORM apps cannot AOT-compile against this
backend until that lands.
