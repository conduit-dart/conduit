/// Mirror-free runtime surface used by AOT-compiled Conduit binaries.
///
/// This entrypoint is safe to import from `dart compile exe`-bound code:
/// it does not transitively import `dart:mirrors`. The legacy
/// mirror-based discovery, build pipeline, and `Compiler` machinery have
/// been moved to `package:conduit_runtime/dev.dart` and are only loaded
/// in JIT/dev workflows or by the still-supported `conduit build` CLI.
library;

export 'package:conduit_runtime/src/context.dart';
export 'package:conduit_runtime/src/exceptions.dart';
