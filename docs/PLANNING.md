# Housekeeping & feature planning — 2026-07 snapshot

Follow-up to [REFACTOR_CONTEXT.md](REFACTOR_CONTEXT.md) (2026-04). Since that
snapshot, the workspace gained six real packages (`mysql`, `sqlite`, `graph`,
`graph_neo4j`, `graphql`, `build_runner`), v7.0.0 shipped, and the 6.0/7.0
migration guides landed. This doc records what's clean, what's owed, and
what's worth building next.

## 1. Housekeeping

### Resolved on this branch

- `melos.yaml.orig` deleted (config lives in root `pubspec.yaml` `melos:` block).
- Orphan `docs/files/settings.jar` deleted (unreferenced IDE artifact).
- Stale `action-items.md` deleted (all three items self-declared "nothing to do").
- `docs/http/README.md` "Responsers" typo fixed; `docs/auth/README.md` empty
  OAuth link now points at `what_is_oauth.md`.
- Unused direct deps removed: `analyzer` + `postgres` from `conduit_core`,
  `analyzer` moved to dev_dependencies in `conduit` (cli) — see §2.
- Constraint floors aligned: `collection ^1.18.0`, `meta ^1.12.0`, `args ^2.4.2`.
- Root `CLAUDE.md` added (agent onboarding — see §3).

### Still owed

| Item | Size | Notes |
| --- | --- | --- |
| `packages/common` has **zero tests** | S | Load-bearing OpenAPI documenter interfaces; also excluded from melos test scripts (`--ignore "*common*"`). Add contract tests and stop ignoring it. |
| 7 aging `// todo:` comments | S | All in core/open_api/codable; notable: `resource_controller.dart:285` ("should be done compile-time") aligns with the build_runner direction. |
| `packages/mysql` / `packages/sqlite` READMEs are thin | S | Both defer to solid `doc/usage.md`; lift install + status into the README since pub.dev renders only the README. |
| No committed `pubspec.lock` | S | Decide policy: committing the root lock gives reproducible CI resolution for the workspace. |
| OpenAPI v2 (Swagger) subtree | M | Still unowned decision: deprecate or document why it stays. |

## 2. Performance

Full audit result (July 2026): drivers are current (`postgres` v3 API,
`mysql_dart` 1.2+, `sqlite3` FFI), there is no duplicate crypto lib, and no
third-party HTTP layer — core rides `dart:io`. The wins are wiring, not
dependency swaps:

1. **Wire up the dead Postgres connection pool.** *(landed — opt-in)*
   `PostgreSQLPersistentStore` now takes `maxConnectionCount` (default 1 =
   legacy single-connection behavior); above 1 the store fronts a postgres
   v3 `Pool` and transactions check out dedicated connections. See
   [CONNECTION_POOLING.md](CONNECTION_POOLING.md) for the design and the
   semantics that change in pooled mode. Still owed: load-test evidence
   and a decision on flipping the default in the next major.
2. **Cache prepared statements.** Every ORM call re-parses via
   `Sql.named(...)` + `QueryMode.extended` and discards the statement
   (`postgresql_persistent_store.dart:383-388`; same pattern in
   `sqlite_persistent_store.dart:70-111` with `prepare`/`dispose` per call).
   An LRU keyed on the generated SQL string in each store removes the
   parse/plan round-trip on hot queries.
3. **Get `analyzer` out of the shipped closure.** Direct unused declarations
   are removed on this branch, but `conduit_runtime` and
   `conduit_isolate_exec` genuinely import `analyzer ^12`, so every deployed
   app still carries it. The structural fix is finishing the
   `build_runner`-based AOT path so runtime discovery never needs the
   analyzer at serve time — big binary-size and cold-start win.
4. **PBKDF2 cost + placement.** `hashRounds = 1000` (`auth.dart:22`) is far
   below OWASP guidance (~600k for PBKDF2-HMAC-SHA256). Raising it is a
   security fix that turns the pure-Dart PBKDF2 loop into a login-path CPU
   hotspot — pair the bump with hashing on an isolate pool. A native crypto
   dependency is *not* recommended; on server-side Dart the isolate offload
   is the better first move.

Non-findings worth recording: `postgres ^3.1.1` is the modern v3 API (no v2
migration owed); `graph_neo4j`'s Bolt client is hand-rolled with zero external
deps (a feature, not a smell); no JSON codegen dependency exists anywhere —
serialization is `conduit_codable` + `dart:convert`.

## 3. AI alignment (agent-friendliness)

Done on this branch: root **`CLAUDE.md`** — workspace map, canonical
commands, conventions (conventional-commit PR titles, branch naming, test
requirements), and the sharp edges an agent must not trip (dual
mirror/AOT runtime modes, closure-introspecting query DSL, frozen public API,
generated-state conventions).

Next steps, in order of value:

1. **Per-package `CLAUDE.md` stubs only where behavior is surprising**
   (`runtime`, `cli`, `core/src/runtime/`) — pointers into
   REFACTOR_CONTEXT §4 rather than duplicated prose.
2. **Keep docs snapshots dated and superseding** (REFACTOR_CONTEXT →
   this file → next); agents read these first, so staleness is actively
   harmful. Delete rather than accumulate.
3. **Make verification agent-runnable** *(landed on this branch)*: tests
   otherwise need a provisioned Postgres, so `melos run test-fast` runs the
   database-free packages (codable, open_api, password_hash, config,
   build_runner) — mirroring the Woodpecker `workspace-unit-tests` +
   `build-runner-tests` steps — as a cheap local gate before the full suite.

## 4. Feature planning

Ranked by user-visible leverage:

1. **Multi-backend ORM completion.** `conduit_mysql` and `conduit_sqlite`
   both throw `UnimplementedError` on `newQuery<T>` — blocked on extracting
   the predicate/query builders from `conduit_postgresql` into core behind
   `SqlDialect`. This is the single feature that turns the two new backends
   from "schema + raw SQL" into real ORM targets, and it unlocks no-Docker
   test fixtures via in-memory SQLite (which then feeds §3.3).
2. **AOT-first story via `build_runner`.** The builders exist (8 of them,
   tested). Finishing the path so `conduit build` needs no `dart:mirrors`
   and no `analyzer` at runtime addresses REFACTOR_CONTEXT items 1–3 and
   perf item 3 in one arc.
3. **GraphQL maturation.** `conduit_graphql` is the largest new package
   (5k lib LOC, 607-line README, integration tests across all four
   backends) — closest to a headline feature; needs docs-site coverage
   (`docs/persistence/graphql-cross-source.md` exists; wire into mkdocs nav)
   and a `conduit create` template.
4. **Query DSL de-magicking** (REFACTOR_CONTEXT item 4): a column-selector
   API to replace closure introspection; long pole, coordinate with (1)
   since the extracted builders define the seam.
5. **Scheduled agentic maintenance** — see
   [AGENTIC_MAINTENANCE.md](AGENTIC_MAINTENANCE.md) for the self-hosted
   model + Woodpecker cron design and rollout phases.
