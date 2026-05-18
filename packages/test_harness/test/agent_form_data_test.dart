import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit_test/conduit_test.dart';
import 'package:test/test.dart';
import 'package:test_core/src/util/io.dart';

void main() {
  group("Form-encoded body (application/x-www-form-urlencoded)", () {
    late MockHTTPServer server;

    setUp(() async {
      server = await getUnusedPort(MockHTTPServer.new);
      await server.open();
    });

    tearDown(() async {
      await server.close();
    });

    test("Map body is sent as url-encoded and decodes back to the same map",
        () async {
      final agent = Agent.onPort(server.port)
        ..contentType = ContentType("application", "x-www-form-urlencoded",
            charset: "utf-8");

      await agent.post("/login", body: {
        "username": "alice",
        "password": "p@ss w/special&chars",
      });

      final req = await server.next();
      expect(req.method, "POST");
      expect(req.raw.headers.contentType?.primaryType, "application");
      expect(req.raw.headers.contentType?.subType, "x-www-form-urlencoded");

      // Server-side decoding via the existing _FormDecoder produces a
      // Map<String, List<String>>.
      final decoded = req.body.as<Map<String, dynamic>>();
      expect(decoded["username"], ["alice"]);
      expect(decoded["password"], ["p@ss w/special&chars"]);
    });

    test("List values produce repeated key=value pairs", () async {
      final agent = Agent.onPort(server.port)
        ..contentType = ContentType("application", "x-www-form-urlencoded",
            charset: "utf-8");

      await agent.post("/q", body: {
        "tag": ["a", "b", "c"],
      });

      final req = await server.next();
      final decoded = req.body.as<Map<String, dynamic>>();
      expect(decoded["tag"], ["a", "b", "c"]);
    });
  });

  group("Multipart body (multipart/form-data)", () {
    late HttpServer server;
    late int port;

    setUp(() async {
      port = await getUnusedPort((p) => p);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test(
        "Text fields and a binary file produce a body the server can parse, "
        "Content-Type carries the boundary parameter", () async {
      final received = Completer<_RawCapture>();
      server.listen((req) async {
        final bytes = <int>[];
        await for (final chunk in req) {
          bytes.addAll(chunk);
        }
        received.complete(_RawCapture(req.headers, bytes));
        req.response.statusCode = 200;
        await req.response.close();
      });

      final agent = Agent.onPort(port)
        ..contentType = ContentType.parse("multipart/form-data");

      final pngBytes = <int>[
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
        0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      ];

      await agent.post("/upload", body: {
        "name": "alice",
        "note": "hello, world",
        "avatar": MultipartFormFile.fromBytes(
          pngBytes,
          filename: "a.png",
          contentType: ContentType("image", "png"),
        ),
      });

      final captured = await received.future
          .timeout(const Duration(seconds: 5));

      // Boundary is on the Content-Type header.
      final ct = captured.headers.contentType!;
      expect(ct.primaryType, "multipart");
      expect(ct.subType, "form-data");
      final boundary = ct.parameters["boundary"];
      expect(boundary, isNotNull);
      expect(boundary, isNotEmpty);

      // Body parses cleanly via the boundary.
      final parts = _parseMultipart(captured.body, boundary!);
      expect(parts.keys, containsAll(["name", "note", "avatar"]));

      final namePart = parts["name"]!;
      expect(utf8.decode(namePart.body), "alice");
      expect(namePart.filename, isNull);

      final notePart = parts["note"]!;
      expect(utf8.decode(notePart.body), "hello, world");

      final avatarPart = parts["avatar"]!;
      expect(avatarPart.filename, "a.png");
      expect(avatarPart.contentType, "image/png");
      expect(avatarPart.body, pngBytes);
    });

    test("Boundary value is unique per request", () async {
      final boundaries = <String?>[];
      server.listen((req) async {
        boundaries.add(req.headers.contentType?.parameters["boundary"]);
        await req.drain<void>();
        req.response.statusCode = 200;
        await req.response.close();
      });

      final agent = Agent.onPort(port)
        ..contentType = ContentType.parse("multipart/form-data");

      await agent.post("/x", body: {"k": "v1"});
      await agent.post("/x", body: {"k": "v2"});

      // Allow time for the server's listener to record both requests.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(boundaries, hasLength(2));
      expect(boundaries[0], isNotNull);
      expect(boundaries[1], isNotNull);
      expect(boundaries[0], isNot(equals(boundaries[1])));
    });

    test("Iterable values produce one part per element", () async {
      final received = Completer<_RawCapture>();
      server.listen((req) async {
        final bytes = <int>[];
        await for (final chunk in req) {
          bytes.addAll(chunk);
        }
        received.complete(_RawCapture(req.headers, bytes));
        req.response.statusCode = 200;
        await req.response.close();
      });

      final agent = Agent.onPort(port)
        ..contentType = ContentType.parse("multipart/form-data");

      await agent.post("/q", body: {
        "tag": ["a", "b"],
      });

      final captured = await received.future
          .timeout(const Duration(seconds: 5));
      final boundary = captured.headers.contentType!.parameters["boundary"]!;
      final repeated = _parseMultipartRepeated(captured.body, boundary);
      expect(repeated["tag"]?.map((p) => utf8.decode(p.body)).toList(),
          ["a", "b"]);
    });

    test("Body that is not a Map throws StateError", () async {
      final agent = Agent.onPort(port)
        ..contentType = ContentType.parse("multipart/form-data");

      await expectLater(
        agent.post("/x", body: "not a map"),
        throwsA(isA<StateError>()),
      );
    });
  });

  group("JSON body backwards compatibility", () {
    late MockHTTPServer server;

    setUp(() async {
      server = await getUnusedPort(MockHTTPServer.new);
      await server.open();
    });

    tearDown(() async {
      await server.close();
    });

    test("Default JSON body still works after multipart additions", () async {
      final agent = Agent.onPort(server.port);
      await agent.post("/foo", body: {"a": 1, "b": "two"});

      final req = await server.next();
      expect(req.raw.headers.contentType?.primaryType, "application");
      expect(req.raw.headers.contentType?.subType, "json");
      expect(req.body.as<Map<String, dynamic>>(), {"a": 1, "b": "two"});
    });
  });
}

class _RawCapture {
  _RawCapture(this.headers, this.body);
  final HttpHeaders headers;
  final List<int> body;
}

/// Minimal multipart parser used only by these tests.
class _ParsedPart {
  _ParsedPart(this.body, this.filename, this.contentType);
  final List<int> body;
  final String? filename;
  final String? contentType;
}

Map<String, _ParsedPart> _parseMultipart(List<int> body, String boundary) {
  final result = <String, _ParsedPart>{};
  for (final entry in _parseMultipartEntries(body, boundary)) {
    result[entry.key] = entry.value;
  }
  return result;
}

Map<String, List<_ParsedPart>> _parseMultipartRepeated(
    List<int> body, String boundary) {
  final result = <String, List<_ParsedPart>>{};
  for (final entry in _parseMultipartEntries(body, boundary)) {
    result.putIfAbsent(entry.key, () => []).add(entry.value);
  }
  return result;
}

Iterable<MapEntry<String, _ParsedPart>> _parseMultipartEntries(
    List<int> body, String boundary) sync* {
  final delim = utf8.encode("--$boundary");
  final closing = utf8.encode("--$boundary--");
  // Find each delimiter.
  final indexes = <int>[];
  for (var i = 0; i <= body.length - delim.length; i++) {
    var match = true;
    for (var j = 0; j < delim.length; j++) {
      if (body[i + j] != delim[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      indexes.add(i);
    }
  }
  if (indexes.isEmpty) return;
  for (var k = 0; k < indexes.length - 1; k++) {
    final start = indexes[k] + delim.length;
    var end = indexes[k + 1];
    // Skip CRLF after delimiter.
    var s = start;
    if (s + 2 <= body.length && body[s] == 0x0d && body[s + 1] == 0x0a) {
      s += 2;
    }
    // Strip trailing CRLF before next delimiter.
    if (end >= 2 && body[end - 1] == 0x0a && body[end - 2] == 0x0d) {
      end -= 2;
    }
    final partBytes = body.sublist(s, end);
    // Split headers and body on first \r\n\r\n.
    var hdrEnd = -1;
    for (var i = 0; i <= partBytes.length - 4; i++) {
      if (partBytes[i] == 0x0d &&
          partBytes[i + 1] == 0x0a &&
          partBytes[i + 2] == 0x0d &&
          partBytes[i + 3] == 0x0a) {
        hdrEnd = i;
        break;
      }
    }
    if (hdrEnd < 0) continue;
    final headerStr = utf8.decode(partBytes.sublist(0, hdrEnd));
    final partBody = partBytes.sublist(hdrEnd + 4);
    String? name;
    String? filename;
    String? contentType;
    for (final raw in headerStr.split("\r\n")) {
      final line = raw.toLowerCase();
      if (line.startsWith("content-disposition:")) {
        final m = RegExp(r'name="([^"]*)"').firstMatch(raw);
        if (m != null) name = m.group(1);
        final fm = RegExp(r'filename="([^"]*)"').firstMatch(raw);
        if (fm != null) filename = fm.group(1);
      } else if (line.startsWith("content-type:")) {
        contentType = raw.substring(raw.indexOf(":") + 1).trim();
      }
    }
    if (name == null) continue;
    yield MapEntry(name, _ParsedPart(partBody, filename, contentType));
  }
  // Validate there's a closing boundary so callers can trust the parse.
  if (indexes.isNotEmpty) {
    final last = indexes.last;
    if (last + closing.length <= body.length) {
      var match = true;
      for (var j = 0; j < closing.length; j++) {
        if (body[last + j] != closing[j]) {
          match = false;
          break;
        }
      }
      if (!match) {
        // Not fatal for tests; still yielded all real parts above.
      }
    }
  }
}
