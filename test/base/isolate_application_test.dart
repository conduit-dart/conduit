import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:io';

main() {
  group("Lifecycle", () {
    var app = new Application<TPipeline>();

    tearDownAll(() async {
      await app?.stop();
    });

    test("Application starts", () async {
      await app.start(numberOfInstances: 3);
      expect(app.supervisors.length, 3);
    });

    ////////////////////////////////////////////

    test("Application responds to request", () async {
      var response = await http.get("http://localhost:8080/t");
      expect(response.statusCode, 200);
    });

    test("Application properly routes request", () async {
      var tRequest = http.get("http://localhost:8080/t");
      var rRequest = http.get("http://localhost:8080/r");

      var tResponse = await tRequest;
      var rResponse = await rRequest;

      expect(tResponse.body, '"t_ok"');
      expect(rResponse.body, '"r_ok"');
    });

    test("Application handles a bunch of requests", () async {
      var reqs = [];
      var responses = [];
      for (int i = 0; i < 100; i++) {
        var req = http.get("http://localhost:8080/t");
        req.then((resp) {
          responses.add(resp);
        });
        reqs.add(req);
      }

      await Future.wait(reqs);

      expect(responses.any((http.Response resp) => resp.headers["server"] ==
          "aqueduct/1"), true);
      expect(responses.any((http.Response resp) => resp.headers["server"] ==
          "aqueduct/2"), true);
      expect(responses.any((http.Response resp) => resp.headers["server"] ==
          "aqueduct/3"), true);
    });

    test("Application stops", () async {
      await app.stop();

      var successful = false;
      try {
        var _ = await http.get("http://localhost:8080/t");
        successful = true;
      } catch (e) {
        expect(e, isNotNull);
      }
      expect(successful, false);

      await app.start(numberOfInstances: 3);
      var resp = await http.get("http://localhost:8080/t");
      expect(resp.statusCode, 200);
    });
  });

  group("Failures", () {
    test("Application start fails and logs appropriate message if pipeline doesn't open", () async {
      var crashingApp = new Application<CrashPipeline>();

      var succeeded = false;
      try {
        crashingApp.configuration.pipelineOptions = {"crashIn" : "constructor"};
        await crashingApp.start();
        succeeded = true;
      } catch (e) {
        expect(e.message, "TestException: constructor");
      }
      expect(succeeded, false);

      try {
        crashingApp.configuration.pipelineOptions = {"crashIn" : "addRoutes"};
        await crashingApp.start();
        succeeded = true;
      } catch (e) {
        expect(e.message, "TestException: addRoutes");
      }
      expect(succeeded, false);

      try {
        crashingApp.configuration.pipelineOptions = {"crashIn" : "willOpen"};
        await crashingApp.start();
        succeeded = true;
      } catch (e) {
        expect(e.message, "TestException: willOpen");
      }
      expect(succeeded, false);

      crashingApp.configuration.pipelineOptions = {"crashIn" : "dontCrash"};
      await crashingApp.start();
      var response = await http.get("http://localhost:8080/t");
      expect(response.statusCode, 200);
      await crashingApp.stop();
    });

    test("Application that fails to open because port is bound fails gracefully", () async {
      var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8080);
      server.listen((req) {

      });

      var conflictingApp = new Application<TPipeline>();
      conflictingApp.configuration.port = 8080;

      var successful = false;
      try {
        await conflictingApp.start();
        successful = true;
      } catch (e) {
        expect(e, new isInstanceOf<IsolateSupervisorException>());
      }
      expect(successful, false);

      await server.close(force: true);
      await conflictingApp.stop();
    });
  });
}

class TestException implements Exception {
  final String message;
  TestException(this.message);

  String toString() {
    return "TestException: $message";
  }
}

class CrashPipeline extends ApplicationPipeline {
  CrashPipeline(Map opts) : super(opts) {
    if (opts["crashIn"] == "constructor") {
      throw new TestException("constructor");
    }
  }

  void addRoutes() {
    if (options["crashIn"] == "addRoutes") {
      throw new TestException("addRoutes");
    }
    router.route("/t").next(() => new TController());
  }

  @override
  Future willOpen() async {
    if (options["crashIn"] == "willOpen") {
      throw new TestException("willOpen");
    }
  }
}

class TPipeline extends ApplicationPipeline {
  TPipeline(Map opts) : super(opts);

  void addRoutes() {
    router.route("/t").next(() => new TController());
    router.route("/r").next(() => new RController());
  }
}

class TController extends HTTPController {
  @httpGet
  Future<Response> getAll() async {
    return new Response.ok("t_ok");
  }
}

class RController extends HTTPController {
  @httpGet
  Future<Response> getAll() async {
    return new Response.ok("r_ok");
  }
}