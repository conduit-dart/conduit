#!/usr/bin/env bash
# Load-test smoke lane for Woodpecker (cron/manual only — see .woodpecker.yml).
#
# Runs the k6 pooling harness (tool/load/) at smoke scale against two store
# configurations — POOL_SIZE=1 (legacy) and POOL_SIZE=8 — and prints a
# comparison. Hard failures come from k6 thresholds inside each run (error
# rate, per-isolate heap cap); the cross-run comparison is informational so
# runner noise can't flake the build. See docs/SCALE_TESTING.md.
#
# Tunables (step environment): K6_VERSION, LOAD_RATE, LOAD_DURATION,
# LOAD_SLOW_MS, LOAD_ISOLATES.
set -euo pipefail

K6_VERSION="${K6_VERSION:-v1.1.0}"
LOAD_RATE="${LOAD_RATE:-20}"
LOAD_DURATION="${LOAD_DURATION:-30s}"
LOAD_SLOW_MS="${LOAD_SLOW_MS:-100}"
LOAD_ISOLATES="${LOAD_ISOLATES:-2}"

ROOT="$(pwd)"
OUT_DIR="${ROOT}/load-smoke-out"
mkdir -p "${OUT_DIR}"

# --- k6 binary -------------------------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq --no-install-recommends curl ca-certificates
fi
if ! command -v k6 >/dev/null 2>&1; then
  echo "installing k6 ${K6_VERSION}"
  curl -fsSL \
    "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /tmp
  install -m 0755 "/tmp/k6-${K6_VERSION}-linux-amd64/k6" /usr/local/bin/k6
fi
k6 version

cleanup() {
  [ -f "${OUT_DIR}/app.pid" ] && kill "$(cat "${OUT_DIR}/app.pid")" 2>/dev/null || true
  [ -f "${OUT_DIR}/monitor.pid" ] && kill "$(cat "${OUT_DIR}/monitor.pid")" 2>/dev/null || true
}
trap cleanup EXIT

run_case() {
  local pool="$1" summary="$2"

  echo "=== case: isolates=${LOAD_ISOLATES} pool=${pool} ==="
  (
    cd tool/load/target
    ISOLATES="${LOAD_ISOLATES}" POOL_SIZE="${pool}" \
      nohup dart run --enable-vm-service=8181 --disable-service-auth-codes \
      bin/main.dart >"${OUT_DIR}/target-pool${pool}.log" 2>&1 &
    echo $! >"${OUT_DIR}/app.pid"
  )

  for _ in $(seq 1 60); do
    curl -fs http://127.0.0.1:8888/healthz >/dev/null 2>&1 && break
    sleep 1
  done
  curl -fs http://127.0.0.1:8888/healthz >/dev/null # fail loudly if never up

  (
    cd tool/load/monitor
    nohup dart run bin/isolate_monitor.dart \
      --vm ws://127.0.0.1:8181/ws --port 9091 \
      --out "${OUT_DIR}/samples-pool${pool}.jsonl" \
      >"${OUT_DIR}/monitor-pool${pool}.log" 2>&1 &
    echo $! >"${OUT_DIR}/monitor.pid"
  )
  sleep 2

  k6 run \
    --tag "isolates=${LOAD_ISOLATES}" --tag "pool=${pool}" \
    --summary-export "${summary}" \
    -e TARGET=http://127.0.0.1:8888 \
    -e MONITOR=http://127.0.0.1:9091 \
    -e RATE="${LOAD_RATE}" -e DURATION="${LOAD_DURATION}" \
    -e SLOW_MS="${LOAD_SLOW_MS}" \
    tool/load/k6/pooling_baseline.js

  cleanup
  sleep 1
}

run_case 1 "${OUT_DIR}/summary-pool1.json"
run_case 8 "${OUT_DIR}/summary-pool8.json"

dart tool/load/ci/compare_summaries.dart \
  "${OUT_DIR}/summary-pool1.json" "${OUT_DIR}/summary-pool8.json"
