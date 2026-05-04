/// Dev/JIT-only entrypoint for `package:conduit_config`.
///
/// Re-exports the mirror-based `Configuration` compiler. Production
/// AOT-compiled code should import
/// `package:conduit_config/conduit_config.dart` instead.
library;

export 'package:conduit_config/conduit_config.dart';
export 'package:conduit_config/src/compiler.dart';
