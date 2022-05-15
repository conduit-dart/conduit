import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit/conduit.dart';
import 'package:conduit_test/conduit_test.dart';
import 'package:test/test.dart';
import 'package:test_core/src/util/io.dart';

void main() async {
  group("Agent instantiation", () {
    Application? app;

    tearDown(() async {
      await app?.stop();
    });

    test("Create from app, explicit port", () async {
      final port = await getUnusedPort((port) => port);

      app = Application<SomeChannel>()..options.port = port;
      await app!.startOnCurrentIsolate();
      final client = Agent(app);
      expect(client.baseURL, "http://localhost:$port");
    });

    test("Create from app, assigned port", () async {
      app = Application<SomeChannel>()..options.port = 0;
      await app!.startOnCurrentIsolate();

      final client = Agent(app);
      final response = await client.request("/").get();
      expect(response, hasStatus(200));
    });

    test("Create from unstarted app throws useful exception", () async {
      app = Application<SomeChannel>();
      final tc = Agent(app);
      try {
        await tc.request("/").get();
        expect(true, false);
      } on StateError catch (e) {
        expect(e.toString(), contains("Application under test is not running"));
      }
    });

    test("Create from unstarted app, start app, works OK", () async {
      app = Application<SomeChannel>()..options.port = 0;
      final tc = Agent(app);
      await app!.startOnCurrentIsolate();

      expectResponse(await tc.request("/").get(), 200);
    });

    test(
        "Create agent from another agent has same request URL, contentType and headers",
        () {
      final original = Agent.fromOptions(ApplicationOptions()
        ..port = 2121
        ..address = "foobar.com");
      original.headers["key"] = "value";
      original.contentType = ContentType.text;

      final clone = Agent.from(original);
      expect(clone.baseURL, original.baseURL);
      expect(clone.headers, original.headers);
      expect(clone.contentType, original.contentType);
    });
  });

  group("Request building", () {
    late MockHTTPServer server;
    setUp(() async {
      server = await getUnusedPort((port) => MockHTTPServer(port));
      await server.open();
    });

    tearDown(() async {
      await server.close();
    });

    test("Host created correctly", () async {
      final portLocal = await getUnusedPort((port) => port);
      final defaultTestClient = Agent.onPort(server.port);
      final portConfiguredClient =
          Agent.fromOptions(ApplicationOptions()..port = portLocal);
      final hostPortConfiguredClient = Agent.fromOptions(ApplicationOptions()
        ..port = portLocal
        ..address = "foobar.com");
      final hostPortSSLConfiguredClient = Agent.fromOptions(
          ApplicationOptions()
            ..port = portLocal
            ..address = "foobar.com",
          useHTTPS: true);
      expect(defaultTestClient.baseURL, "http://localhost:${server.port}");
      expect(portConfiguredClient.baseURL, "http://localhost:$portLocal");
      expect(hostPortConfiguredClient.baseURL, "http://localhost:$portLocal");
      expect(
          hostPortSSLConfiguredClient.baseURL, "https://localhost:$portLocal");
    });

    test("Request URLs are created correctly", () {
      final defaultTestClient = Agent.onPort(server.port);

      expect(defaultTestClient.request("/foo").requestURL,
          "http://localhost:${server.port}/foo");
      expect(defaultTestClient.request("foo").requestURL,
          "http://localhost:${server.port}/foo");
      expect(defaultTestClient.request("foo/bar").requestURL,
          "http://localhost:${server.port}/foo/bar");

      expect(
          (defaultTestClient.request("/foo")..query = {"baz": "bar"})
              .requestURL,
          "http://localhost:${server.port}/foo?baz=bar");
      expect((defaultTestClient.request("/foo")..query = {"baz": 2}).requestURL,
          "http://localhost:${server.port}/foo?baz=2");
      expect(
          (defaultTestClient.request("/foo")..query = {"baz": null}).requestURL,
          "http://localhost:${server.port}/foo?baz");
      expect(
          (defaultTestClient.request("/foo")..query = {"baz": true}).requestURL,
          "http://localhost:${server.port}/foo?baz");
      expect(
          (defaultTestClient.request("/foo")..query = {"baz": true, "boom": 7})
              .requestURL,
          "http://localhost:${server.port}/foo?baz&boom=7");
    });

    test("HTTP requests are issued", () async {
      final defaultTestClient = Agent.onPort(server.port);
      await defaultTestClient.request("/foo").get();
      Request msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "GET");

      await defaultTestClient.request("/foo").delete();
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "DELETE");

      expect(
          await defaultTestClient.post("/foo", body: {"foo": "bar"})
              is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "POST");
      expect(msg.body.as(), {"foo": "bar"});

      expect(
          await defaultTestClient.execute("PATCH", "/foo", body: {"foo": "bar"})
              is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "PATCH");
      expect(msg.body.as(), {"foo": "bar"});

      expect(
          await defaultTestClient.put("/foo", body: {"foo": "bar"})
              is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "PUT");
      expect(msg.body.as<Map<String, dynamic>>(), {"foo": "bar"});
    });

    test("Default headers are added to requests", () async {
      final defaultTestClient = Agent.onPort(server.port)
        ..headers["X-Int"] = 1
        ..headers["X-String"] = "1";

      await defaultTestClient.get("/foo");

      final Request msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.headers.value("x-int"), "1");
      expect(msg.raw.headers.value("x-string"), "1");
    });

    test("Default headers can be overridden", () async {
      final defaultTestClient = Agent.onPort(server.port)
        ..headers["X-Int"] = 1
        ..headers["X-String"] = "1";

      await (defaultTestClient.request("/foo")
            ..headers = {
              "X-Int": [1, 2]
            })
          .get();

      final Request msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.headers.value("x-int"), "1, 2");
    });

    test("Client can expect array of JSON", () async {
      final portLocal = await getUnusedPort((port) => port);
      final client = Agent.onPort(portLocal);
      final server = await HttpServer.bind("localhost", portLocal,
          v6Only: false, shared: false);
      final router = Router();
      router.route("/na").link(() => TestController());
      router.didAddToChannel();
      server.map((req) => Request(req)).listen(router.receive);

      final resp = await client.request("/na").get();
      expect(
          resp, hasResponse(200, body: everyElement({"id": greaterThan(0)})));

      await server.close(force: true);
    });

    test("Query parameters are provided when using execute", () async {
      final defaultTestClient = Agent.onPort(server.port);

      await defaultTestClient.get("/foo", query: {"k": "v"});

      final Request msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.uri.query, "k=v");
    });

    test("Basic authorization adds header to all requests", () async {
      final defaultTestClient = Agent.onPort(server.port)
        ..headers["k"] = "v"
        ..setBasicAuthorization("username", "password");

      await defaultTestClient.get("/foo");

      final Request msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.headers.value("k"), "v");
      expect(msg.raw.headers.value("authorization"),
          "Basic ${base64.encode("username:password".codeUnits)}");
    });

    test("Bearer authorization adds header to all requests", () async {
      final defaultTestClient = Agent.onPort(server.port)
        ..headers["k"] = "v"
        ..bearerAuthorization = "token";

      await defaultTestClient.get("/foo");

      final Request msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.headers.value("k"), "v");
      expect(msg.raw.headers.value("authorization"), "Bearer token");
    });
  });

  group("Response handling", () {
    late HttpServer server;

    tearDown(() async {
      await server.close(force: true);
    });

    test("Responses have body", () async {
      final portLocal = await getUnusedPort((port) => port);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, portLocal);
      server.listen((req) {
        final resReq = Request(req);
        resReq.respond(Response.ok([
          {"a": "b"}
        ]));
      });

      final defaultTestClient = Agent.onPort(portLocal);
      final response = await defaultTestClient.request("/foo").get();
      expect(response.body.as<List>().length, 1);
      expect(response.body.as<List>().first["a"], "b");
    });

    test("Responses with no body don't return one", () async {
      final portLocal = await getUnusedPort((port) => port);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, portLocal);
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.close();
      });

      final defaultTestClient = Agent.onPort(portLocal);
      final response = await defaultTestClient.request("/foo").get();
      expect(response.body.isEmpty, true);
    });

    test("Request with accept adds header", () async {
      final portLocal = await getUnusedPort((port) => port);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, portLocal);
      server.listen((req) {
        final resReq = Request(req);
        resReq.respond(Response.ok(
            {"ACCEPT": req.headers.value(HttpHeaders.acceptHeader)}));
      });

      final client = Agent.onPort(portLocal);
      final req = client.request("/foo")
        ..accept = [ContentType.json, ContentType.text];

      final response = await req.post();
      expect(response.body.as<Map<String, dynamic>>(), {
        "ACCEPT": "application/json; charset=utf-8,text/plain; charset=utf-8"
      });
    });
  });
}

class SomeChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final r = Router();
    r.route("/").linkFunction((r) async => Response.ok(null));
    return r;
  }
}

class TestController extends ResourceController {
  @Operation.get()
  Future<Response> get() async {
    return Response.ok([
      {"id": 1},
      {"id": 2}
    ]);
  }
}
