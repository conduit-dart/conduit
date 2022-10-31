// ignore: unnecessary_const
// ignore_for_file: avoid_print, avoid_dynamic_calls

@Timeout(Duration(seconds: 120))
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit/conduit.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group("Lifecycle", () {
    late Application<TestChannel> app;

    setUp(() async {
      app = Application<TestChannel>();
      await app.start(numberOfInstances: 2, consoleLogging: true);
      print("started");
    });

    tearDown(() async {
      print("stopping");
      await app.stop();
      print("stopped");
    });

    test("Application starts", () async {
      expect(app.supervisors.length, 2);
    });

    test("Application responds to request", () async {
      final response = await http.get(Uri.parse("http://localhost:8888/t"));
      expect(response.statusCode, 200);
    });

    test("Application properly routes request", () async {
      final tRequest = http.get(Uri.parse("http://localhost:8888/t"));
      final rRequest = http.get(Uri.parse("http://localhost:8888/r"));

      final tResponse = await tRequest;
      final rResponse = await rRequest;

      expect(tResponse.body, '"t_ok"');
      expect(rResponse.body, '"r_ok"');
    });

    test("Application handles a bunch of requests", () async {
      final reqs = <Future>[];
      final responses = <http.Response>[];
      for (int i = 0; i < 20; i++) {
        final req = http.get(Uri.parse("http://localhost:8888/t"));
        // ignore: unawaited_futures
        req.then(responses.add);
        reqs.add(req);
      }

      await Future.wait(reqs);

      expect(
        responses.any(
          (http.Response resp) => resp.headers["server"] == "conduit/1",
        ),
        true,
      );
      expect(
        responses.any(
          (http.Response resp) => resp.headers["server"] == "conduit/2",
        ),
        true,
      );
    });

    test("Application stops", () async {
      await app.stop();

      try {
        await http.get(Uri.parse("http://localhost:8888/t"));
        // ignore: empty_catches
      } on SocketException {}

      await app.start(numberOfInstances: 2, consoleLogging: true);

      final resp = await http.get(Uri.parse("http://localhost:8888/t"));
      expect(resp.statusCode, 200);
    });

    test(
        "Application runs app startup function once, regardless of isolate count",
        () async {
      var sum = 0;
      for (var i = 0; i < 10; i++) {
        final result =
            await http.get(Uri.parse("http://localhost:8888/startup"));
        sum += int.parse(json.decode(result.body) as String);
      }
      expect(sum, 10);
    });
  });

  group("App launch status", () {
    late Application<TestChannel> app;

    tearDown(() async {
      await app.stop();
    });

    test(
        "didFinishLaunching is false before launch, true after, false after stop",
        () async {
      app = Application<TestChannel>();
      expect(app.isRunning, false);

      final future = app.start(numberOfInstances: 2, consoleLogging: true);
      expect(app.isRunning, false);
      await future;
      expect(app.isRunning, true);

      await app.stop();
      expect(app.isRunning, false);
    });
  });
}

class TestChannel extends ApplicationChannel {
  static Future initializeApplication(ApplicationOptions config) async {
    final v = config.context["startup"] as List<int>? ?? [];
    v.add(1);
    config.context["startup"] = v;
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router.route("/t").linkFunction((req) async => Response.ok("t_ok"));
    router.route("/r").linkFunction((req) async => Response.ok("r_ok"));
    router.route("startup").linkFunction((r) async {
      final total = options!.context["startup"].fold(0, (a, b) => a + b);
      return Response.ok("$total");
    });
    return router;
  }
}
