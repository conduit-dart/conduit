# Hardening checklist — conduit

Language: Dart (Melos 7 pub workspace, 19 packages + 2 examples + 2 tools)
Framework: in-house Conduit HTTP framework + ORM (Postgres / SQLite / MySQL) + Graph/GraphQL
SDK floor: `>=3.13.0 <4.0.0` (raised from 3.12 in this pass)

History:
- 2026-05-30: read-only audit (pre-`v7.0.0`).
- 2026-10-03: write pass on `claude/hardening-pass-2026-10`. This file reflects that pass.

---

## Priority — open after this pass

1. **`QueryPredicate.and` parameter-collision bug under `:name` dialects (SQLite, MySQL).**
   Two predicates on the same column (`where(n).lessThan(500)..where(n).greaterThan(10)`)
   collide on the parameter name. `and()` renames the map key (`n` -> `n0`) but only
   rewrites `@name` in the format string, so `:name` dialects keep `:n` twice. It also
   drops the AST, so the broken format string is what executes. Reproduced on
   `SqlitePersistentStore.memory()`: the fetch throws
   `Invalid argument (params): This statement contains no parameter named :_R_n0`.
   MySQL uses the same `:name` placeholder and was not run live. Pinned in
   `packages/core/test/db/goldens/predicate_render.golden` (case
   "lt / lte / gt / gte AND chain", named-colon block). Proposed fix: rename with a
   placeholder-aware regex (`(?<=[@:])key(?!\w)`) and rename inside the AST too, so the
   AST survives. Not applied here because it changes core query behaviour; it needs its
   own `fix(core):` PR with a SQLite/MySQL regression test.
2. **pub.dev publisher + trusted publishing for the five 7.0.0-new packages.** All five are
   live at 7.0.0, but `publisherId` is `null` for `conduit_sqlite`, `_mysql`, `_graph`,
   `_graph_neo4j`, `_graphql`. Transfer them to `theconduit.dev` and confirm automated
   publishing is enabled before the next tag. Runbook: `docs/PUBLISHING.md`.
3. **`melos run test-unit` is not green on `master`, and CI wouldn't notice.** CI's `unit`
   job runs `packages/core` only. `packages/cli/test/build_test.dart` still exercises the
   `conduit build` command that 7.0 removed. See Findings for the full per-package run.
4. **Nix devShell ships Dart 3.5.4.** `flake.nix` pins `nixos-24.11`, whose `pkgs.dart` is
   3.5.4. That couldn't resolve the old 3.12 floor either. The Woodpecker `nix-shell` step
   only prints `dart --version`, so it stays green. Pin a nixpkgs that has Dart >= 3.13, or
   fetch the SDK in the flake.
5. **Semver for the SDK-floor raise.** `conduit_core`'s 7.0.0 CHANGELOG treats a floor raise
   as breaking. Decide 7.1.0 vs 8.0.0 and title the PR to match.

---

## Tests

- [x] Test infra across every shipping package; backend-specific suites for sqlite / mysql / graph_neo4j / graphql.
- [x] Golden tests for the predicate AST -> SQL render: `packages/core/test/db/predicate_render_golden_test.dart`. 21 real `Query.where()` shapes run through `QueryBuilder` under `@name`/ILIKE, `:name`/LIKE and `?` positional dialects. The AST render must be byte-identical to the legacy format string. Regenerate with `CONDUIT_UPDATE_GOLDENS=1`.
- [x] Property tests on the `SqlExpression` render round-trip: `packages/core/test/db/expression_render_property_test.dart`. Hand-rolled seeded generator, 400 seeds, 6 properties (positional arity/order, named completeness incl. collisions, named<->positional round-trip, no value leakage, `and()` format equivalence, determinism). Mutation-checked: a swapped BETWEEN operand order fails at seed 3.
- [x] `conduit_graph` single-test-file rationale documented (`packages/graph/README.md` § Testing; `docs/migration/7.0.md` §3).
- [x] Coverage measured in CI, instrument-only: `linux.yml` `coverage` job. lcov artifact + step-summary table, no threshold.
- [ ] Coverage floor on `conduit_core`. Set it once a few CI runs establish the baseline.
- [ ] `packages/cli/test/build_test.dart` tests the removed `conduit build`. Delete or port it to the build_runner path (see Findings).

## Static analysis

- [x] Shared lint floor (`analysis_options.shared.yaml`, 22 Dart 3 lints). Already landed on `master` as #294 before this pass. The local `refactor/dart3-modernization` branch is that PR's pre-squash history and was not re-applied.
- [x] 22 `library_private_types_in_public_api` infos in `sql_expression_visitor.dart` fixed. The visitors now extend `SqlExpressionVisitor<String>`.
- [x] `melos run analyze`: 21/21 packages "No issues found!" on Dart 3.13.5.
- [x] `dart format --set-exit-if-changed .` is clean (Dart 3.13.5, language 3.13) and gated in CI. GHA linux/macos/windows smoke jobs run it on the `stable` leg; the Woodpecker `lint` step runs it too.
- [x] `dart pub publish --dry-run` remains the release gate (`publish.yml` `dry-run` job).

## Error paths

- [x] `empty_catches` is enforced again in `conduit_core` and `conduit_config`. The old `ignore` only masked one test catch per package, not the claimed `Application.stop` sites, which log via `logger.severe`. Both `analysis_options.yaml` files now explain why.
- [x] `print()`: spot-checked. CLI + isolate_exec use it as their output channel. The only other site is `core/.../application/options.dart` `--help` usage. No change.
- [x] `package:logging` adoption: spot-checked, no gap. No change.
- [x] Entry-point error handling: spot-checked (`Application.start/stop`, `Controller` chain, `Router`). No gap. No change.
- [x] Public error types are structured (`HTTPResponseException`, `QueryException`, `SchemaException`, `GraphException`, `CLIException`).
- [ ] `QueryPredicate.and` `:name` collision bug. Priority 1.

## Supply chain

- [x] Lockfiles intentionally not committed (library workspace).
- [x] OIDC trusted publishing in `publish.yml`.
- [x] Dependabot: `.github/dependabot.yml`, weekly grouped `pub` (root + `/packages/*`) and `github-actions`.
- [x] Advisory scan: non-gating "Dependency advisories" step in `linux.yml` (stable). The audit's `dart pub outdated --mode=security` does not exist, so the step reads `isCurrentAffectedByAdvisory` / `isDiscontinued` / `isCurrentRetracted` from `dart pub outdated --json --show-all`. Today: 99 packages, none flagged.
- [x] `analyzer` `^12.0.0` -> `^13.0.0` (cli, build_runner, runtime, isolate_exec). Resolves cleanly; `^14` also resolves and is a follow-up.
- [x] `melos.yaml.orig` was already removed on `master` (#300). `melos_conduit_workspace.iml` is untracked, gitignored, and referenced by the melos-generated `.idea/modules.xml`, so it was left alone.
- [x] License posture unchanged (BSD upstream / MIT new). No LICENSE files touched. `license-audit.md` was not refreshed in this pass.

## CI

- [x] Format gate on every platform's smoke job (stable leg) + Woodpecker lint.
- [x] Coverage job (instrument-only) + advisory step (informational) on Linux.
- [x] Woodpecker image pinned `dart:beta` -> `dart:3.13`. Beta was only needed while the floor was the pre-release `>=3.12.0-0`. `ci/run-local.sh` follows.
- [x] GHA `setup-dart` steps already pass `sdk:` explicitly (matrix / `stable` / `beta`). Unchanged.
- [ ] Untracked-file check: skipped (low value).
- [ ] CI runs only `conduit_core` tests on PRs, plus the DB-free set on Woodpecker. cli / postgresql / sqlite / mysql / graphql suites are not exercised (see Findings).

## Deploy / release (library remap)

- [x] Tag-driven release, dry-run gate, topological publish, visibility poll, multi-arch images.
- [x] `docs/migration/7.0.md`: #267 cost corrected to the measured ~+20% (multi-term construction); graph testing note; §10 "after 7.0.0" covers the 3.13 floor, lint floor, `empty_catches`, analyzer ^13, and the visitor change.
- [x] First-publish + trusted-publisher runbook: `docs/PUBLISHING.md`.
- [x] `CONTRIBUTING.md` § Releasing, with Rollback (fix forward with a `+1` patch, then retract) and Deprecation policy (one major of warnings, removal in N+1).
- [ ] Publisher transfer + OIDC confirmation for the five new packages (needs the maintainer's pub.dev session). Priority 2.

## Observability (library remap)

- [x] `package:logging` convention; OpenAPI generation; bench harness + `RESULTS.md`.
- [x] `.github/ISSUE_TEMPLATE/performance_regression.md`: asks for a bench reproducer, Dart channel/versions, and JIT vs AOT; cites #267/#270.

---

## Findings

### Dart 3.13 fallout (fixed in this pass)

- Language 3.13 rejects `final` on ordinary parameters. That produced 7 errors in `conduit_core` `runtime/orm/*_builder.dart`; `final` was dropped.
- `use_super_parameters` now fires for named super arguments: `PostgresOnly` (`conduit_test`) and `APIHeader` (`conduit_open_api`). Converted; signatures unchanged.
- The formatter style follows the language version, so 119 files were reformatted.

### Per-package test run on Dart 3.13.5

Branch HEAD, Dart 3.13.5. Postgres 18 from `ci/docker-compose.yaml`, bound to 127.0.0.1 only.
Packages were run one at a time without `--fail-fast`, so one failure doesn't hide the rest.

| Package | Result | Where |
| --- | --- | --- |
| conduit_core | 1132 pass / 7 skip / 0 fail | `dart:3.13` container on `ci_default`. On the host, 8888 is held by an unrelated 127.0.0.1 listener, and core's tests bind fixed port 8888. |
| conduit_postgresql | 365 pass / 11 skip | host |
| conduit_sqlite | 34 pass | host. The `dart:3.13` image has no `libsqlite3.so`. |
| conduit_mysql | 29 pass with `-x integration` | host. The `integration` tag is declared in `dart_test.yaml` but never skipped or excluded, so a plain `dart test` fails without a live MySQL, contrary to the file's doc comment. Pre-existing. |
| conduit_test | 100 pass / 1 skip | host |
| conduit_graph / _graph_neo4j / _graphql | 28 / 55 (3 skip) / 132 (6 skip) | host |
| conduit_build_runner, _codable, _config, _open_api, _password_hash, _isolate_exec, _runtime, fs_test_agent | all pass | host / container |
| conduit (cli) | fails on `master` too | `build_test.dart` tests the removed `conduit build`. `create_test.dart` alone gives 8 pass / 5 fail on both `origin/master`@3.12.2 and HEAD@3.13.5. The full suite times out identically on both without a reachable DB. No 3.13 regression. Pre-existing. |

The `melos run test-unit` gate stops at the cli failure (`--fail-fast`, cli runs first). It cannot
be green on `master` until the cli suite is repaired and the mysql `integration` tag is excluded by
default. CI only runs `conduit_core`, so neither problem shows up in CI.

Other gates on Dart 3.13.5: `melos run analyze` 21/21 clean; `dart format --set-exit-if-changed .`
clean (554 files); the advisory check (`dart pub outdated --json --show-all`) reports 99 packages
and none advisory-affected, discontinued, or retracted.
