import 'package:conduit_runtime/src/context.dart';
import 'package:conduit_runtime/src/mirror_context.dart' as mc;

/// JIT-mode fallback. Selected by the conditional import in
/// `context.dart` when `dart:mirrors` is available. Reading
/// [mc.instance] also self-registers the mirror context as the default
/// factory for any later `RuntimeContext.current` calls.
RuntimeContext resolveMirrorFallback() => mc.instance;
