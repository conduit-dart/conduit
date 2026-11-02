# License audit — conduit

Workspace: Dart Melos workspace, 19 packages under `packages/*`.
Audit date: 2026-05-30; re-audited 2026-11-01 against `master` @ `03f181d5`
  (melos 8, Dart pub workspace).
Audit posture: read-only. No pubspec.yaml, LICENSE, or source mutations.
Scope: per-package LICENSE inventory + direct/transitive dep license sweep
  + attribution obligations + risk-tiered remediation.
Method: LICENSE-body classification (`Permission is hereby granted` → MIT,
  `Redistribution and use in source and binary forms` ± `Neither the name of`
  → BSD-2/3, `Apache License Version 2.0` → Apache-2.0, etc.) against the
  fully-resolved root `pubspec.lock` of the pub workspace, reading each
  hosted package's LICENSE/COPYING from the pub cache.

**2026-11-01 re-audit deltas:** transitive graph still 94 hosted packages,
all permissive. D2 is resolved (`test_core` now resolves to 0.6.18, which
ships its LICENSE; BSD-3-Clause 76 → 77). Per-package LICENSE files are
unchanged. A1 remains open. L1 now compares against the rule in the repo's
`CLAUDE.md`.

---

## Verdict

**Ship-safe with one followup.** The dependency tree is uniformly permissive
(MIT / BSD-2/3 / Apache-2.0); no GPL, LGPL, AGPL, SSPL, or Elastic anywhere
in the 94-package transitive graph. The per-package LICENSE picture is
**mixed BSD-2-Clause + MIT** (see Finding L1) — it does **not** match the
rule in the repo's `CLAUDE.md` (*"New packages must carry the root-level
BSD-2 license"*), but the reality is also not a license-compatibility problem; both are permissive. The one followup
worth doing pre-v7 is the AOT-binary attribution bundle for the template
smoke binary (Finding A1).

---

## L1 — per-package LICENSE inventory (the real picture)

The repo's `CLAUDE.md` says *"New packages must carry the root-level BSD-2
license."* The legacy Stable-Kernel-era packages follow that, but the five
packages added in 2026 (`graph`, `graph_neo4j`, `graphql`, `mysql`, `sqlite`)
carry **MIT** (AnhQuan Nguyen). This is fine legally — both are permissive —
but the stated rule and the LICENSE tree disagree and should be reconciled.

| Package | LICENSE | Copyright | Notes |
|---|---|---|---|
| `build_runner` | BSD-2-Clause | 2018, stable/kernel | legacy |
| `cli` | BSD-2-Clause | 2018, Stable Kernel LLC | legacy |
| `codable` | BSD-2-Clause | 2018, stable/kernel | legacy |
| `common` | BSD-2-Clause | 2018, stable/kernel | legacy |
| `config` | **BSD-3-Clause** | 2016, Stable Kernel LLC | legacy; the only 3-clause (extra no-endorsement clause) |
| `core` | BSD-2-Clause | 2018, Stable Kernel LLC | legacy |
| `fs_test_agent` | BSD-2-Clause | 2019, Stable Kernel LLC | legacy |
| `graph` | **MIT** | 2026, AnhQuan Nguyen | new |
| `graph_neo4j` | **MIT** | 2026, AnhQuan Nguyen | new |
| `graphql` | **MIT** | 2026, AnhQuan Nguyen | new |
| `isolate_exec` | BSD-2-Clause | 2018, stable/kernel | legacy |
| `isolate_exec_test_packages` | **NO LICENSE** | — | internal test fixture; not published |
| `mysql` | **MIT** | 2026, AnhQuan Nguyen | new |
| `open_api` | BSD-2-Clause | 2016, Stable Kernel LLC | legacy |
| `password_hash` | **MIT** | 2017, stable/kernel | predates the convention but is already MIT |
| `postgresql` | BSD-2-Clause | 2018, Stable Kernel LLC | legacy |
| `runtime` | BSD-2-Clause | 2019, Stable Kernel LLC | legacy |
| `sqlite` | **MIT** | 2026, AnhQuan Nguyen | new |
| `test_harness` | BSD-2-Clause | 2018, stable/kernel | legacy |

Summary by license:
- **BSD-2-Clause** (11): `build_runner`, `cli`, `codable`, `common`, `core`,
  `fs_test_agent`, `isolate_exec`, `open_api`, `postgresql`, `runtime`,
  `test_harness`
- **BSD-3-Clause** (1): `config`
- **MIT** (6): `graph`, `graph_neo4j`, `graphql`, `mysql`, `password_hash`,
  `sqlite`
- **No LICENSE** (1): `isolate_exec_test_packages` (test fixture only — does
  not need one; verify it's not accidentally published)

Root `LICENSE`: BSD-2-Clause "conduit-dart and contributors, 2021" — applies
to the workspace as a whole when packages are not individually licensed.

### Pubspec metadata

Per-package `pubspec.yaml` files do **not** declare an explicit `license:`
field (Dart pub doesn't require it — pub.dev infers from the LICENSE file).
The workspace root `pubspec.yaml` carries the `homepage` / `repository` /
`issue_tracker` URLs only.

**Risk tier:** 🟡 yellow. Mixed posture is legal and compatible; the stated
rule should be reconciled with reality but this does not block v7.

**Remediation (optional, not v7-blocking):**
- Pick one: relicense the five MIT packages to the root BSD-2 license (the
  copyright holder can do this unilaterally before first publish), **or**
  update `CLAUDE.md` to the actual rule: *"original Stable-Kernel-era
  packages retain BSD-2-Clause; new packages get MIT; `config` is
  BSD-3-Clause for historical reasons."*
- Optional: add an explicit `license: MIT` / `license: BSD-2-Clause` field
  to each `pubspec.yaml` so pub.dev's per-package metadata reflects the
  per-package LICENSE without relying on inference.
- ~~`isolate_exec_test_packages/pubspec.yaml` should set `publish_to: none`~~
  — verified 2026-11-01: already set, so the missing LICENSE never reaches
  pub.dev.

---

## D1 — direct + transitive dependency licenses

Transitive graph: 94 hosted packages (lockfile, runtime+dev). Classified by
LICENSE body, deduped:

| License | Count | Notable members |
|---|---|---|
| **BSD-3-Clause** | 77 | `analyzer`, `args`, `async`, `collection`, `crypto`, `http`, `meta`, `path`, `postgres`, `shelf`, `test`, `yaml_edit`, all `build_*`, `dart_lang/*` stack |
| **MIT** | 10 | `xml`, `yaml`, `sqlite3`, `petitparser`, `html`, `mysql_dart`, `prompts`, `cli_launcher`, `node_preamble`, `pub_updater` |
| **Apache-2.0** | 4 | `ansi_styles`, `melos` (dev), `quiver`, `conventional_commit` |
| **BSD-2-Clause** | 3 | `tuple`, `recase`, `mustache_template` |

**No GPL / LGPL / AGPL / SSPL / Elastic / commercial / dual-license deps.**
The graph is uniformly permissive and MIT-compatible (which covers both the
new MIT-licensed packages and the legacy BSD-licensed ones).

**Risk tier:** 🟢 green for the graph as a whole. Apache-2.0 has the
strictest attribution requirement of the bunch (NOTICE preservation when
binaries redistribute, which Conduit AOT binaries do); see Finding A1.

---

## D2 — `test_core-3.1.0` ships without a LICENSE file — ✅ resolved

**2026-11-01:** the workspace now resolves `test_core` 0.6.18, whose
published tarball includes its BSD-3-Clause LICENSE. Original finding kept
below for the record.

`test_core` is an internal Dart team package (`dart-lang/test`) and is
upstream-licensed BSD-3-Clause. The specific `3.1.0` release on pub.dev
didn't ship a LICENSE file inside the published tarball. Other versions of
the same package do.

Impact: minimal. The license is well-known and applies by the
upstream-repo `LICENSE`. But strictly speaking, redistributing the
`test_core-3.1.0` source pulled from the pub cache without including a
LICENSE puts the recipient in a hand-wavy position.

**Risk tier:** 🟢 green for v7. `test_core` is a `dev_dependency` only;
it's not shipped in any published Conduit package, AOT binary, or Docker
image. No remediation needed for ship; consider filing an issue upstream
(`dart-lang/test`) at leisure.

---

## A1 — Attribution in AOT binaries (the one followup worth doing)

The `default` template smoke (`ci/template-aot-smoke.sh`) produces a
`dart compile exe` binary from a fresh `conduit create` project. That
binary statically links every transitive dep — by license terms, the
recipient is entitled to receive the LICENSE text of each linked dep.

Current state: `dart compile exe` does **not** embed LICENSE files in the
output binary. The smoke script doesn't bundle a `LICENSES.txt` either.
Users who build their own conduit-based server and ship it as a binary
inherit the same gap.

Impact varies by license:
- **BSD-2/3 + MIT**: source-form notice is the obligation; binary
  distribution does NOT require LICENSE bundling in the binary. Standard
  practice is "the LICENSE files of all deps are available in the source
  tree"; for a pub-cache-built binary that means the cache directory or
  the upstream repos. Defensible but not great.
- **Apache-2.0** (4 deps: `ansi_styles`, `melos`, `quiver`,
  `conventional_commit`): explicitly requires the NOTICE file (if any) and
  the LICENSE to be conveyed with binary distributions. Of those, `melos`
  is dev-only and not in runtime AOT. `ansi_styles` and `conventional_commit`
  are also Melos transitives, dev-only. `quiver` is the one that may end
  up in runtime AOT depending on which Conduit subpackages pull it
  (`packages/core`'s deps include `quiver`).

**Risk tier:** 🟠 orange. Not a v7 ship blocker because (a) most users
will ship source-form Dart packages via pub.dev, not the AOT binary, and
(b) the obligation is on the *binary distributor*, who is the
user-of-Conduit not Conduit itself. But the template smoke binary the
docs point at as the canonical deploy artifact lacks attribution
plumbing, and that's a footgun for downstream users.

**Remediation (post-v7 is fine):**
- Add a `tool/bundle_licenses.dart` that walks `.dart_tool/package_config.json`
  → finds each dep's LICENSE in the pub cache → concatenates into a
  `THIRD_PARTY_LICENSES.txt`. Run it as a build step in
  `ci/template-aot-smoke.sh` and bake the file next to the binary.
- Document the recipe in `docs/deploy/binary-attribution.md` for downstream
  users.
- The five new MIT packages (`graph`, `graph_neo4j`, `graphql`, `mysql`,
  `sqlite`) inherit the same plumbing for free once it exists.

---

## R1 — Per-package LICENSE → pub.dev publication sanity

The tag-driven publish workflow (`.github/workflows/publish.yml`) uses
`melos exec --order-dependents` to publish each package independently. Each
package's pubspec.yaml + the LICENSE file in that package's directory ARE
what pub.dev surfaces on the package's pub.dev page. This is correct:
each of the 19 packages will show its own copyright + license accurately,
because each ships its own LICENSE file.

The implication: the **first** publish of `conduit_graph`, `conduit_graph_neo4j`,
`conduit_graphql`, `conduit_mysql`, `conduit_sqlite` will publish their MIT
LICENSE files (correct, per L1). `conduit_postgresql` and the 10 other
legacy packages will publish their BSD-2-Clause LICENSE files (correct).
No remediation needed.

**Risk tier:** 🟢 green.

---

## What I checked but did not change

- I did **not** modify any LICENSE file.
- I did **not** modify any `pubspec.yaml` (no `license:` field added).
- I did **not** add a `THIRD_PARTY_LICENSES.txt` or attribution plumbing
  (that's Finding A1's remediation, slated for post-v7).
- I did **not** change `CLAUDE.md`'s licensing rule — that's the
  maintainer's call; the options are in L1's remediation section.

---

## Cross-reference

- Hardener artifact: `hardening-checklist.md` (top-3 to ship before tagging
  `v7.0.0`). The hardener noted licensing was "already encoded in tree and
  matches the stated rule" — this audit refines that: it's encoded in
  tree, but the actual rule is
  *legacy-BSD + new-MIT*, not *BSD-2 throughout* as `CLAUDE.md` states.
  Substantively the same ship verdict (🟢 ship-safe); the difference is in
  how the rule is documented.
- Top-3 ship-blockers identified by the hardener (migration guide,
  first-time publish for the 5 new packages, dry-run-via-workflow_dispatch
  before tag push) all remain the priority. **License posture adds no
  ship-blocker.**
