# Load-testing harness (k6)

Produces the load-test evidence for connection pooling
(`docs/CONNECTION_POOLING.md`); design rationale in
`docs/LOAD_TESTING.md`, scenario guide in `docs/SCALE_TESTING.md`.

`target/` and `monitor/` are *private* workspace members: `melos
bootstrap` resolves them and `melos run analyze` type-checks them on
every PR, but publish/test scripts skip them. A smoke-scale run of the
whole harness (`ci/load-smoke.sh`) is wired into Woodpecker as the
`load-test-smoke` step — it fires only on `cron` or `manual` pipeline
events, never on PRs. Create the cron in the Woodpecker repo settings
(suggested: `load-smoke`, weekly) or trigger a manual run from the UI.

## Pieces

| Path | What it is |
| --- | --- |
| `target/` | Minimal Conduit app, entirely env-configured (`ISOLATES`, `POOL_SIZE`, `POSTGRES_*`). Routes: `/items` (read/insert), `/tx` (transactional insert+count), `/slow?ms=` (pg_sleep), `/healthz`. |
| `monitor/` | Sidecar that attaches to the target's Dart VM service, samples per-isolate heap stats every second, serves the latest sample as JSON, and appends JSONL. |
| `k6/pooling_baseline.js` | Three load scenarios (read-heavy, write+tx mix, slow-query) plus a 1-VU monitor scenario that re-emits the sidecar's per-isolate metrics as k6 Trends. |

## Running

```bash
# 1. database (repo root)
docker-compose -f ci/docker-compose.yaml up -d

# 2. target app — the run-matrix knobs are ISOLATES and POOL_SIZE
cd tool/load/target && dart pub get
ISOLATES=2 POOL_SIZE=1 dart run \
  --enable-vm-service=8181 --disable-service-auth-codes bin/main.dart

# 3. isolate monitor
cd tool/load/monitor && dart pub get
dart run bin/isolate_monitor.dart --vm ws://127.0.0.1:8181/ws --port 9091

# 4. k6 (https://grafana.com/docs/k6/latest/set-up/install-k6/)
k6 run --tag isolates=2 --tag pool=1 \
  -e TARGET=http://127.0.0.1:8888 -e MONITOR=http://127.0.0.1:9091 \
  -e RATE=50 -e DURATION=60s -e SLOW_MS=100 \
  tool/load/k6/pooling_baseline.js
```

`--disable-service-auth-codes` removes the auth token from the VM-service
URL. That service can evaluate code in the process — only ever bind it to
localhost on a dev machine.

## The pooling run matrix

Repeat the k6 run for each cell, keeping `--tag isolates=… --tag pool=…`
accurate; compare `http_req_duration{endpoint:slow}` p95 and
`dart_isolate_heap_bytes` across cells.

| | pool=1 | pool=4 | pool=8 |
| --- | --- | --- | --- |
| isolates=1 | legacy default | | |
| isolates=2 | | | |
| isolates=4 | | | |

Expected shape: on `slow_query`, pool=1 saturates when the arrival rate
exceeds `isolates × 1000/SLOW_MS` req/s and p95 grows with queue depth;
pooled cells shift that knee by roughly the pool factor. `read_heavy`
should move much less — that difference localizes the win to connection
contention rather than general overhead.

For long comparison runs, add `-o experimental-prometheus-rw` (k6's
built-in Prometheus remote-write output) and graph k6 + sidecar series
together in Grafana.
