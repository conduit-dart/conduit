// ignore: unnecessary_const
@Timeout(const Duration(seconds: 90))
import 'dart:async';

import 'package:conduit/conduit.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group("Recovers", () {
    final app = Application<TestChannel>();

    tearDown(() async {
      // ignore: avoid_print
      print("stopping");
      await app.stop();
      // ignore: avoid_print
      print("stopped");
    });

    test("Application reports uncaught error, recovers", () async {
      final errorMsgCompleter = Completer<LogRecord>();
      app.logger.onRecord.listen((rec) {
        if (rec.message.contains("Uncaught exception")) {
          errorMsgCompleter.complete(rec);
        }
      });
      await app.start();

      // This request will generate an uncaught exception
      final failFuture =
          http.get(Uri.parse("http://localhost:8888/?crash=true"));

      // This request will come in right after the failure but should succeed
      final successFuture = http.get(Uri.parse("http://localhost:8888/"));

      // Ensure both requests respond with 200, since the failure occurs asynchronously AFTER the response has been generated
      // for the failure case.
      // ignore: avoid_print
      print("sent requests");
      final responses = await Future.wait([successFuture, failFuture]);
      // ignore: avoid_print
      print("got responses");
      expect(responses.first.statusCode, 200);
      expect(responses.last.statusCode, 200);

      final errorMessage = await errorMsgCompleter.future;
      // ignore: avoid_print
      print("got log message");
      expect(errorMessage.message, contains("Uncaught exception"));
      expect(errorMessage.error.toString(), contains("foo"));
      expect(errorMessage.stackTrace, isNotNull);

      // And then we should make sure everything is working just fine.
      expect((await http.get(Uri.parse("http://localhost:8888/"))).statusCode,
          200);
      // ignore: avoid_print
      print("succeeded in final request");
    });

    test("Application with multiple isolates reports uncaught error, recovers",
        () async {
      final contents = <String>[];
      int counter = 0;
      final completer = Completer();
      app.logger.onRecord.listen((rec) {
        // ignore: avoid_print
        print("got msg");
        contents.add(rec.message);
        counter++;
        if (counter == 5) {
          completer.complete();
        }
      });

      await app.start(numberOfInstances: 2);

      // Throw some deferred crashers then some success messages at the server
      final failFutures = Iterable.generate(5)
          .map((_) => http.get(Uri.parse("http://localhost:8888/?crash=true")));

      final successResponse =
          await http.get(Uri.parse("http://localhost:8888/"));
      expect(successResponse.statusCode, 200);
      expect((await Future.wait(failFutures)).map((r) => r.statusCode),
          everyElement(200));

      // ignore: avoid_print
      print("wait on completion");
      await completer.future;
      // ignore: avoid_print
      print("completed");
      expect(contents.where((c) => c.contains("Uncaught exception")).length, 5);
    });
  });
}

class TestChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = Router();
    router.route("/").link(() => UncaughtCrashController());
    return router;
  }
}

class UncaughtCrashController extends Controller {
  @override
  FutureOr<RequestOrResponse> handle(Request req) {
    if (req.raw.uri.queryParameters["crash"] == "true") {
      Future(() {
        dynamic x;

        /// force an npe to test the crash handler.
        x.foo();
      });
      return Response.ok(null);
    }

    return Response.ok(null);
  }
}
