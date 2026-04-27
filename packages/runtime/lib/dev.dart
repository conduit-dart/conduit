/// Dev/JIT-only entrypoint for `package:conduit_runtime`.
///
/// Re-exports the mirror-based discovery surface that JIT-mode tooling
/// (tests, `conduit serve`, `conduit document`) relies on.
/// `dart compile exe` users should import
/// `package:conduit_runtime/runtime.dart` instead — that entrypoint
/// has no `dart:mirrors` in its import graph.
///
/// Dev/JIT users who want `RuntimeContext.current` to fall back to
/// `MirrorContext` automatically should call [enableMirrorFallback] once
/// at the top of `main()`. AOT users do not need this — the
/// build_runner-generated `bootstrap()` installs the runtime registry
/// directly.
library;

export 'package:conduit_runtime/runtime.dart';
export 'package:conduit_runtime/src/analyzer.dart';
export 'package:conduit_runtime/src/compiler.dart';
export 'package:conduit_runtime/src/mirror_coerce.dart';
export 'package:conduit_runtime/src/mirror_context.dart';

import 'package:conduit_runtime/src/context.dart';
import 'package:conduit_runtime/src/mirror_context.dart' as mc;

/// Wires the mirror-based `MirrorContext` as the default factory used by
/// `RuntimeContext.current`. Call once at the top of `main()` from
/// dev/JIT-mode code that doesn't go through the build_runner-generated
/// `bootstrap()`.
void enableMirrorFallback() {
  registerDefaultContextFactory(() => mc.instance);
}
