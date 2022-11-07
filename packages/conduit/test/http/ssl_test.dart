import 'dart:async';
import 'dart:io';

import 'package:conduit/src/application/application.dart';
import 'package:conduit/src/http/http.dart';
import 'package:test/test.dart';

void main() {
  group("SSL", () {
    late Application app;

    setUp(() {
      final ciDirUri = getCIDirectoryUri();

      app = (Application<TestChannel>()
        ..options.certificateFilePath = ciDirUri
            .resolve("conduit.cert.pem")
            .toFilePath(windows: Platform.isWindows)
        ..options.privateKeyFilePath = ciDirUri
            .resolve("conduit.key.pem")
            .toFilePath(windows: Platform.isWindows));
    });

    tearDown(() async {
      return app.stop();
    });

    test("Start with HTTPS", () async {
      await app.start();
      final completer = Completer<List<int>>();
      final socket = await SecureSocket.connect(
        "localhost",
        8888,
        onBadCertificate: (_) => true,
      );
      const request =
          "GET /r HTTP/1.1\r\nConnection: close\r\nHost: localhost\r\n\r\n";
      socket.add(request.codeUnits);

      socket.listen(completer.complete);
      final httpResult = String.fromCharCodes(await completer.future);
      expect(httpResult, contains("200 OK"));
      await socket.close();
    });
  });
}

Uri getCIDirectoryUri() {
  final env = Platform.environment['CONDUIT_CI_DIR_LOCATION'];
  return env != null
      ? Uri.parse(env)
      : Directory.current.uri.resolve("../../").resolve("ci/");
}

class TestChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = Router();
    router.route("/r").linkFunction((r) async => Response.ok(null));
    return router;
  }
}
