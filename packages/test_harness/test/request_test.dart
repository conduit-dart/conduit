import 'dart:convert';
import 'dart:io';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_test/conduit_test.dart';
import 'package:test/test.dart';
import 'package:test_core/src/util/io.dart';

void main() async {
  late MockHTTPServer server;
  late Agent agent;

  setUp(() async {
    server = await getUnusedPort(MockHTTPServer.new);
    agent = Agent.onPort(server.port);
    await server.open();
  });

  tearDown(() async {
    await server.close();
  });

  test("Body is encoded according to content-type, default is json", () async {
    final req = agent.request("/")..body = {"k": "v"};
    await req.post();

    final Request received = await server.next();
    expect(received.raw.headers.value("content-type"),
        "application/json; charset=utf-8");
    expect(received.body.as<Map>(), {"k": "v"});

    final req2 = agent.request("/")
      ..contentType = ContentType("text", "html", charset: "utf-8")
      ..body = "foobar";
    await req2.post();

    final Request rec2 = await server.next();
    expect(rec2.raw.headers.value("content-type"), "text/html; charset=utf-8");
    expect(rec2.body.as<String>(), "foobar");
  });

  test("If opting out of body encoding, bytes can be set directly on request",
      () async {
    final req = agent.request("/")
      ..encodeBody = false
      ..body = utf8.encode(json.encode({"k": "v"}));
    await req.post();

    final Request received = await server.next();
    expect(received.raw.headers.value("content-type"),
        "application/json; charset=utf-8");
    expect(received.body.as<Map>(), {"k": "v"});
  });

  test("Query parameters get URI encoded", () async {
    final req = agent.request("/")..query = {"k": "v v"};
    await req.get();

    final Request received = await server.next();
    expect(received.raw.uri.query, "k=v%20v");
  });

  test("List query parameters are encoded as separate keys", () async {
    final req = agent.request("/")
      ..query = {
        "k": ["v", "w"]
      };
    await req.get();

    final Request received = await server.next();
    expect(received.raw.uri.query, "k=v&k=w");
  });

  test("Headers get added to request", () async {
    final req = agent.request("/")
      ..headers["k"] = "v"
      ..headers["i"] = 2;
    await req.get();

    final Request received = await server.next();
    expect(received.raw.headers.value("k"), "v");
    expect(received.raw.headers.value("i"), "2");
  });

  test("Path and baseURL negotiate path delimeters", () async {
    var req = agent.request("/")
      ..baseURL = "http://localhost:${server.port}"
      ..path = "path";
    expect(req.requestURL, "http://localhost:${server.port}/path");

    req = agent.request("/")
      ..baseURL = "http://localhost:${server.port}/"
      ..path = "path";
    expect(req.requestURL, "http://localhost:${server.port}/path");

    req = agent.request("/")
      ..baseURL = "http://localhost:${server.port}/"
      ..path = "/path";
    expect(req.requestURL, "http://localhost:${server.port}/path");

    req = agent.request("/")
      ..baseURL = "http://localhost:${server.port}/base/"
      ..path = "path";
    expect(req.requestURL, "http://localhost:${server.port}/base/path");

    req = agent.request("/")
      ..baseURL = "http://localhost:${server.port}/base/"
      ..path = "/path";
    expect(req.requestURL, "http://localhost:${server.port}/base/path");
  });
}
