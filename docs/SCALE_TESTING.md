# Scale testing Conduit — scenario guide

How to use the k6 harness (`tool/load/`, design in
[LOAD_TESTING.md](LOAD_TESTING.md)) to answer scale questions about a
Conduit deployment. Scenario taxonomy follows Grafana's
[load test types guide](https://grafana.com/docs/k6/latest/testing-guides/test-types/);
each section maps the general pattern onto Conduit's two concurrency
knobs — `ISOLATES` and `POOL_SIZE` — with a public, citable example of
the failure mode it exists to catch.

All snippets assume the harness env vars (`TARGET`, `RATE`, `DURATION`,
`SLOW_MS`) and can be applied by editing the `scenarios` block of
`tool/load/k6/pooling_baseline.js` or a copy of it.

## 1. Smoke test — *does it work at all under trivial load?*

Minimal load, short duration; verifies wiring, not capacity. Grafana's
guidance: run smoke tests every time you touch the system, as a gate
before any larger test ([test types](https://grafana.com/docs/k6/latest/testing-guides/test-types/)).

This is exactly what CI runs: the `load-test-smoke` Woodpecker lane
(cron/manual events only) drives ~20 req/s for 30 s against pool=1 and
pool=8, hard-failing on k6 thresholds (error rate < 1%, per-isolate heap
< 512 MiB) and printing an informational p95 comparison. **Public
precedent for load tests as a CI feature:** GitLab ships k6-based
[Load Performance Testing](https://docs.gitlab.com/ci/testing/load_performance_testing/)
as a first-class CI job, and their Quality team's
[GitLab Performance Tool](https://gitlab.com/gitlab-org/quality/performance/-/blob/main/docs/k6.md)
is built on k6 to validate GitLab's own reference architectures.

```
RATE=20 DURATION=30s   # k6: constant-arrival-rate, low fixed rate
```

## 2. Average-load test — *typical day*

Ramp to the traffic you actually observe in production, hold, ramp down.
The result is your baseline: latency percentiles and per-isolate heap at
normal load, against which every other scenario is compared
([k6-learn: load testing](https://github.com/grafana/k6-learn/blob/main/Modules/I-Performance-testing-principles/03-Load-Testing.md)).

Conduit mapping: run the matrix from `tool/load/README.md` at your real
rate. If `read_heavy` p95 moves when you raise `POOL_SIZE`, you have
connection contention even on fast queries — evidence for revisiting the
pooled default (see CONNECTION_POOLING.md's deferred decision).

## 3. Stress test — *peak traffic*

Same shape as average-load but at your peak multiple (2-5× typical).
What to watch in Conduit: the `slow_query` knee. A single-connection
isolate is a serial queue with capacity `1000/SLOW_MS` req/s; offered
load beyond `ISOLATES × capacity` grows the queue without bound, and p95
— not throughput — is where it shows first. Pooling shifts the knee by
the pool factor; stress runs tell you whether your production peak sits
on the safe side of it.

**Public example of the failure mode:** during Black Friday 2019 a
Shopify Plus retailer's traffic spiked to ~8× normal; by 6:47 AM product
pages timed out and checkout returned 503s — found and fixed only after
load testing at peak multiples
([case study](https://smartsmssolutions.com/resources/blog/business/free-website-load-testing-tools-bulk)).
Conduit returns exactly that 503 when the store's connection can't be
opened or queries time out, so the stress run is where you calibrate
`ISOLATES × POOL_SIZE` against Postgres `max_connections`.

## 4. Spike test — *sudden, massive surge*

No ramp: jump from idle to extreme load in seconds, hold briefly, drop.
Grafana's k6 team covers the pattern and its k6 encoding in
[peak, spike, and soak tests](https://grafana.com/blog/load-testing-grafana-k6-peak-spike-and-soak-tests/).

```js
spike: {
  executor: 'ramping-arrival-rate',
  startRate: 5, timeUnit: '1s', preAllocatedVUs: 500,
  stages: [
    { target: 5,   duration: '30s' },  // idle
    { target: 400, duration: '10s' },  // the spike
    { target: 400, duration: '1m'  },
    { target: 5,   duration: '30s' },  // recovery
  ],
  exec: 'slowQuery',
},
```

Conduit-specific things a spike exposes that steady load can't:
lazy-connection pile-up (the first spike after idle opens pool
connections all at once), and whether the app *recovers* — per-isolate
heap in the monitor's JSONL should return to baseline after the spike;
if it doesn't, something (connections, buffered responses) is leaking.

## 5. Soak test — *hours at moderate load*

Typical load held for hours. This is the scenario the per-isolate
monitor was built for: k6's own metrics can't see a slow heap leak, but
`dart_isolate_heap_bytes` sampled at 1 Hz for four hours can — and the
512 MiB threshold turns "the graph creeps up" into a failed run
([test types: soak](https://grafana.com/docs/k6/latest/testing-guides/test-types/),
[peak/spike/soak blog](https://grafana.com/blog/load-testing-grafana-k6-peak-spike-and-soak-tests/)).

Conduit specifics worth soaking: connection reconnect churn (kill the DB
mid-soak and confirm the store's reopen-on-next-query behavior doesn't
leak), pooled-connection lifetime, and ORM query-plan memory in
long-lived isolates.

## 6. Breakpoint test — *find the ceiling*

Ramp arrival rate continuously until the system breaks; record where and
how. Use `ramping-arrival-rate` toward an unreachable target and let the
error-rate threshold abort the test (`abortOnFail: true`). The value for
Conduit is the *shape* of the breakage: single-connection stores break
by latency inflation (queue growth → timeouts → 503s), pooled stores by
Postgres `max_connections` exhaustion — which one you hit first tells
you which knob to turn next.

## Where to run these

Smoke and relative comparisons: the CI lane / any dev machine. Anything
whose absolute numbers will be cited: two ephemeral cloud machines so
the load generator doesn't share CPU with the target — provisioning
script and cost analysis in
[LOAD_PROVISIONING.md](LOAD_PROVISIONING.md) (short version: ~€0.10 per
session on hourly-billed Hetzner ARM VMs).

## Reporting conventions

Every run must carry `--tag isolates=… --tag pool=…` (and `--tag
scenario=…` for custom shapes) so results remain comparable; long runs
should add `-o experimental-prometheus-rw` and land in Grafana alongside
the sidecar's series. Keep raw `--summary-export` JSON and the monitor
JSONL for anything you intend to cite in a PR — the pooling default
decision (CONNECTION_POOLING.md) will be argued from these artifacts.

## Sources

- [k6 load test types](https://grafana.com/docs/k6/latest/testing-guides/test-types/) — taxonomy this guide follows
- [Load testing with Grafana k6: peak, spike, and soak](https://grafana.com/blog/load-testing-grafana-k6-peak-spike-and-soak-tests/)
- [k6-learn: load testing principles](https://github.com/grafana/k6-learn/blob/main/Modules/I-Performance-testing-principles/03-Load-Testing.md)
- [GitLab Load Performance Testing (k6 in CI)](https://docs.gitlab.com/ci/testing/load_performance_testing/)
- [GitLab Performance Tool docs](https://gitlab.com/gitlab-org/quality/performance/-/blob/main/docs/k6.md)
- [Black Friday load-failure case study](https://smartsmssolutions.com/resources/blog/business/free-website-load-testing-tools-bulk)
