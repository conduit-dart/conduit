# conduit_sql

Dialect-pluggable SQL backend toolkit for the Conduit ORM. Lets backends like
Postgres, MySQL, and SQLite share the SQL builder, JOIN planner, and row
instantiator while only implementing the bits that genuinely differ between
dialects.

This is **phase 0** of the work documented in
[`docs/GENERAL_ORM.md`](../../docs/GENERAL_ORM.md): the package, the
`Dialect` abstract surface, and a smoke test. The shared builders that
consume this interface are extracted from `packages/postgresql/` in phase 1.

## What's here today

- `Dialect` — abstract interface every adapter implements
  (identifier quoting, parameter syntax, DDL type names, capability flags).
- `DialectCapabilities` — feature flags the shared builders branch on
  (`supportsReturning`, `supportsUpsert`, `supportsJsonColumn`,
  `supportsCheckConstraints`, `maxIdentifierLength`).

## Not here yet

- The shared SQL builders themselves — phase 1 moves them out of
  `packages/postgresql/lib/src/{builders,query_builder,row_instantiator}.dart`.
- A concrete `PostgresDialect` / `MySQLDialect` — phases 3 and 4.

A user app does not import this package directly. They import a backend
adapter (`conduit_postgresql`, `conduit_mysql`) which depends on this
package transitively.
