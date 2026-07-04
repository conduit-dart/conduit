# Connection pooling design — per-isolate pools for the Postgres store

Status: implemented (opt-in, default off) — 2026-07.
Companion to [PLANNING.md](PLANNING.md) §2 item 1. Measurement harness:
[LOAD_TESTING.md](LOAD_TESTING.md) / `tool/load/`.

## The question

Conduit's concurrency model is isolate-based: `Application.start` spawns N
isolates, each re-instantiating the full `ApplicationChannel`, and each
channel's `prepare()` creates one `PersistentStore` holding **one** database
connection. Queries within an isolate serialize on that connection. Should
that remain the only mode?

## Findings (code archaeology, 2026-07)

### The single-connection contract is real and load-bearing

1. **Transactions.** `PostgreSQLPersistentStore.transaction()` runs `runTx`
   on the store's connection and swaps the context's store for a
   `_TransactionProxy` pinned to the `TxSession`
   (`postgresql_persistent_store.dart`). `ManagedContext.transaction`'s docs
   warn that using the outer context inside the block "will deadlock your
   application" — a direct artifact of the single connection.
2. **Implicit serialization is tested behavior.** The test
   "Queries outside of transaction block while transaction block is running
   are queued until transaction is complete"
   (`packages/postgresql/test/transaction_test.dart`) starts a transaction
   *without awaiting it*, immediately fetches on the outer context, and
   expects the fetch to observe the committed result. That only holds
   because both serialize on one connection.
3. **The test harness needs session affinity.**
   `TestHarnessORMMixin.addSchema` creates `CREATE TEMPORARY TABLE`s
   (session-scoped) on the store's connection; a pooled store would create
   them on one connection and run later queries on another.
4. **Not all backends can pool.** `conduit_mysql` issues a session-level
   `SET time_zone` at connect; `conduit_sqlite` wraps a synchronous FFI
   `Database` handle where a pool is meaningless — for SQLite, isolates
   *are* the concurrency mechanism. The `PersistentStore` contract must
   therefore stay single-session-compatible.
5. **The docs promise it.** `docs/application/threading.md`: "each isolate
   has its own database connection … a serial queue"; total connections =
   machines × isolates. Downstream deployments may size Postgres
   `max_connections` on that arithmetic.

### But single-connection-only is a real bottleneck

1. **The default is one connection for the whole app.**
   `ApplicationOptions.isolates` defaults to **0**, which runs the channel
   on the current isolate — so a stock app serializes *every* query through
   one connection. (`docs/application/threading.md` claiming a default of 3
   isolates was stale; the code default is 0.)
2. **Isolates are an expensive unit of DB concurrency.** Each isolate
   duplicates the channel, ORM registry, and dev-mode mirror state. Isolates
   should scale with CPU; connection count should scale with I/O
   concurrency. The single-connection design couples them.
3. **The deadlock footgun.** With a pool, `runTx` checks out a dedicated
   connection; outer-context queries during a transaction proceed on
   another connection instead of deadlocking.
4. **The seam already existed.** `executionContext` is typed
   `Future<Session>`, and `postgres` v3's `Pool` implements `Session` and
   `SessionExecutor` (`execute`, `runTx`, `withConnection`). A dead
   `getConnectionPool()` helper (hardcoded `maxConnectionCount: 10`, never
   called) was already half-way there.

## Decision

**Keep single-connection-per-isolate as the default and guaranteed mode;
add opt-in per-isolate pooling to the Postgres store.**

- `PostgreSQLPersistentStore` gains `maxConnectionCount` (default **1**).
  At 1, the store keeps the exact legacy code path: one lazily opened
  `Connection`, reconnect-on-next-query, `Finalizer` cleanup, implicit
  query serialization.
- At >1, the store lazily creates a `Pool` sized to `maxConnectionCount`;
  `executionContext` returns the pool, and `transaction()` / `upgrade()`
  run through `pool.runTx` (each transaction gets a dedicated pooled
  connection; the `_TransactionProxy` mechanism is unchanged).
- `DatabaseConfiguration` gains an optional `maxConnectionCount` field
  (default 1) so the standard config-file → store plumbing can carry it;
  the `db` template threads it through.
- `getDatabaseConnection()` throws `StateError` on a pooled store — session
  state on a checked-out connection would not be visible to queries, so
  handing out a raw connection would be a trap. Use `executionContext`.

### Semantics that change in pooled mode (documented, intentional)

- Queries no longer serialize per store. Code that relied on issuing
  un-awaited queries in program order (the transaction_test pattern above)
  must await its futures.
- Session-scoped state (temporary tables, `SET`, advisory locks, LISTEN)
  is not meaningful through a pooled store. The test harness must keep
  pool size 1 (the default — nothing to do).
- Total Postgres connections become isolates × maxConnectionCount; size
  against `max_connections` (default 100).

### Out of scope, sequenced deliberately

- **mysql/sqlite pooling**: mysql needs per-connection `SET time_zone`
  init before it can pool; sqlite never pools. Both keep the default path.
- **Statement caching** (PLANNING §2 item 2): prepared statements are
  per-connection; if added later it must live inside
  `withConnection`/session scope, not per-store. Pooling lands first on
  purpose.
- **Changing the pooled default**: revisit making `maxConnectionCount`
  default to >1 (or CPU-derived) in the next major, after soak time.
