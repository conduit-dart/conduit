# `conduit_postgresql`

The original Conduit ORM backend. Targets PostgreSQL 12+ via the
`postgres` Dart driver. CockroachDB is also supported via this package
(it speaks the Postgres wire protocol); see the **Cockroach** section
below.

## Install

```yaml
# pubspec.yaml
dependencies:
  conduit_postgresql: ^6.0.0
```

## Connection string

```
postgres://user:password@host:5432/database
postgresql://user:password@host:5432/database
```

Both schemes resolve to the same backend. `--connection` on the
`conduit db` CLI accepts either; the legacy `--connect` and per-flag
form (`--user / --password / --host / --port / --database`) remains
supported.

## Programmatic construction

```dart
import 'package:conduit_postgresql/conduit_postgresql.dart';

final store = PostgreSQLPersistentStore(
  'user', 'password', 'localhost', 5432, 'mydb',
);
```

## Capabilities

- Full ORM `Query<T>` path (`Query.fetch`, `.insert`, `.update`,
  `.delete`, joins, subqueries).
- Schema management + migrations.
- Transactions with savepoint semantics.
- Postgres-specific features: `RETURNING`, `JSONB`, `ILIKE`, `@>`
  containment operators, full-text search via `tsvector`.

## Quirks / limitations

- The driver requires SSL by default for managed Postgres providers
  (RDS, Cloud SQL, etc.); set `sslMode: 'require'` or `'verifyFull'`
  on `PostgreSQLPersistentStore` for those targets.
- Connection pooling is not built into this package — wrap with
  `pgbouncer` or use the driver's connection-per-isolate pattern for
  high-concurrency workloads.

## CockroachDB variant

CockroachDB speaks the Postgres wire protocol, so this same package
works against a Cockroach cluster:

```dart
final store = PostgreSQLPersistentStore(
  'root', '', 'cockroach.local', 26257, 'mydb',
);
```

A separate `conduit_cockroach` package exists for behavior-divergence
gating (sequence semantics, `SERIAL` column types, `RETURNING` after
`UPSERT`); use it when you need annotation-level fanout via
`@OnlyOn([Dialect.cockroach])` (see
`package:conduit_test/src/dialect_annotations.dart`). For most apps
the postgres package is sufficient.

## Canonical example

See the project templates under `packages/cli/templates/db/` and
`packages/cli/templates/db_and_auth/` — both ship with a working
postgres `database.yaml` and a generated initial migration.
