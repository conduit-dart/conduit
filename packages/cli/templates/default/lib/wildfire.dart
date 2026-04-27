/// wildfire
///
/// A conduit web server.
library wildfire;

export 'dart:async';
export 'dart:io';

// `aot.dart` is the lean entrypoint that does NOT pull `dart:mirrors`,
// so `dart compile exe` produces a working binary. The fat
// `package:conduit_core/conduit_core.dart` entrypoint (used by
// `package:conduit/dev.dart`) is still available for tooling that
// needs the legacy `Compiler` re-exports.
export 'package:conduit_core/aot.dart';

export 'channel.dart';
