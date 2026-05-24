# conduit_mysql

MySQL / MariaDB ORM backend for [Conduit](https://github.com/conduit-dart/conduit).
Schema management, raw execute path, and the dialect-agnostic ORM
`newQuery<T>` lifted from `conduit_postgresql`.

See [`doc/usage.md`](doc/usage.md) for the integration walkthrough.

## Status

Published from the Conduit 7.0.0 release. Treat the public API as
stable; corner cases that the Postgres backend covers but MySQL does
not are tracked in `doc/usage.md`.
