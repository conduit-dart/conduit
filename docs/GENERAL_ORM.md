# General ORM — multi-dialect SQL backend

> Design proposal for letting Conduit's ORM target backends other than
> PostgreSQL. Companion to [REFACTOR_CONTEXT.md](REFACTOR_CONTEXT.md).
> Scope: SQL dialects (Postgres, MySQL, SQLite). Non-SQL stores are a
> separate problem and out of scope for this proposal.

## 1. Goal

Conduit's ORM (`Query<T>`, `ManagedObject`, `Schema`) is already
backend-agnostic at the API surface. The only live backend is
`packages/postgresql/`. PR #192 (closed) attempted a parallel
`packages/mysql/` package by cloning the postgresql tree; it stalled
after 3 years because every Postgres improvement required a manual
re-clone.

Goal: make adding a backend a small, contained job — one new package
per dialect, ~few hundred lines, no duplicated SQL builder logic.
First non-Postgres dialect: MySQL. SQLite, MSSQL, etc. follow the
same shape.

## 2. Where the Postgres-specific logic actually lives

Surveyed `packages/postgresql/lib/src/` — 11 files, 2144 lines. Split
by how dialect-specific they actually are:

| File | Lines | Dialect-specific? |
| --- | --- | --- |
| `postgresql_persistent_store.dart` | 495 | **Yes** — `package:postgres` driver, `SslMode`, connection pooling, parameter substitution syntax (`@varname`) |
| `postgresql_schema_generator.dart` | 289 | **Yes** — DDL strings (`SERIAL`, `TIMESTAMP`, `JSONB`, `BIGSERIAL` mappings) |
| `postgresql_query.dart` | 254 | **Mostly no** — INSERT/UPDATE/DELETE/SELECT SQL assembly. Only PG-isms are `RETURNING` clause and the `@varname` parameter style. |
| `postgresql_query_reduce.dart` | 105 | **No** — aggregation function names (COUNT, MAX, etc.) are SQL-standard |
| `query_builder.dart` | 138 | **No** — already generically named, coordinates the builders below |
| `row_instantiator.dart` | 172 | **No** — maps DB rows to `ManagedObject` instances; backend-agnostic |
| `builders/column.dart` | 158 | **No** — column reference + alias generation |
| `builders/expression.dart` | 151 | **No** — WHERE clause matchers (`=`, `LIKE`, `IN`, etc.) |
| `builders/sort.dart` | 24 | **No** — `ORDER BY ... ASC/DESC` |
| `builders/table.dart` | 341 | **No** — JOIN tree, table aliases, FROM-clause assembly |
| `builders/value.dart` | 17 | **No** — value/parameter binding wrapper |

About **1100 of the 2144 lines are already dialect-neutral SQL
construction.** They live in `packages/postgresql/` for historical
reasons (Aqueduct only ever shipped a Postgres backend) but have no
inherent PG dependency.

## 3. Approach

Three new pieces:

1. **`packages/sql/` (`conduit_sql`)** — extracted shared SQL toolkit.
   Becomes the home of the dialect-neutral builders and a `Dialect`
   abstract interface that captures everything a backend must answer
   about its own SQL. Imports `conduit_core` only.

2. **`Dialect` interface** — the small surface area that varies by
   backend. From the Postgres survey above:
   - **Identifier quoting** — `"foo"` vs `` `foo` `` vs `[foo]`
   - **Parameter syntax** — `@name` vs `?` vs `$1`
   - **Auto-increment column type** — `BIGSERIAL` vs `BIGINT AUTO_INCREMENT` vs `INTEGER PRIMARY KEY AUTOINCREMENT`
   - **DDL type names** for each `ManagedPropertyType`
   - **Returning-clause support** — Postgres has `RETURNING`; MySQL
     8.0+ has it for some statements; older MySQL needs a follow-up
     `LAST_INSERT_ID()` SELECT
   - **Conflict / upsert syntax** — `ON CONFLICT` vs `ON DUPLICATE KEY`
   - **Boolean literal** — `TRUE` / `FALSE` vs `1` / `0`
   - **Date/time formatting**
   - **JSON column support** — `JSONB` vs `JSON` vs absent

3. **Per-backend adapter packages** — `packages/postgresql/` and the
   new `packages/mysql/` each shrink to:
   - `<X>PersistentStore extends PersistentStore` with
     connection-pool, driver, transaction handling.
   - `<X>Dialect extends Dialect` returning the dialect-specific
     strings and capability flags.
   - Optionally a tiny `<X>Query` if some statements need bespoke
     assembly that doesn't fit the shared template.

   The estimate is: postgresql shrinks from 2144 lines to about
   600-800; mysql lands around the same size, with the rest
   (≈1100 lines) shared via `conduit_sql`.

## 4. User-facing API

Unchanged. A user app today writes:

```dart
final ctx = ManagedContext(
  dataModel,
  PostgreSQLPersistentStore(
    user, password, host, port, db,
  ),
);

final users = await Query<User>(ctx).fetch();
```

After this work, swapping to MySQL is one import + one constructor
swap:

```dart
final ctx = ManagedContext(
  dataModel,
  MySQLPersistentStore(
    user, password, host, port, db,
  ),
);

final users = await Query<User>(ctx).fetch();   // identical
```

`Query<T>`, `ManagedObject`, `Schema`, `Migration` — all unchanged.

## 5. Migration plan (chunked)

Each phase is independently shippable; postgres keeps working at
every step.

### Phase 0 — Scaffolding (this PR)

- New package `packages/sql/` (`conduit_sql`) at version 6.0.0,
  registered in workspace + melos.
- `Dialect` abstract class with the capability surface from §3,
  stub implementations + doc comments. No real callers yet.
- `analysis_options.yaml`, `CHANGELOG.md`, `README.md`, `LICENSE`,
  empty `test/` with a smoke test.

No behavior change for postgresql users.

### Phase 1 — Extract dialect-neutral builders

Move from `packages/postgresql/lib/src/`:
- `builders/column.dart`, `expression.dart`, `sort.dart`,
  `table.dart`, `value.dart`
- `query_builder.dart`, `row_instantiator.dart`

into `packages/sql/lib/src/`. Update imports. Add `Dialect`
parameter where the moved code currently hard-codes Postgres
quoting / parameter syntax.

### Phase 2 — Extract reduce + the query template

Move `postgresql_query_reduce.dart` and the dialect-neutral parts of
`postgresql_query.dart` (INSERT/UPDATE/DELETE/SELECT assembly) into
`packages/sql/`. The PG-specific `RETURNING` handling goes through
the `Dialect.returningClauseFor(...)` hook.

### Phase 3 — Postgres adapter cleanup

What remains in `packages/postgresql/`:
- `postgresql_persistent_store.dart` (driver + transactions)
- `postgresql_schema_generator.dart` (DDL strings)
- A new `postgresql_dialect.dart` implementing `Dialect`
- A thin `postgresql_query.dart` that just plugs the dialect into
  the shared template.

Estimated final size: ~700 lines, down from 2144.

### Phase 4 — MySQL adapter

`packages/mysql/` (`conduit_mysql`):
- `mysql_persistent_store.dart` using `package:mysql_client` ^1.x
  (latest, breaking-change updated from the 0.0.27 in #192)
- `mysql_schema_generator.dart` mirroring the postgres DDL with
  MySQL types (`AUTO_INCREMENT`, `JSON`, `DATETIME`, …)
- `mysql_dialect.dart` implementing `Dialect`
- `mysql_query.dart` thin wrapper, plus a fallback path for
  pre-8.0 servers without `RETURNING`.
- Test suite cloned from `packages/postgresql/test/`, retargeted
  at a MySQL container in `ci/docker-compose.yaml`.

### Phase 5 — Optional: SQLite adapter

`packages/sqlite/` (`conduit_sqlite`) using `package:sqlite3`. Same
shape as MySQL. Useful for embedded and test scenarios where
spinning up Postgres/MySQL is overkill. Lower priority.

### Phase 6 — Docs + migration guide

- `docs/db/connecting.md` shows all three backends.
- `docs/db/dialects.md` (new) explains the dialect interface for
  third-party adapters.
- v6.x → v7.x migration note if any user-visible API changed (none
  expected).

## 6. Open questions

1. **Migrations DDL across dialects.** A migration file calls
   `database.createTable(...)` etc. Today the call goes through
   `PersistentStore`, which is per-backend, so the SQL emitted is
   already correct for whichever store is attached. **Implication:**
   migrations stay portable across dialects as long as the user
   doesn't drop into raw SQL strings inside a migration. Worth a
   call-out in the docs.

2. **Connection pooling.** `package:postgres` and
   `package:mysql_client` have different pooling models.
   `PersistentStore` could either expose a pool-agnostic interface
   or stay opinionated per-backend. **Lean: per-backend** — pool
   tuning is dialect-specific in practice.

3. **Transaction isolation levels.** Postgres and MySQL have
   different default isolation and different syntax for setting it.
   `ManagedContext.transaction` takes no isolation argument today;
   adding one is its own design discussion. **Lean: out of scope
   for this proposal.**

4. **Capability negotiation at construction time.** A `Dialect`
   could expose feature flags (`supportsReturning`,
   `supportsCheckConstraints`, `maxIdentifierLength`) so the shared
   builder can pick the right path. Use a `DialectCapabilities`
   struct rather than scattering bool getters on `Dialect`.

5. **NoSQL.** A document store like Mongo or KV store like Redis
   would not implement `Dialect` — the `PersistentStore` interface
   itself would need a sibling abstraction. **Out of scope for this
   proposal**, but the package layout (`conduit_sql` rather than
   `conduit_db_common`) is named to avoid claiming non-SQL territory.

6. **Where the `RETURNING` shim lives.** For dialects that don't
   have it natively (older MySQL, SQLite), the shared INSERT
   template needs to emit a `LAST_INSERT_ID()` follow-up. This is a
   real piece of logic — not just a string difference. Likely lives
   on `Dialect` as `Future<dynamic> insertReturning(executor, sql, params)`.

## 7. What "starting work" looks like in practice (this PR)

This PR lands phase 0 only:

- New `packages/sql/` package skeleton
- Stub `Dialect` interface with the capability surface from §3
- Workspace + melos registration
- Smoke test that the package builds and the stub interface compiles
- This design doc

No production code change. Phases 1–4 land in subsequent PRs, in
order. Phase 5 can land any time after phase 3.

---

*Proposal, not a commitment. Sizes in §3 are line counts as of
2026-04-25. Phase ordering may shift if extracting the builders
turns out trickier than the line counts suggest.*
