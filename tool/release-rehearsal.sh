#!/usr/bin/env bash
# Rehearse a workspace release against a self-hosted pub server instead of
# pub.dev, so you can verify the full publish + consume round-trip before
# tagging a real release. Works with any pub-compatible server (e.g. unpub,
# or any host that speaks the pub HTTP publishing API).
#
# Driven by `melos run release-rehearsal`.
#
# Posture
#   - Mutates every workspace package's pubspec.yaml to add a `publish_to:`
#     line pointing at your server.
#   - Always reverts on exit (trap), even on failure, so a Ctrl-C
#     mid-rehearsal does not leave dirty pubspecs.
#   - Aborts unless the working tree is clean — otherwise the trap
#     revert would clobber unrelated edits.
#   - Runs `dart pub publish` serially via `melos exec --concurrency 1`.
#     Order does not matter for the publish step itself (uploads are
#     independent); `--order-dependents` would trip the dev-only
#     conduit_core <-> conduit_test cycle for no benefit.
#
# Env
#   PUB_SERVER_URL  pub server URL to publish to, e.g. http://127.0.0.1:8080 (required)
#   PUB_TOKEN       bearer token for that server (required)

set -euo pipefail

PUB_SERVER_URL="${PUB_SERVER_URL:-}"

if [ -z "$PUB_SERVER_URL" ]; then
  echo "release-rehearsal: PUB_SERVER_URL is required." >&2
  echo "                   Point it at your self-hosted pub server, e.g." >&2
  echo "                   PUB_SERVER_URL=http://127.0.0.1:8080" >&2
  exit 1
fi

if [ -z "${PUB_TOKEN:-}" ]; then
  echo "release-rehearsal: PUB_TOKEN is required (bearer token for PUB_SERVER_URL)." >&2
  exit 1
fi

if [ -n "$(git status --porcelain packages/*/pubspec.yaml 2>/dev/null)" ]; then
  echo "release-rehearsal: packages/*/pubspec.yaml has uncommitted edits." >&2
  echo "                   The trap revert would clobber them; commit or stash first." >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Pre-flight: ensure dart pub knows the token for PUB_SERVER_URL. Idempotent.
dart pub token add "$PUB_SERVER_URL" --env-var PUB_TOKEN >/dev/null

revert_pubspecs() {
  echo "release-rehearsal: reverting publish_to: edits in packages/*/pubspec.yaml"
  git checkout -- packages/*/pubspec.yaml
}
trap revert_pubspecs EXIT

echo "release-rehearsal: patching publish_to: $PUB_SERVER_URL into every non-private pubspec"
for f in packages/*/pubspec.yaml; do
  # Skip packages marked `publish_to: none` (private) — they aren't
  # published in the real publish.yml flow either (`--no-private`).
  if grep -q "^publish_to: *none" "$f"; then
    continue
  fi
  # Skip synthetic test-fixture pubspecs that are never published.
  case "$f" in *isolate_exec_test_packages*) continue;; esac
  # Insert `publish_to: $PUB_SERVER_URL` immediately after the `name:` line
  # — keeps the field near the top where pub conventionally expects it.
  awk -v url="$PUB_SERVER_URL" '
    /^name:/ { print; print "publish_to: " url; next }
    { print }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

echo "release-rehearsal: publishing every workspace package (alphabetical, serial)"
melos exec --concurrency 1 --no-private -- \
  'dart pub publish --force'

echo "release-rehearsal: done. Packages published to $PUB_SERVER_URL"
echo "release-rehearsal: consume side — set PUB_HOSTED_URL=$PUB_SERVER_URL in a fresh scaffold."
