import 'dart:async';
import 'dart:io';

import 'package:conduit/conduit.dart';
import 'package:conduit/src/dev/helpers.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

// Some CachePolicy fields are tested by file_controller_test.dart, this
// file tests the combinations not tested there.
void main() {
  HttpServer? server;

  tearDown(() async {
    await server?.close(force: true);
  });

  test("Prevent intermediate caching", () async {
    const policy = CachePolicy(preventIntermediateProxyCaching: true);
    server = await bindAndRespondWith(Response.ok("foo")..cachePolicy = policy);
    final result = await http.get(Uri.parse("http://localhost:8888/"));
    expect(result.headers["cache-control"], "private");
  });

  test("Prevent caching altogether", () async {
    const policy = CachePolicy(preventCaching: true);
    server = await bindAndRespondWith(Response.ok("foo")..cachePolicy = policy);
    final result = await http.get(Uri.parse("http://localhost:8888/"));
    expect(result.headers["cache-control"], "no-cache, no-store");
  });
}

Future<HttpServer> bindAndRespondWith(Response response) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
  server.map((req) => Request(req)).listen((req) async {
    final next = PassthruController();
    next.linkFunction((req) async {
      return response;
    });
    await next.receive(req);
  });

  return server;
}
