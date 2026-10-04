---
name: Performance regression
about: Something got measurably slower between two Conduit versions or Dart SDKs
title: "[PERF]"
labels: performance
assignees: ''

---

<!--
Precedent: #267 moved predicates to an AST and made multi-term predicate
construction ~20% slower (see #270 and packages/core/bench/RESULTS.md).
That was measured, documented, and accepted. Reports that come with a
reproducible benchmark like those get acted on; "it feels slower" can't be.
-->

**What got slower**
The operation (e.g. building a 10-term `where()` query, rendering a
response, decoding a request body) and how much slower, in numbers.

**Versions**
- Fast: Conduit `x.y.z`, Dart `x.y.z`
- Slow: Conduit `x.y.z`, Dart `x.y.z`
- Dart channel (`stable` / `beta` / `main`) and how Dart was installed:
- Backend, if relevant (`conduit_postgresql` / `_sqlite` / `_mysql` / …) and server version:
- OS / CPU:
- JIT (`dart run`) or AOT (`dart compile exe`):

**Bench reproducer**
Required. Smallest self-contained benchmark that shows the difference,
ideally a `package:benchmark_harness` `BenchmarkBase` in the style of
`packages/core/bench/` so it can be dropped in and run with
`dart run bench/<file>.dart`. Paste it here or link a gist/repo.

```dart

```

**Results**
Best-of-3 (or more) on the same machine, for both the fast and the slow
version. Paste raw output.

| Benchmark | Fast (µs/op) | Slow (µs/op) | Δ% |
| --- | ---: | ---: | ---: |
|  |  |  |  |

**Application-level impact**
Does it show up end to end (request latency, throughput, CPU)? Numbers
if you have them. Microbenchmark-only regressions are still worth
reporting; say so.

**Bisect (optional)**
If you narrowed it down to a commit or PR, which one.
