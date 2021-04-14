import 'dart:async';
import 'dart:io';

import 'package:conduit/conduit.dart';
import 'package:test/test.dart';

void main() {
  group("SSL", () {
    late Application app;

    tearDown(() async {
      await app.stop();
    });

    test("Start with HTTPS", () async {
      var ciDirUri = getCIDirectoryUri();

      app = Application<TestChannel>()
        ..options.certificateFilePath = ciDirUri
            .resolve("conduit.cert.pem")
            .toFilePath(windows: Platform.isWindows)
        ..options.privateKeyFilePath = ciDirUri
            .resolve("conduit.key.pem")
            .toFilePath(windows: Platform.isWindows);

      await app.start(numberOfInstances: 1);

      var completer = Completer<List<int>>();
      var socket = await SecureSocket.connect("localhost", 8888,
          onBadCertificate: (_) => true);
      var request =
          "GET /r HTTP/1.1\r\nConnection: close\r\nHost: localhost\r\n\r\n";
      socket.add(request.codeUnits);

      socket.listen((bytes) => completer.complete(bytes));
      var httpResult = String.fromCharCodes(await completer.future);
      expect(httpResult, contains("200 OK"));
      await socket.close();
    });
  });
}

Uri getCIDirectoryUri() {
  final env = Platform.environment['CONDUIT_CI_DIR_LOCATION'];
  return env != null
      ? Uri.parse(env)
      : Directory.current.uri.resolve("../").resolve("ci/");
}

class TestChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = Router();
    router.route("/r").linkFunction((r) async => Response.ok(null));
    return router;
  }
}
