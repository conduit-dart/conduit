// k6 harness for the connection-pooling run matrix (tool/load/README.md).
//
//   k6 run -e TARGET=http://127.0.0.1:8888 \
//          -e MONITOR=http://127.0.0.1:9091 \
//          -e RATE=50 -e DURATION=60s -e SLOW_MS=100 \
//          tool/load/k6/pooling_baseline.js
//
// Three load scenarios exercise the store differently, plus one 1-VU
// "pseudo-plugin" scenario that polls the isolate_monitor sidecar and
// re-emits per-isolate Dart heap stats as k6 Trend metrics — so isolate
// resources land in the same output stream as latency and can gate
// thresholds. Tag every run with the server-side config for comparison:
//
//   k6 run --tag pool=8 --tag isolates=2 ...

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Gauge } from 'k6/metrics';

const TARGET = __ENV.TARGET || 'http://127.0.0.1:8888';
const MONITOR = __ENV.MONITOR || 'http://127.0.0.1:9091';
const RATE = Number(__ENV.RATE || 50);
const DURATION = __ENV.DURATION || '60s';
const SLOW_MS = Number(__ENV.SLOW_MS || 100);

const dartHeapUsage = new Trend('dart_isolate_heap_bytes');
const dartHeapCapacity = new Trend('dart_isolate_heap_capacity_bytes');
const dartExternalUsage = new Trend('dart_isolate_external_bytes');
const dartIsolateCount = new Gauge('dart_isolate_count');

export const options = {
  scenarios: {
    // Cheap indexed reads: measures per-request overhead; pooling should
    // change little here at moderate rates.
    read_heavy: {
      executor: 'constant-arrival-rate',
      exec: 'readHeavy',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: 50,
      maxVUs: 500,
    },
    // Insert + transactional insert-and-count: exercises transaction
    // checkout, where each pooled transaction holds a dedicated connection.
    write_tx_mix: {
      executor: 'constant-arrival-rate',
      exec: 'writeTxMix',
      rate: Math.max(1, Math.floor(RATE / 5)),
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: 20,
      maxVUs: 200,
    },
    // The pooling showcase: pg_sleep-backed requests. With POOL_SIZE=1
    // these serialize per isolate (p95 explodes as rate exceeds
    // isolates × 1000/SLOW_MS); with POOL_SIZE=N they overlap N deep.
    slow_query: {
      executor: 'constant-arrival-rate',
      exec: 'slowQuery',
      rate: Math.max(1, Math.floor(RATE / 10)),
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: 20,
      maxVUs: 300,
    },
    // Pseudo-plugin: pulls the Dart VM sidecar samples into k6 metrics.
    isolate_monitor: {
      executor: 'constant-vus',
      exec: 'monitorIsolates',
      vus: 1,
      duration: DURATION,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    'http_req_duration{endpoint:items_read}': ['p(95)<250'],
    'http_req_duration{endpoint:tx}': ['p(95)<500'],
    // Generous bound; exists mainly so the slow submetric appears in
    // --summary-export (k6 only exports submetrics that have thresholds),
    // which the CI cross-run comparison keys on.
    'http_req_duration{endpoint:slow}': ['p(95)<30000'],
    // Guardrail rather than target: catches unbounded heap growth (e.g. a
    // pool/connection leak) during the run.
    dart_isolate_heap_bytes: ['max<536870912'], // 512 MiB per isolate
  },
};

export function readHeavy() {
  const res = http.get(`${TARGET}/items?limit=20`, {
    tags: { endpoint: 'items_read' },
  });
  check(res, { 'read 200': (r) => r.status === 200 });
}

export function writeTxMix() {
  const write = http.post(`${TARGET}/items`, null, {
    tags: { endpoint: 'items_write' },
  });
  check(write, { 'write 200': (r) => r.status === 200 });

  const tx = http.get(`${TARGET}/tx`, { tags: { endpoint: 'tx' } });
  check(tx, { 'tx 200': (r) => r.status === 200 });
}

export function slowQuery() {
  const res = http.get(`${TARGET}/slow?ms=${SLOW_MS}`, {
    tags: { endpoint: 'slow' },
    timeout: '30s',
  });
  check(res, { 'slow 200': (r) => r.status === 200 });
}

export function monitorIsolates() {
  const res = http.get(`${MONITOR}/metrics.json`, {
    tags: { endpoint: 'monitor' },
  });
  if (res.status !== 200) {
    return;
  }
  const sample = res.json();
  if (!sample || !sample.isolates) {
    return;
  }
  dartIsolateCount.add(sample.isolateCount);
  sample.isolates.forEach((iso) => {
    const tags = { isolate: iso.name || iso.id };
    if (iso.heapUsage != null) dartHeapUsage.add(iso.heapUsage, tags);
    if (iso.heapCapacity != null) {
      dartHeapCapacity.add(iso.heapCapacity, tags);
    }
    if (iso.externalUsage != null) {
      dartExternalUsage.add(iso.externalUsage, tags);
    }
  });
  // Sidecar samples on its own interval; poll at the same cadence.
  sleep(1);
}
