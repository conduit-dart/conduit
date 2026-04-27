#!/usr/bin/env bash
# Legacy `conduit build` smoke test.
#
# Mirrors the `smoke` job in .github/workflows/linux.yml: scaffolds a
# wildfire (db_and_auth) project via `conduit create --offline`, then
# runs `conduit build` and `conduit db generate` against it. This proves
# the existing mirror-based AOT pipeline still produces a binary while
# the build_runner migration is in flight.
#
# Caller is responsible for activating the conduit CLI and running
# `melos cache-source --no-select` before invoking this script — that's
# what fills the offline pub cache the `--offline` flag relies on.
#
# Required environment:
#   PUB_CACHE — points at a populated pub cache (set by .woodpecker.yml)
#   PATH       — must include $PUB_CACHE/bin
#
# Caller may override:
#   LEGACY_SMOKE_DIR — defaults to /tmp/legacy-smoke

set -euo pipefail

SMOKE_DIR="${LEGACY_SMOKE_DIR:-/tmp/legacy-smoke}"

echo "==> Legacy build smoke. Smoke dir: $SMOKE_DIR"

rm -rf "$SMOKE_DIR"
mkdir -p "$SMOKE_DIR"
cd "$SMOKE_DIR"

echo "==> conduit create -t db_and_auth --offline wildfire"
conduit create -t db_and_auth --offline wildfire

cd wildfire/

echo "==> conduit build"
conduit build

echo "==> conduit db generate"
conduit db generate

# `conduit build` writes the AOT executable to <projectRoot>/<package>.aot
# (see packages/cli/lib/src/commands/build.dart:49).
if [ ! -x wildfire.aot ]; then
  echo "FAIL: no executable produced. Project listing:"
  ls -la
  exit 1
fi

echo "==> Legacy smoke OK"
