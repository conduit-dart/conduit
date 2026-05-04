/// Dev/JIT-only entrypoint for `package:conduit_core`.
///
/// Re-exports the mirror-based `ConduitCompiler` and friends. Production
/// AOT-compiled code should import `package:conduit_core/conduit_core.dart`
/// instead, which omits these.
library;

export 'package:conduit_core/conduit_core.dart';
export 'package:conduit_core/src/runtime/compiler.dart';
