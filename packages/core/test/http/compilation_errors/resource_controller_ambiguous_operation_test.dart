// ignore_for_file: avoid_catching_errors

import "dart:core";

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_runtime/runtime.dart';
import "package:test/test.dart";

void main() {
  test("Ambiguous methods throws exception", () {
    try {
      // ignore: unnecessary_statements
      RuntimeContext.current;
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(), contains("'get1'"));
      expect(e.toString(), contains("'get2'"));
      expect(e.toString(), contains("'AmbiguousController'"));
    }
  });
}

class AmbiguousController extends ResourceController {
  @Operation.get("id")
  Future<Response> get1(@Bind.path("id") int id) async {
    return Response.ok(null);
  }

  @Operation.get("id")
  Future<Response> get2(@Bind.path("id") int id) async {
    return Response.ok(null);
  }
}
