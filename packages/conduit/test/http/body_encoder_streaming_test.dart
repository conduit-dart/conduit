// ignore_for_file: always_declare_return_types

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit/conduit.dart';
import 'package:conduit/src/dev/helpers.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

int port = 8886;

void main() {
  final defaultSize = RequestBody.maxSize;
  setUp(() {
    // Revert back to default before each test
    RequestBody.maxSize = defaultSize;
  });

  group("Unencoded list of bytes", () {
    late HttpServer server;

    tearDown(() async {
      await server.close(force: true);
    });

    test("Stream a list of bytes as a response", () async {
      final sc = StreamController<List<int>>();
      final response = Response.ok(sc.stream)
        ..contentType = ContentType("application", "octet-stream");
      server = await bindAndRespondWith(response);

      final resultFuture = http.get(Uri.parse("http://localhost:$port"));

      sc.add([1, 2, 3, 4]);
      sc.add([5, 6, 7, 8]);
      // ignore: unawaited_futures
      sc.close();

      final result = await resultFuture;
      expect(result.bodyBytes, [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(result.headers["transfer-encoding"], "chunked");
    });

    test("Stream of list of bytes encounters error", () async {
      final sc = StreamController<List<int>>();
      final response = Response.ok(sc.stream)
        ..contentType = ContentType("application", "octet-stream");
      server = await bindAndRespondWith(response);

      final request = await HttpClient().get("localhost", port, "/");
      final resultFuture = request.close();

      sc.add([1, 2, 3, 4]);
      sc.add([5, 6, 7, 8]);
      sc.addError(Exception("Whatever"));
      // ignore: unawaited_futures
      sc.close();

      final resp = await resultFuture;
      try {
        await resp.toList();
        expect(true, false);
      } on HttpException catch (e) {
        expect(
          e.toString(),
          contains("Connection closed while receiving data"),
        );
      }

      expect(serverHasNoMoreConnections(server), completes);
    });

    test("Stream a list of bytes with incorrect content type returns 500",
        () async {
      CodecRegistry.defaultInstance
          .add(ContentType("application", "silly"), const Utf8Codec());

      final sc = StreamController<List<int>>();
      final response = Response.ok(sc.stream)
        ..contentType = ContentType("application", "silly");
      server = await bindAndRespondWith(response);

      final resultFuture = http.get(Uri.parse("http://localhost:$port"));

      sc.add([1, 2, 3, 4]);
      sc.add([5, 6, 7, 8]);
      // ignore: unawaited_futures
      sc.close();

      // The test fails for a different reason in checked vs. unchecked mode.
      // Tests run in checked mode, but coverage runs in unchecked mode.
      try {
        final result = await resultFuture;
        expect(result.statusCode, 500);
        expect(result.bodyBytes, []);
      } on http.ClientException catch (_) {}
    });
  });

  group("Streaming codec", () {
    late HttpServer server;

    tearDown(() async {
      await server.close(force: true);
    });

    test("Stream a string as a response (which uses a codec)", () async {
      final sc = StreamController<String>();
      final response = Response.ok(sc.stream)
        ..contentType = ContentType("text", "plain", charset: "utf-8");
      server = await bindAndRespondWith(response);

      final resultFuture = http.get(Uri.parse("http://localhost:$port"));

      sc.add("abcd");
      sc.add("efgh");
      // ignore: unawaited_futures
      sc.close();

      final result = await resultFuture;
      expect(result.body, "abcdefgh");
      expect(result.headers["transfer-encoding"], "chunked");
    });

    test("Crash in encoder terminates connection", () async {
      CodecRegistry.defaultInstance
          .add(ContentType("application", "crash"), CrashingCodec());

      final sc = StreamController<String>();
      final response = Response.ok(sc.stream)
        ..contentType = ContentType("application", "crash");
      server = await bindAndRespondWith(response);

      final request = await HttpClient().get("localhost", port, "/");
      final resultFuture = request.close();

      sc.add("abcd");
      sc.add("efgh");
      // ignore: unawaited_futures
      sc.close();

      try {
        final resp = await resultFuture;
        await resp.toList();
        expect(true, false);
      } on HttpException catch (e) {
        expect(
          e.toString(),
          contains("Connection closed while receiving data"),
        );
      }

      expect(serverHasNoMoreConnections(server), completes);
    });
  });

  group("Compression", () {
    late HttpServer server;
    late HttpClient client;

    setUp(() async {
      client = HttpClient();
    });

    tearDown(() async {
      await server.close();
      client.close(force: true);
    });

    test(
        "Content-Type that can be gzipped but request does not have Accept-Encoding not gzipped",
        () async {
      final sc = StreamController<String>();
      server = await bindAndRespondWith(
        Response.ok(sc.stream)..contentType = ContentType.text,
      );

      final req = await client.getUrl(Uri.parse("http://localhost:$port"));
      req.headers.clear();

      final respFuture = req.close();

      sc.add("abcd");
      sc.add("efgh");
      // ignore: unawaited_futures
      sc.close();

      final resp = await respFuture;

      expect(
        resp.headers.contentType.toString(),
        equals(ContentType.text.toString()),
      );
      expect(resp.headers.value("content-encoding"), isNull);
      expect(resp.headers.value("transfer-encoding"), "chunked");
      expect(resp.headers.value("content-length"), isNull);

      expect(resp.statusCode, 200);
      final allBody = (await resp.toList()).expand((i) => i).toList();
      expect(utf8.decode(allBody), "abcdefgh");
    });

    test(
        "Content-Type that can be gzipped and request has Accept-Encoding but not gzip doesn't get gzipped",
        () async {
      final sc = StreamController<String>();
      server = await bindAndRespondWith(
        Response.ok(sc.stream)..contentType = ContentType.text,
      );

      final req = await client.getUrl(Uri.parse("http://localhost:$port"));
      req.headers.clear();
      req.headers.add("accept-encoding", "deflate");
      final respFuture = req.close();

      sc.add("abcd");
      sc.add("efgh");
      // ignore: unawaited_futures
      sc.close();

      final resp = await respFuture;

      expect(
        resp.headers.contentType.toString(),
        equals(ContentType.text.toString()),
      );
      expect(resp.headers.value("content-encoding"), isNull);
      expect(resp.headers.value("transfer-encoding"), "chunked");
      expect(resp.headers.value("content-length"), isNull);

      expect(resp.statusCode, 200);
      final allBody = (await resp.toList()).expand((i) => i).toList();
      expect(utf8.decode(allBody), "abcdefgh");
    });

    test("Unregistered content-type of Stream<List<int>> does not get gzipped",
        () async {
      final sc = StreamController<List<int>>();
      final ct = ContentType("application", "1");
      server =
          await bindAndRespondWith(Response.ok(sc.stream)..contentType = ct);
      final req = await client.getUrl(Uri.parse("http://localhost:$port"));
      req.headers.clear();
      req.headers.add("accept-encoding", "gzip");
      final respFuture = req.close();

      sc.add([1, 2, 3, 4]);
      // ignore: unawaited_futures
      sc.close();

      final resp = await respFuture;

      expect(resp.headers.contentType.toString(), ct.toString());
      expect(resp.headers.value("content-encoding"), isNull);

      expect(resp.statusCode, 200);
      expect(await resp.first, [1, 2, 3, 4]);
    });

    test(
        "Content-type that can't be gzipped and Accept-Encoding accepts gzip, not gzipped",
        () async {
      final sc = StreamController<String>();
      final ct = ContentType("application", "3");
      CodecRegistry.defaultInstance
          .add(ct, const Utf8Codec(), allowCompression: false);
      server =
          await bindAndRespondWith(Response.ok(sc.stream)..contentType = ct);
      final req = await client.getUrl(Uri.parse("http://localhost:$port"));
      req.headers.clear();
      req.headers.add("accept-encoding", "gzip");
      final respFuture = req.close();

      sc.add("abcd");
      // ignore: unawaited_futures
      sc.close();

      final resp = await respFuture;

      expect(resp.headers.contentType.toString(), ct.toString());
      expect(resp.headers.value("content-encoding"), isNull);

      expect(resp.statusCode, 200);
      expect(utf8.decode(await resp.first), "abcd");
    });
  });

  group("Client cancellation", () {
    late HttpServer server;

    tearDown(() async {
      await server.close(force: true);
    });

    test("Client request is cancelled during stream cleans up appropriately",
        () async {
      final sc = StreamController<List<int>>();
      final response = Response.ok(sc.stream)
        ..contentType = ContentType("application", "octet-stream");
      final initiateResponseCompleter = Completer();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      server.map((req) => Request(req)).listen((req) async {
        final next = PassthruController();
        next.linkFunction((req) async {
          initiateResponseCompleter.complete();
          return response;
        });
        await next.receive(req);
      });

      final socket = await Socket.connect("localhost", port);
      const request =
          "GET /r HTTP/1.1\r\nConnection: keep-alive\r\nHost: localhost\r\n\r\n";
      socket.add(request.codeUnits);

      await initiateResponseCompleter.future;

      sc.add([1, 2, 3, 4]);
      expect(server.connectionsInfo().active, 1);

      await socket.close();
      socket.destroy();
      await sc.close();

      expect(serverHasNoMoreConnections(server), completes);
    });
  });

  // This group only gets ran when not on windows, because there is some issue
  // that doesn't allow it to complete. The error occurs on client.postUrl
  // and the error message is: SocketException: Write failed (OS Error: An existing connection was forcibly closed by the remote host.
  // 3317  , errno = 10054)
  entityTooLarge() {
    late HttpServer server;
    late HttpClient client;

    setUp(() async {
      client = HttpClient();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8123);
      server.idleTimeout = const Duration(seconds: 1);
    });

    tearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });

    /*
      There is a different set of expectations when running on macOS.
      On macOS, when the client request is sending data and the server decides to terminate the connection,
      the client will get a 'EPROTOTYPE' socket error (most of the time). This occurs when the client tries
      to send data while the socket is in the process of being torn down. Since the server will kill the
      socket when it realizes too much data is being sent, the client throws an exception and doesn't
      get back the response.
     */

    test(
        "Entity with known content-type that is too large is rejected, chunked",
        () async {
      Controller.letUncaughtExceptionsEscape = true;
      RequestBody.maxSize = 8193;

      final controller = PassthruController()
        ..linkFunction((req) async {
          final body = await req.body.decode<Map<String, dynamic>>();
          return Response.ok(body);
        });
      server.listen((req) {
        controller.receive(Request(req));
      });

      var req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(
        HttpHeaders.contentTypeHeader,
        "application/json; charset=utf-8",
      );
      var body = {"key": List.generate(8192 * 50, (_) => "a").join(" ")};
      req.add(utf8.encode(json.encode(body)));

      try {
        final response = await req.close();
        if (Platform.isMacOS) {
          fail("Should not complete on macOS, see comment above tests");
        } else {
          expect(response.statusCode, 413);
        }
      } on SocketException catch (_) {
        if (!Platform.isMacOS) {
          rethrow;
        }
      }

      await serverHasNoMoreConnections(server);

      // Make sure we can still send some more requests;
      req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(
        HttpHeaders.contentTypeHeader,
        "application/json; charset=utf-8",
      );
      body = {"key": "a"};
      req.add(utf8.encode(json.encode(body)));
      final response = await req.close();
      expect(json.decode(utf8.decode(await response.first)), {"key": "a"});
    });

    test(
        "Entity with unknown content-type that is too large is rejected, chunked",
        () async {
      RequestBody.maxSize = 8193;
      final controller = PassthruController()
        ..linkFunction((req) async {
          final body = await req.body.decode();
          return Response.ok(body)
            ..contentType = ContentType("application", "octet-stream");
        });
      server.listen((req) {
        controller.receive(Request(req));
      });

      var req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers
          .add(HttpHeaders.contentTypeHeader, "application/octet-stream");
      req.add(List.generate(8192 * 100, (_) => 1));

      try {
        final response = await req.close();
        if (Platform.isMacOS) {
          fail("Should not complete on macOS, see comment above tests");
        } else {
          expect(response.statusCode, 413);
        }
      } on SocketException {
        if (!Platform.isMacOS) {
          rethrow;
        }
      }

      expect(serverHasNoMoreConnections(server), completes);

      // Make sure we can still send some more requests;
      req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers
          .add(HttpHeaders.contentTypeHeader, "application/octet-stream");
      req.add([1, 2, 3, 4]);
      final response = await req.close();
      expect(await response.toList(), [
        [1, 2, 3, 4]
      ]);
    });
  }

  if (!Platform.isWindows) {
    group("Entity too large", entityTooLarge);
  }
}

Future serverHasNoMoreConnections(HttpServer server) async {
  if (server.connectionsInfo().total == 0) {
    return null;
  }

  await Future.delayed(const Duration(milliseconds: 100));

  return serverHasNoMoreConnections(server);
}

Future<HttpServer> bindAndRespondWith(Response response) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  server.map((req) => Request(req)).listen((req) async {
    final next = PassthruController();
    next.linkFunction((req) async {
      return response;
    });
    await next.receive(req);
  });

  return server;
}

class CrashingCodec extends Codec<String, List<int>> {
  @override
  CrashingEncoder get encoder => CrashingEncoder();
  @override
  Converter<List<int>, String> get decoder =>
      EmptyConverter<List<int>, String>() as Converter<List<int>, String>;
}

class EmptyConverter<T, U> extends Converter {
  @override
  // ignore: type_annotate_public_apis
  T? convert(input) {
    return null;
  }
}

class CrashingEncoder extends Converter<String, List<int>> {
  @override
  List<int> convert(String val) => [];

  @override
  CrashingSink startChunkedConversion(Sink<List<int>> sink) {
    return CrashingSink(sink);
  }
}

class CrashingSink extends ChunkedConversionSink<String> {
  CrashingSink(this.sink);

  Sink<List<int>> sink;
  int count = 0;
  @override
  void add(String chunk) {
    count += chunk.length;
    if (count > 4) {
      throw Exception("uhoh");
    }
    sink.add([1]);
  }

  @override
  void close() {}
}
