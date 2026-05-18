import 'dart:async';
import 'dart:io';

import 'package:conduit_core/conduit_core.dart';
import 'package:test_core/src/util/io.dart' show getUnsafeUnusedPort;

/// Builds an [Application], assigns it an OS-picked free port, and starts
/// it — retrying on EADDRINUSE.
///
/// Copied from `packages/core/test/_helpers/free_port.dart` (see #272).
/// This is intentionally test-private code that the per-package test
/// suites depend on; pre-G5 there's no shared `conduit_test_kit`
/// package, so copy-paste keeps each package's tests self-contained.
///
/// `getUnusedPort` from `package:test_core` has a built-in race window: it
/// binds a probe socket on port 0 to discover an unused port, closes the
/// socket, and returns the port number. Between the close and the actual
/// downstream `HttpServer.bind`, another process can grab the port. The
/// usual mitigation is to perform the real bind *inside* the `tryPort`
/// callback so a null return triggers a fresh port — but
/// `Application.start` rolls in isolate spawning + supervisor wiring,
/// which the simple null-retry contract doesn't model cleanly.
///
/// This helper handles the retry explicitly: each attempt builds a fresh
/// [Application] via [build], assigns a probed port, and calls `start`. If
/// `start` throws a [SocketException] with EADDRINUSE (errno 48 on macOS
/// or 98 on Linux), the failed app is stopped and the loop retries with a
/// new port. Other failures propagate.
Future<({Application<T> app, int port})>
    startWithFreePort<T extends ApplicationChannel>(
  Application<T> Function() build, {
  int numberOfInstances = 1,
  int maxAttempts = 10,
}) async {
  Object? lastError;
  StackTrace? lastStack;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final candidate = await getUnsafeUnusedPort();
    final app = build();
    app.options.port = candidate;
    try {
      await app.start(numberOfInstances: numberOfInstances);
      return (app: app, port: candidate);
    } on SocketException catch (e, st) {
      if (_isAddrInUse(e)) {
        await _safeStop(app);
        lastError = e;
        lastStack = st;
        continue;
      }
      await _safeStop(app);
      rethrow;
    } on ApplicationStartupException catch (e, st) {
      // Application.start wraps the underlying SocketException as
      // ApplicationStartupException for the multi-isolate path; sniff
      // the message to decide whether this is the same race.
      if (e.toString().contains('Failed to create server socket') &&
          e.toString().contains('Address already in use')) {
        await _safeStop(app);
        lastError = e;
        lastStack = st;
        continue;
      }
      await _safeStop(app);
      rethrow;
    }
  }
  throw StateError(
    'startWithFreePort: could not bind a free port after $maxAttempts '
    'attempts. Last error: $lastError\n$lastStack',
  );
}

bool _isAddrInUse(SocketException e) {
  final code = e.osError?.errorCode;
  return code == 48 || code == 98; // macOS / Linux
}

Future<void> _safeStop(Application<dynamic> app) async {
  try {
    await app.stop();
  } catch (_) {
    // Stop can fail if start did not get far enough to register
    // supervisors; ignore — the retry will build a fresh app.
  }
}
