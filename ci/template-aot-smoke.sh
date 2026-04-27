#!/usr/bin/env bash
# End-to-end smoke for the `conduit create` template's AOT path.
#
# Goes through the same path a user would: scaffold a project from the
# `default` template, point its dependency overrides at the workspace,
# run build_runner, AOT-compile, start the binary, and curl /example.
# Failure here means a fresh `conduit create` project cannot ship as a
# self-contained `dart compile exe` binary — that's the whole point of
# the build_runner migration, so this is a deployable-state regression.
#
# Required environment:
#   PUB_CACHE / PATH — set by .woodpecker.yml so `conduit` is on PATH
#                      and the workspace pub cache is populated.
#
# Caller may override:
#   TEMPLATE_SMOKE_DIR — defaults to /tmp/template-aot-smoke
#   SMOKE_PORT         — port the binary will bind to (default 18888)

set -euo pipefail

WORKSPACE="${CI_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
SMOKE_DIR="${TEMPLATE_SMOKE_DIR:-/tmp/template-aot-smoke}"
SMOKE_PORT="${SMOKE_PORT:-18888}"

echo "==> Template AOT smoke. Workspace=$WORKSPACE smoke=$SMOKE_DIR port=$SMOKE_PORT"

rm -rf "$SMOKE_DIR"
mkdir -p "$SMOKE_DIR"
cd "$SMOKE_DIR"

echo "==> conduit create -t default --offline tmpl"
conduit create -t default --offline tmpl

cd tmpl/

# Repoint conduit_* deps at the workspace so we exercise the source
# under test, not whatever conduit_build_runner / conduit_core happens
# to be on pub.dev.
cat > pubspec_overrides.yaml <<EOF
dependency_overrides:
  conduit:
    path: $WORKSPACE/packages/cli
  conduit_codable:
    path: $WORKSPACE/packages/codable
  conduit_common:
    path: $WORKSPACE/packages/common
  conduit_config:
    path: $WORKSPACE/packages/config
  conduit_core:
    path: $WORKSPACE/packages/core
  conduit_isolate_exec:
    path: $WORKSPACE/packages/isolate_exec
  conduit_open_api:
    path: $WORKSPACE/packages/open_api
  conduit_password_hash:
    path: $WORKSPACE/packages/password_hash
  conduit_runtime:
    path: $WORKSPACE/packages/runtime
  conduit_test:
    path: $WORKSPACE/packages/test_harness
  conduit_build_runner:
    path: $WORKSPACE/packages/build_runner
EOF

# pub workspaces (in the conduit monorepo) ignore overrides files in
# nested packages, but this smoke runs *outside* the workspace —
# /tmp/template-aot-smoke/tmpl is its own root — so the overrides
# apply normally here.

echo "==> dart pub get"
dart pub get

echo "==> dart run build_runner build"
dart run build_runner build --delete-conflicting-outputs

echo "==> generated artifacts:"
ls -la lib/

if [ ! -f lib/conduit.g.dart ]; then
  echo "FAIL: lib/conduit.g.dart was not generated."
  exit 1
fi

echo "==> dart compile exe"
mkdir -p build
dart compile exe bin/main.dart -o build/server

echo "==> ./build/server -p $SMOKE_PORT &"
./build/server -p "$SMOKE_PORT" >/tmp/template-smoke.log 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

# Wait for the server to bind. dart-vm cold-start is fast in AOT (~50ms)
# but isolate setup can stretch to ~1s on contended runners.
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$SMOKE_PORT/example" >/tmp/template-smoke.body 2>/dev/null; then
    break
  fi
  sleep 0.5
done

if ! curl -fsS "http://127.0.0.1:$SMOKE_PORT/example" >/tmp/template-smoke.body 2>/dev/null; then
  echo "FAIL: /example did not respond. Server log:"
  cat /tmp/template-smoke.log
  exit 1
fi

body="$(cat /tmp/template-smoke.body)"
echo "==> /example body: $body"

# SimpleController returns {"key":"value"} — match without coupling to
# a specific JSON serialization order.
echo "$body" | grep -q '"key"' && echo "$body" | grep -q '"value"' \
  || { echo "FAIL: unexpected /example body: $body"; exit 1; }

echo "==> Template AOT smoke OK"
