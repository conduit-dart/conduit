/// Mirror-free entrypoint for `package:conduit_core`.
///
/// Production AOT-compiled binaries should import this in place of
/// `package:conduit_core/conduit_core.dart`. The latter re-exports the
/// mirror-using `ConduitCompiler` for dev/JIT mirror discovery, which
/// `dart compile exe` rejects on platforms without `dart:mirrors`.
///
/// Equivalent to `conduit_core.dart` minus the
/// `src/runtime/compiler.dart` re-export.
library;

export 'package:conduit_config/aot.dart';
export 'package:conduit_core/src/application/channel.dart';
export 'package:logging/logging.dart';

export 'package:conduit_core/src/application/application.dart';
export 'package:conduit_core/src/auth/auth.dart';
export 'package:conduit_core/src/db/db.dart';
export 'package:conduit_core/src/db/managed/relationship_type.dart';
export 'package:conduit_core/src/http/http.dart';
