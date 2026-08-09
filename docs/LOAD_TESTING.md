# Load-testing design — k6 harness + isolate resource analysis

Status: harness implemented under `tool/load/` (2026-07); evidence runs
still owed. Companion to [CONNECTION_POOLING.md](CONNECTION_POOLING.md),
which this exists to measure.

## Goals

1. Produce before/after evidence for `maxConnectionCount` across an
   isolates × pool-size matrix.
2. Observe **per-isolate** resources (heap, isolate count, eventually CPU)
   *during* load, in the same output stream as latency — Conduit's whole
   concurrency story is isolates, and process-level metrics can't show
   whether one isolate is hot while three idle.
3. Stay off the PR critical path. The Dart tools are *private* workspace
   members (so `melos run analyze` type-checks them on every PR), and a
   smoke-scale run (`ci/load-smoke.sh`, Woodpecker `load-test-smoke`
   step) fires only on cron/manual pipeline events. Full-scale runs stay
   manual — see [SCALE_TESTING.md](SCALE_TESTING.md) for the scenario
   guide.

## Why k6

Scenario-based arrival-rate executors (constant-arrival-rate holds the
offered load constant while latency degrades — the right shape for finding
the saturation knee), first-class custom metrics and thresholds, tags for
run-matrix bookkeeping, and built-in Prometheus remote-write output
(merged into k6 core as an experimental module since v0.42, so no custom
binary is needed for dashboards).

## Architecture

```
k6 (scenarios: read_heavy / write_tx_mix / slow_query)
 │                                  ┌──────────────────────────────┐
 ├── HTTP load ────────────────────▶│ target app (tool/load/target)│
 │                                  │  ISOLATES × POOL_SIZE, env-  │
 │                                  │  configured, --enable-vm-    │
 │                                  │  service                     │
 │                                  └──────────────┬───────────────┘
 │                                                 │ VM service WS
 │   1-VU monitor scenario           ┌─────────────▼───────────────┐
 └── polls /metrics.json ──────────▶│ isolate_monitor sidecar      │
     re-emits as k6 Trends           │ (package:vm_service): getVM │
     (dart_isolate_heap_bytes, …)    │ + getMemoryUsage per isolate│
                                     │ → JSON endpoint + JSONL     │
                                     └─────────────────────────────┘
```

The monitor scenario is a deliberate "pseudo-plugin": a plain-JS k6
scenario that ingests external metrics via HTTP polling. Because the
values become real k6 `Trend`s, thresholds can gate on them — e.g. the
harness fails the run if any isolate's heap exceeds 512 MiB, which turns
a connection/pool leak into a red build instead of a graph someone has
to eyeball.

## Do we need to write a k6 plugin (xk6 extension)?

**Not for v1.** k6 extensions come in two kinds — JS-API extensions and
metric-output extensions, both built into a custom binary with `xk6
build`. What each would buy us today is already covered:

- *Output side*: Prometheus remote-write is already in k6 core; the
  sidecar's JSONL covers offline analysis.
- *Input side*: per-isolate heap via `getMemoryUsage` is cheap enough to
  poll at 1 Hz over HTTP from plain JS.

**Where a real extension becomes justified — `xk6-dartvm` sketch.** The
genuine gap is **per-isolate CPU attribution**. The VM service exposes it
only through `getCpuSamples(isolateId, timeOrigin, timeExtent)` — sample
buffers that need windowed collection and aggregation, which is too heavy
and too stateful for a 1 Hz JS polling loop. A Go JS-API extension
(`import dartvm from 'k6/x/dartvm'`) would:

1. hold a persistent WebSocket to the VM service (JSON-RPC), registered
   in `setup()` from the script;
2. subscribe to GC/Isolate event streams (`streamListen`) instead of
   polling, so isolate spawn/exit and GC pauses become k6 events with
   exact timestamps;
3. window `getCpuSamples` per isolate and emit
   `dart_isolate_cpu_percent{isolate=…}` alongside the heap Trends;
4. register its metrics through k6's Go metrics registry, so thresholds
   work identically to the pseudo-plugin's.

Effort estimate: a few hundred lines of Go plus xk6 build plumbing; the
maintenance cost is tracking the VM service protocol (currently 4.x).
Decision: build it only if a pooling investigation actually gets blocked
on "which isolate is burning CPU" — heap, latency, and the saturation
knee answer the current questions without it.

## Interpreting the matrix

The `slow_query` scenario (pg_sleep, default 100 ms) is the discriminator:
a single-connection isolate is a serial queue with service time ~SLOW_MS,
so its capacity is `1000/SLOW_MS` req/s and offered load beyond that grows
the queue without bound — p95 latency, not throughput, is where it shows.
Pooling multiplies per-isolate capacity by the pool size. `read_heavy`
(sub-millisecond queries) should barely move: if it *does* improve
materially, that's evidence of contention even on fast queries and an
argument for revisiting the pooled default in the next major
(CONNECTION_POOLING.md's deferred decision).

Per-isolate heap matters in the same runs because pooling trades memory
for concurrency: each pooled connection holds buffers, and N isolates ×
M connections is the multiplication documented in the pooling design.
The 512 MiB threshold is a leak tripwire, not a performance target.

## Sources

- [k6 Prometheus remote write output](https://grafana.com/docs/k6/latest/results-output/real-time/prometheus-remote-write/)
- [xk6-output-prometheus-remote (merged into k6 core)](https://github.com/grafana/xk6-output-prometheus-remote)
- [Dart VM Service Protocol](https://github.com/dart-lang/sdk/blob/main/runtime/vm/service/service.md)
- [package:vm_service MemoryUsage](https://pub.dev/documentation/vm_service/latest/vm_service/MemoryUsage-class.html)
