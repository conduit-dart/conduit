#!/usr/bin/env bash
# AOT smoke test for the conduit_build_runner pipeline.
#
# Scaffolds a minimal channel-only Conduit app in /tmp, runs
# `dart run build_runner build` and `dart compile exe`, then runs the
# resulting binary and asserts that `bootstrap()` populated the runtime
# registry as expected.
#
# Failure of this script means the new AOT build path is broken — i.e.
# users following docs/AOT_WITHOUT_BUILD.md will not be able to ship a
# binary. See ci/README.md for what "deployable" means.
#
# Required environment:
#   PUB_CACHE — points at the workspace's pub cache (set by .woodpecker.yml)
#   PATH       — must include $PUB_CACHE/bin (set by .woodpecker.yml)
#
# Caller may override:
#   AOT_SMOKE_DIR — defaults to /tmp/aot-smoke (will be wiped clean each run)

set -euo pipefail

WORKSPACE="${CI_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
SMOKE_DIR="${AOT_SMOKE_DIR:-/tmp/aot-smoke}"

echo "==> AOT smoke against workspace: $WORKSPACE"
echo "==> Smoke app dir:               $SMOKE_DIR"

rm -rf "$SMOKE_DIR"
mkdir -p "$SMOKE_DIR/lib" "$SMOKE_DIR/bin"

cat > "$SMOKE_DIR/pubspec.yaml" <<EOF
name: aot_smoke
description: Disposable hello app for the conduit AOT smoke gate.
publish_to: none
version: 0.0.1

environment:
  sdk: ">=3.12.0-0 <4.0.0"

dependencies:
  conduit_core: ^6.0.0
  conduit_runtime: ^6.0.0

dev_dependencies:
  build_runner: ^2.14.1
  conduit_build_runner: ^6.0.0

dependency_overrides:
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
  conduit_build_runner:
    path: $WORKSPACE/packages/build_runner
EOF

cat > "$SMOKE_DIR/lib/aot_smoke_channel.dart" <<'EOF'
import 'package:conduit_core/aot.dart';

class SmokeChannel extends ApplicationChannel {
  @override
  Controller get entryPoint => Router();
}
EOF

cat > "$SMOKE_DIR/bin/main.dart" <<'EOF'
import 'package:aot_smoke/aot_smoke_channel.dart';
import 'package:aot_smoke/conduit.g.dart' as conduit_runtime;
import 'package:conduit_core/aot.dart';
import 'package:conduit_runtime/runtime.dart';

void main(List<String> args) {
  conduit_runtime.bootstrap();

  final ctx = RuntimeContext.current;
  final keys = ctx.runtimes.map.keys.toList();
  print('REGISTERED:${keys.join(',')}');

  final runtime = ctx[SmokeChannel];
  print('SMOKE_CHANNEL_RUNTIME:${runtime.runtimeType}');
}
EOF

cd "$SMOKE_DIR"

echo "==> dart pub get"
dart pub get

echo "==> dart run build_runner build"
dart run build_runner build --delete-conflicting-outputs

echo "==> generated files:"
ls -la lib/

echo "==> dart compile exe"
dart compile exe bin/main.dart -o bin/server

echo "==> ./bin/server"
out="$(./bin/server)"
echo "$out"

# Assertions — the binary must report SmokeChannel registered, and the
# runtime type must be the build_runner-emitted class. Anything else
# means bootstrap() didn't install the registry, or ChannelBuilder
# didn't see SmokeChannel, or the conditional-import fallback fired.
echo "$out" | grep -q '^REGISTERED:.*SmokeChannel' \
  || { echo "FAIL: SmokeChannel not registered"; exit 1; }
echo "$out" | grep -q '^SMOKE_CHANNEL_RUNTIME:\$SmokeChannelChannelRuntime' \
  || { echo "FAIL: runtime is not the generated \$SmokeChannelChannelRuntime"; exit 1; }

echo "==> AOT smoke OK"
