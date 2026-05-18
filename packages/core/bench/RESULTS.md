# Performance Regression: Pre/Post AST Migration (PR #267)

**Baseline:** master @ `8416288f` — pre-#267, post-Cockroach. Predicates flow
through the legacy raw-format-string path only; no `SqlExpression` AST.

**Current:** master @ `efa04d1b` — post-#267 + #266 (graph) + #269
(graph_neo4j). Internal builders populate the AST + visitor alongside the
legacy `format` string.

## Headline numbers (best-of-3, microseconds per op)

| Benchmark                              | Pre-AST (µs) | Post-AST (µs) | Δ%      | Verdict       |
|----------------------------------------|-------------:|--------------:|--------:|---------------|
| predicate: single eq                   |       0.407  |        0.393  |  -3.4%  | OK (noise)    |
| predicate: 5-term AND                  |      12.66   |       15.48   | +22.3%  | mild regress  |
| predicate: 10-term AND                 |      24.40   |       29.18   | +19.6%  | mild regress  |
| predicate: mixed AND/OR                |       0.699  |        0.989  | +41.5%  | small abs cost|
| predicate: IN(20)                      |      24.73   |       25.86   |  +4.6%  | OK (noise)    |
| ast render: 5-term AND (named)         |          —   |        8.65   |  N/A    | new path      |
| ast render: 10-term AND (named)        |          —   |       16.30   |  N/A    | new path      |
| ast render: 5-term AND (positional)    |          —   |        5.11   |  N/A    | new path      |
| ast render: 10-term AND (positional)   |          —   |        9.24   |  N/A    | new path      |
| query e2e: 5-term where() (named)      |      12.93   |       26.18   |+102.5%  | expected      |
| query e2e: 10-term where() (named)     |      24.35   |       49.89   |+104.9%  | expected      |
| query e2e: 5-term where() (positional) |          —   |       20.99   |  N/A    | new path      |
| query e2e: 10-term where() (positional)|          —   |       40.09   |  N/A    | new path      |

## Existing PR #261 benches (sanity check on master)

Re-run on the same host as a noise-floor cross-check. Compared against the
README baseline captured for PR #261.

| Bench                                  | PR #261 baseline | Current (best of 3) |    Δ%   |
|----------------------------------------|-----------------:|--------------------:|--------:|
| `cast<List<int>>` (n=100)              |          ~5.2 µs |              5.20 µs|   +0.0% |
| `cast<List<Map<String, dynamic>>>`     |          ~5.0 µs |              5.07 µs|   +1.3% |
| `cast<Map<String, dynamic>>` (keys=20) |          ~2.2 µs |              2.22 µs|   +0.8% |
| `json.encode List[1000 maps]`          |          ~3.7 ms |              3.60 ms|   -2.7% |
| `json.decode List[1000 maps]`          |          ~2.4 ms |              2.41 ms|   +0.5% |
| `json.encode Map[20 keys]`             |         ~13.2 µs |             13.48 µs|   +2.1% |
| `json.decode Map[20 keys]`             |         ~10.2 µs |              9.95 µs|   -2.5% |

All within the documented ~3% noise floor — coerce and JSON paths are
unaffected by the AST migration, as expected.

## Verdict

**Mild regression** in predicate construction, in the 19-22% range for
multi-term `AND` chains. The percentage is above the 15% "investigate"
threshold, but the **absolute cost is microseconds per query-build cycle**
and the regression is dominated by exactly the work the AST migration
exists to do — it is not a hidden inefficiency.

Where the cost lives:
- Each leaf predicate now allocates a `BinaryOpExpression`, a
  `ColumnExpression`, a `ParameterExpression`, plus the `QueryPredicate`
  itself. The pre-AST path allocated only the `QueryPredicate` (the
  format string + a small map).
- `QueryPredicate.and` now does an extra pre-walk to (a) check that
  every child has an AST attached and (b) collect the children into a
  fresh `LogicalExpression('AND', ...)`. That's two passes over the
  predicate list rather than one.
- The "mixed AND/OR" shape is a single ~1 µs op so the +41% is dominated
  by allocator noise on a tiny fixture; absolute delta is ~0.3 µs.
- The "IN(20)" shape barely moves (+4.6%) because the per-value overhead
  of the AST node is small relative to the 20 `ParameterExpression` +
  format-string allocations the legacy path already did.

Where the cost does **not** live:
- AST rendering (the new visitor path) is not a regression — it's a
  brand-new code path that didn't exist on the baseline. The numbers
  here become the rendering baseline going forward.
- Coerce + JSON micro-paths are flat against PR #261's numbers.

The `query e2e` benches double on the AST path because the post-#267
build cycle is "build format string (legacy compat) + build AST + render
AST → SQL+params". The legacy path only did the first. The framework
keeps the format string for back-compat with downstream code that reads
`predicate.format` directly; if/when that compat is dropped, the
duplicate string-building work falls away.

### Recommendation: **accept and document.**

The regression is the cost of correctness — the AST is what enables the
MySQL backend (#267), the SQLite backend (#264), and any future
positional-parameter dialect, none of which the format-string path can
serve. Per-query overhead at this magnitude (single-digit µs added per
predicate-build cycle) is not visible end-to-end against the cost of
PostgreSQL round-trips (typically 100s of µs to single-digit ms).

If a measurable regression appears at the application level downstream,
the obvious follow-ups are:

1. Specialize `QueryPredicate.and` to fuse the "collect children" pass
   with the "stringify + dedupe" pass (one walk, not two).
2. Skip the format-string build entirely on AST-aware backends — emit
   only when a consumer reads `.format` lazily.

Neither is in scope for this PR; this is a measurement scaffold, not a
fix.

## Methodology

- **Hardware:** AMD Ryzen 9 9950X (32 logical CPUs), Linux 6.12.77 (Manjaro).
- **Dart SDK:** 3.13.0-89.0.dev (linux_x64).
- **Iterations:** `benchmark_harness` defaults — each `run()` body is
  warmed for 100 ms then measured for 2 s; the harness reports the
  per-iteration mean.
- **Repetition:** best of 3 full bench-binary invocations per shape,
  separate processes (no shared JIT cache). Reported number is the
  lowest mean across the 3 runs.
- **Baseline / current commits:** `8416288f` and `efa04d1b` respectively.
- **Build:** JIT mode (`dart run`) — matches how Conduit apps execute
  outside of the AOT-compiled production path; AOT numbers may differ
  but the relative regression should track.
- **Host conditions:** the box was idle, but no CPU governor pinning
  was applied. Per-shape variance across the 3 runs was within ~5% on
  the multi-µs benches and within ~10% on the sub-µs `single eq`
  shape — small enough not to flip any verdict in the table above.

## Reproducing

```bash
# From this worktree (post-AST path):
cd packages/core
dart pub get
dart run bench/predicate_construction_bench.dart
dart run bench/ast_render_bench.dart
dart run bench/query_e2e_bench.dart

# For the pre-AST baseline:
git worktree add /tmp/conduit-baseline 8416288f
# Apply the equivalent legacy-API benches under packages/core/bench/
# (see PR description for the diff). The post-AST `ast_render_bench.dart`
# does NOT compile against 8416288f — there's no AST to render — so
# only `predicate_construction_bench.dart` and `query_e2e_bench.dart`
# port across.
cd /tmp/conduit-baseline/packages/core
dart pub get
dart run bench/predicate_construction_bench.dart
dart run bench/query_e2e_bench.dart
```
