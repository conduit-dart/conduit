import 'package:conduit_runtime/src/mirror_context.dart';

/// Provides the runtime registry entries used by the JIT/dev mirror
/// fallback (`MirrorContext`).
///
/// Each `package:conduit_*` package that contributes types to
/// `RuntimeContext` exports one concrete `Compiler` subclass; on
/// JIT startup, `MirrorContext` discovers them via `dart:mirrors` and
/// calls [compile] on each. Under AOT, this class is never reached —
/// the `package:conduit_build_runner`-emitted `bootstrap()` installs
/// the registry directly.
///
/// Historically this class also defined the `conduit build` deflection
/// hooks (`deflectPackage`, `getUrisToResolve`,
/// `didFinishPackageGeneration`). Those were removed when the
/// `conduit build` CLI was retired in favor of `dart run build_runner
/// build && dart compile exe`.
abstract class Compiler {
  /// Returns the runtime objects this compiler contributes to
  /// `RuntimeContext.runtimes`, keyed by class name. Called once at
  /// `MirrorContext._()` initialization.
  Map<String, Object> compile(MirrorContext context);
}
