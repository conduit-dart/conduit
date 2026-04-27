#!/usr/bin/env bash
# Run any subset of the deployable-state gates locally against the same
# dart:beta image Woodpecker uses. Mirrors .woodpecker.yml step-for-step
# so a green local run is a strong predictor of a green CI run.
#
# Usage:
#   ci/run-local.sh                # run every gate
#   ci/run-local.sh lint aot-smoke # run only the named gates
#
# Available gates: lint build-runner-tests workspace-unit-tests
#                  aot-smoke legacy-smoke core-integration-tests
#
# State that persists between runs:
#   docker volume "conduit-pub-cache" — workspace pub cache
#   docker volume "conduit-pgdata"    — Postgres data dir for the
#                                       integration suite
#
# Both volumes are local; rm them to force a clean bootstrap.

set -euo pipefail

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
DART_IMAGE="dart:beta"
PG_IMAGE="postgres:18.0"
PUB_VOL="conduit-pub-cache"
PG_VOL="conduit-pgdata"
PG_CONTAINER="conduit-ci-postgres"

ALL_GATES=(lint build-runner-tests workspace-unit-tests aot-smoke legacy-smoke template-aot-smoke core-integration-tests)

if [ "$#" -eq 0 ]; then
  GATES=("${ALL_GATES[@]}")
else
  GATES=("$@")
fi

run_in_dart() {
  # $1 = step label, rest = bash -c body
  local label="$1"; shift
  echo
  echo "================================================================"
  echo "== $label"
  echo "================================================================"
  docker run --rm \
    -v "$WORKSPACE":/conduit \
    -v "$PUB_VOL":/conduit/.pub-cache \
    -w /conduit \
    -e PUB_CACHE=/conduit/.pub-cache \
    --network "${NETWORK:-bridge}" \
    "$DART_IMAGE" bash -c "$*"
}

ensure_bootstrap() {
  echo "==> bootstrap (pub cache: $PUB_VOL)"
  docker volume inspect "$PUB_VOL" >/dev/null 2>&1 || docker volume create "$PUB_VOL" >/dev/null
  run_in_dart "bootstrap" '
    export PATH="$PATH:$PUB_CACHE/bin"
    if ! command -v melos >/dev/null; then
      dart pub global activate melos
    fi
    melos bootstrap
  '
}

start_postgres() {
  if docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
    echo "==> postgres already running"
    return
  fi
  echo "==> starting postgres ($PG_IMAGE)"
  docker volume inspect "$PG_VOL" >/dev/null 2>&1 || docker volume create "$PG_VOL" >/dev/null
  docker run -d --rm \
    --name "$PG_CONTAINER" \
    --network conduit-ci \
    -e POSTGRES_USER=conduit_test_user \
    -e POSTGRES_PASSWORD='conduit!' \
    -e POSTGRES_DB=conduit_test_db \
    -v "$PG_VOL":/var/lib/postgresql/data \
    "$PG_IMAGE" >/dev/null
  # Wait for ready.
  for _ in $(seq 1 30); do
    docker exec "$PG_CONTAINER" pg_isready -U conduit_test_user >/dev/null 2>&1 && break
    sleep 1
  done
}

stop_postgres() {
  docker stop "$PG_CONTAINER" >/dev/null 2>&1 || true
}

ensure_network() {
  docker network inspect conduit-ci >/dev/null 2>&1 || docker network create conduit-ci >/dev/null
}

# Ensure bootstrap once for every run.
ensure_bootstrap

trap 'stop_postgres' EXIT

for gate in "${GATES[@]}"; do
  case "$gate" in
    lint)
      run_in_dart "lint" '
        export PATH="$PATH:$PUB_CACHE/bin"
        melos run analyze
      '
      ;;

    build-runner-tests)
      run_in_dart "build-runner-tests" '
        export PATH="$PATH:$PUB_CACHE/bin"
        cd packages/build_runner && dart test -r failures-only
      '
      ;;

    workspace-unit-tests)
      run_in_dart "workspace-unit-tests" '
        export PATH="$PATH:$PUB_CACHE/bin"
        export TEST_VALUE=1
        export TEST_BOOL=true
        export TEST_DB_ENV_VAR="postgres://user:password@host:5432/dbname"
        melos exec --fail-fast \
          --scope conduit_codable \
          --scope conduit_open_api \
          --scope conduit_password_hash \
          --scope conduit_config \
          -- "dart test -r failures-only"
      '
      ;;

    aot-smoke)
      run_in_dart "aot-smoke" '
        export PATH="$PATH:$PUB_CACHE/bin"
        bash ci/aot-smoke.sh
      '
      ;;

    legacy-smoke)
      run_in_dart "legacy-smoke" '
        export PATH="$PATH:$PUB_CACHE/bin"
        dart pub global activate -spath packages/cli
        melos cache-source --no-select
        bash ci/legacy-smoke.sh
      '
      ;;

    template-aot-smoke)
      run_in_dart "template-aot-smoke" '
        export PATH="$PATH:$PUB_CACHE/bin"
        dart pub global activate -spath packages/cli
        melos cache-source --no-select
        bash ci/template-aot-smoke.sh
      '
      ;;

    core-integration-tests)
      ensure_network
      start_postgres
      NETWORK=conduit-ci run_in_dart "core-integration-tests" '
        export PATH="$PATH:$PUB_CACHE/bin"
        export POSTGRES_HOST='"$PG_CONTAINER"'
        export POSTGRES_PORT=5432
        export POSTGRES_USER=conduit_test_user
        export POSTGRES_PASSWORD="conduit!"
        export POSTGRES_DB=conduit_test_db
        export PGPASSWORD="conduit!"
        export TEST_DB_ENV_VAR="postgres://user:password@host:5432/dbname"
        export TEST_VALUE=1
        export TEST_BOOL=true
        cd packages/core && dart test -r failures-only
      '
      ;;

    *)
      echo "Unknown gate: $gate"
      echo "Valid gates: ${ALL_GATES[*]}"
      exit 2
      ;;
  esac
done

echo
echo "================================================================"
echo "== All requested gates passed: ${GATES[*]}"
echo "================================================================"
