# CockroachDB with `conduit_postgresql`

CockroachDB is wire-compatible with Postgres, so the same `package:postgres` driver that conduit uses for Postgres works against a Cockroach endpoint. Conduit provides a small `CockroachSqlDialect` to smooth over the few DDL divergences.

## Usage

```dart
import 'package:conduit_postgresql/conduit_postgresql.dart';

final store = PostgreSQLPersistentStore(
  user, password, host, port, db,
  dialect: const CockroachSqlDialect(),
);
```

The default constructor argument is `PostgresSqlDialect()`; pass `CockroachSqlDialect()` explicitly when targeting Cockroach.

## What the dialect handles automatically

| Concern | Postgres | Cockroach | Dialect handling |
|---|---|---|---|
| `IS NULL` shorthand | accepts `expr ISNULL` | requires `expr IS NULL` | `CockroachSqlDialect` emits standard form |
| Version-table name | `_conduit_version_pgsql` | `_conduit_version_cockroach` | Override prevents collision when one physical DB hosts both |

## What the dialect does NOT handle (caveats for application authors)

These divergences are runtime / semantic, not expressible at the dialect-string layer.

### `SERIAL` and `BIGSERIAL` semantics

Postgres `SERIAL` is `INT4` backed by a sequence (1, 2, 3, ...). Cockroach `SERIAL` is `INT8` with `unique_rowid()` as default — values are **64-bit, globally unique, but not contiguous**. Apps that depend on:

- ID monotonicity within a single node
- Sequential gap-free IDs
- 32-bit ID range

…should declare such columns explicitly rather than rely on `SERIAL`. Conduit's auto-increment column emission uses `SERIAL` regardless of dialect; for Cockroach, that translates to `unique_rowid()` semantics.

### Transaction retry

Cockroach uses optimistic concurrency; under contention it can return a "retry transaction" error (SQLSTATE `40001`). Postgres' equivalent is `serialization_failure` (`40001`) but is rarer in practice. Apps with high-contention transactional workloads against Cockroach should wrap their `transaction(...)` blocks with retry logic. Conduit does not automatically retry — that's an application-level decision (the right number of retries depends on idempotency, latency budgets, etc.).

### Schema-introspection

`SELECT to_regclass(@tableName:text)` works on Cockroach 21.1+ for table-existence checks (the dialect uses this). For older Cockroach versions, `SELECT name FROM crdb_internal.tables WHERE name = '...'` is the supported equivalent — but conduit's supported floor is current Cockroach.

### `ALTER TABLE ONLY`

Cockroach accepts `ALTER TABLE ONLY` as a no-op (no table inheritance). The base `PostgresSqlDialect` emits `ALTER TABLE ONLY` for constraint modifications; this is harmless on Cockroach.

### Foreign keys are enforced asynchronously

Cockroach defers foreign-key checks to the end of statements (Postgres checks at row-write time). Most apps don't notice. Apps that depend on per-row FK enforcement might see different ordering in batch operations.

### `DROP COLUMN ... CASCADE`

Cockroach implements this differently (drops dependent indexes/constraints; doesn't recurse into views the way Postgres does). Behavior is generally more conservative; review any migration that depends on `CASCADE` semantics.

## Verification

To run conduit's test suite against a Cockroach endpoint, swap the Postgres container in `docker-compose.test.yml` (or your CI compose file) for a Cockroach single-node:

```yaml
services:
  conduit_cockroach:
    image: cockroachdb/cockroach:latest
    command: start-single-node --insecure
    ports:
      - "26257:26257"
```

…and configure the test harness with `dialect: const CockroachSqlDialect()`. Tests that depend on Postgres-specific features (e.g., `ISNULL` shorthand, `JSONB` ops not yet implemented in Cockroach, `LIKE` ESCAPE clauses) will fail; mark them `@OnlyOn('postgres')` or skip per your test layer.

A full CI matrix entry exercising the Cockroach dialect end-to-end is tracked separately and lands when the multi-backend harness work in Phase 5 is in place.
