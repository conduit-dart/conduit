/// Mirror-free entrypoint for `package:conduit_config`.
///
/// Production AOT-compiled binaries should import this in place of
/// `package:conduit_config/conduit_config.dart`. The latter re-exports
/// the mirror-using `Configuration` compiler for dev/JIT mirror
/// discovery, which `dart compile exe` rejects.
library;

export 'package:conduit_config/src/configuration.dart';
export 'package:conduit_config/src/default_configurations.dart';
