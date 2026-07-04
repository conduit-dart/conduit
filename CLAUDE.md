# Conduit — agent guide

Conduit is a Dart HTTP server framework (fork of Aqueduct): routing,
ResourceControllers, an ORM (`Query<T>`/`ManagedObject`), OAuth 2.0, and
OpenAPI generation. Monorepo managed with **Melos** (Dart pub workspace).

## Workspace map

| Path | Package | What it is |
| --- | --- | --- |
| `packages/core` | `conduit_core` | The framework: `application/` (lifecycle, isolates), `http/` (Router, Controller, ResourceController), `auth/` (OAuth2 server), `db/` (ORM, query DSL, schema/migrations), `runtime/` (bridge to codegen). |
| `packages/cli` | `conduit` | The `conduit` CLI: create/serve/build/document/db/auth. Spawns isolates that import user code. |
| `packages/runtime` | `conduit_runtime` | AOT pipeline + mirror abstraction. Dev mode uses `dart:mirrors`; `conduit build` generates mirror-free code. |
| `packages/postgresql` | `conduit_postgresql` | Primary `PersistentStore` backend. |
| `packages/mysql`, `packages/sqlite` | | Newer database backends. |
| `packages/graph`, `packages/graph_neo4j`, `packages/graphql` | | Newer graph/GraphQL layers. |
| `packages/config`, `packages/codable`, `packages/common`, `packages/open_api`, `packages/password_hash`, `packages/isolate_exec` | | Support libraries. `common` bridges core/cli → open_api. |
| `packages/test_harness` | `conduit_test` | Test DSL for apps built on Conduit. |
| `packages/fs_test_agent`, `packages/*_test_packages` | | Private test fixtures. |

`docs/REFACTOR_CONTEXT.md` is a deep architecture map (couplings, mirror
usage, ranked refactor targets). Read it before any cross-package refactor.
`docs/PLANNING.md` (2026-07) supersedes its housekeeping list and ranks
current feature/performance work. `docs/AGENTIC_MAINTENANCE.md` covers the
scheduled-maintenance design.

## Setup and commands

```bash
dart pub global activate melos
melos bootstrap                  # resolve the workspace

# Tests need Postgres (and env vars) — use the CI compose file:
docker-compose -f ci/docker-compose.yaml up -d
export POSTGRES_USER=conduit_test_user POSTGRES_PASSWORD='conduit!' \
       POSTGRES_DB=conduit_test_db POSTGRES_PORT=15432 POSTGRES_HOST=localhost

melos run test-fast              # DB-free scope (codable/open_api/password_hash/config/build_runner) — run this first
melos run test-unit              # unit tests across packages (fail-fast, serial; needs Postgres)
melos run analyze                # dart analyze every package
melos run fix                    # dart fix --apply across packages
melos exec --scope="conduit_core" -- dart test test/http/router_test.dart   # one package/file
```

- SDK floor is `>=3.12.0` (see root `pubspec.yaml`). Don't lower it.
- Lints are centralized in `analysis_options.shared.yaml`; per-package
  `analysis_options.yaml` files include it. Add rules there, not per-package.
- CI: GitHub Actions (`.github/workflows/`) + Woodpecker (`.woodpecker.yml`).
  Postgres in CI runs on port **15432**.

## Conventions

- **Conventional commits on PR titles** — PRs are squash-merged and the PR
  title drives melos autoversioning/publishing. Individual branch commits
  don't need to follow the convention.
- Branch naming: `docs/<desc>`, `fix/<user>-<desc>`, `feature/<user>-<desc>`,
  `refactor/<user>-<desc>`.
- Every non-doc change needs tests, including failure cases.
- New packages must carry the root-level BSD-2 license.

## Sharp edges (read before touching)

- **Two runtime modes.** Dev mode reflects with `dart:mirrors`; `conduit
  build` deflects mirrors out via codegen in `packages/runtime`. Any change
  to `core/src/runtime/`, `config`, or annotations must work in BOTH modes —
  a change that only works under mirrors will pass dev tests and break AOT.
- **The query DSL is magic.** `query.where((o) => o.field)` recovers column
  names by introspecting the closure. Renaming a `ManagedObject` field is
  load-bearing; grep for usages in tests and templates.
- **Public API is frozen** by downstream apps: everything exported from
  `packages/core/lib/conduit_core.dart`, `managed_auth.dart`, and the CLI
  subcommand set (`create/serve/build/document/db/auth/setup`). See
  §7 of `docs/REFACTOR_CONTEXT.md`.
- **`packages/common` has no tests** but is load-bearing (OpenAPI documenter
  interfaces used by core and cli). Signature changes there ripple silently.
- **Generated/derived state**: `generated_runtime/` output, migration files
  discovered by filename regex (`N_name.migration.dart`), template projects
  in `packages/cli/templates/` patched by string substitution (`wildfire` →
  project name). Treat all three as conventions, not incidental strings.
- There is no `melos.yaml`; the live melos config is the `melos:` block in
  the root `pubspec.yaml` (pub workspace resolution + melos scripts).

## Docs

User docs live in `docs/` (mkdocs, `mkdocs.yml`). When changing public API
or CLI behavior, update the matching page (`docs/http/`, `docs/db/`,
`docs/cli/`, ...) and the migration guide under `docs/migration/` for
breaking changes.
