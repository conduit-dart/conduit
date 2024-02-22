/// Testing utilities for Conduit applications
///
/// This library should be imported in test scripts. It should not be imported in application code.
///
/// Example:
///
/// import 'package:test/test.dart';
/// import 'package:conduit_core/conduit_core.dart';
/// import 'package:conduit_core/test.dart';
///
/// void main() {
///   test("...", () async => ...);
/// }
library conduit_test;

export 'package:conduit_test/src/agent.dart';
export 'package:conduit_test/src/auth_harness.dart';
export 'package:conduit_test/src/db_harness.dart';
export 'package:conduit_test/src/harness.dart';
export 'package:conduit_test/src/matchers.dart';
export 'package:conduit_test/src/mock_server.dart';
