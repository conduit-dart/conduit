import 'package:conduit_runtime/src/context.dart';

/// AOT-mode stub. Selected by the conditional import in
/// `context.dart` when `dart:mirrors` is unavailable
/// (`dart.library.mirrors == false`, i.e. `dart compile exe`).
RuntimeContext resolveMirrorFallback() {
  throw StateError(
    'No RuntimeContext installed. Call the build_runner-generated '
    "`bootstrap()` from `package:<your_app>/conduit.g.dart` at the top of "
    'main() before constructing Application<T>. (This binary was AOT-'
    'compiled, so the mirror-based fallback is not available.)',
  );
}
