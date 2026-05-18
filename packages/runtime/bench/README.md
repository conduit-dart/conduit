# bench/ — runtime microbenchmarks

Baseline performance harness for `conduit_runtime`. Not a regression
gate yet — captures numbers so PRs touching the hot paths have
something to compare against.

## Run

```bash
cd packages/runtime
dart run bench/coerce_bench.dart
dart run bench/json_codec_bench.dart
```

Each script prints one line per benchmark in the form:

```
<name>(RunTime): <us> us.
```

`benchmark_harness` runs each `run()` body for ~2s, divides by the iteration
count, and reports the per-iteration time. Numbers are deterministic to
within ~3% on a quiet host.

## Benchmarks

### `coerce_bench.dart`

Targets `slow_coerce.cast<T>` over the three type-variant shapes most
commonly hit by ResourceController body-cast paths:

| Bench | Fixture |
|---|---|
| `cast<List<int>>` | 100-element int list |
| `cast<List<Map<String, dynamic>>>` | 50-row table-shaped list |
| `cast<Map<String, dynamic>>` | 20-key flat map |

Captures the baseline against which PRs that change the cast path (e.g.
PR #259's AOT specialization) can be A/B'd.

### `json_codec_bench.dart`

`dart:convert` floor under every JSON-shaped request the framework
serves. Conduit doesn't ship its own JSON codec, so this is a pure
SDK-level baseline — useful for spotting regressions in the SDK or in
host configuration (CPU governor, debug build, etc.).

| Bench | Payload |
|---|---|
| `json.encode List[1000 maps]` | Typical "list endpoint" response body |
| `json.decode List[1000 maps]` | Typical request body parse |
| `json.encode Map[20 keys]` | Typical "single resource" response |
| `json.decode Map[20 keys]` | Typical "single resource" parse |

## Baseline numbers (captured 2026-05-05, dart:beta in Docker on snowman)

These are starting reference points — re-capture on the PR's host before
A/B-comparing against a change.

| Bench | RunTime |
|---|---|
| `cast<List<int>>` (n=100) | ~5.2 µs |
| `cast<List<Map<String, dynamic>>>` (n=50) | ~5.0 µs |
| `cast<Map<String, dynamic>>` (keys=20) | ~2.2 µs |
| `json.encode List[1000 maps]` | ~3.7 ms |
| `json.decode List[1000 maps]` | ~2.4 ms |
| `json.encode Map[20 keys]` | ~13.2 µs |
| `json.decode Map[20 keys]` | ~10.2 µs |

## Adding a new bench

1. New file `bench/<thing>_bench.dart` with one or more
   `BenchmarkBase` subclasses + a `main()` that calls `.report()` on each.
2. Update this README's table.
3. Run it locally on a quiet host; capture the numbers in the PR
   description as the new baseline.

## Future scope (deferred)

The original sanity-check plan listed two more benches that need
fixtures larger than fits in this PR:

- `router_bench.dart` — 1k requests through a 100-route Router.
  Needs a host fixture; lives more naturally in `packages/core/bench/`.
- `startup_bench.dart` — `MirrorContext()` instantiation cost on a
  ~50-controller / ~20-ManagedObject fixture. Needs a synthetic app
  scaffold; warrants its own follow-up.

## Why no CI gate yet

Benchmark numbers vary by host, CPU governor state, neighbor processes,
and Dart SDK version. Add CI assertions only after the noise floor is
measured across a few hosts (laptop, CI runner, Woodpecker) and a stable
threshold is identified. Until then the harness exists for ad-hoc
before/after comparison on PRs that touch hot paths.
