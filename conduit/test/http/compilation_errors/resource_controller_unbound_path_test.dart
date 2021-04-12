import 'dart:async';
import "dart:core";

import 'package:conduit/conduit.dart';
import 'package:conduit_runtime/runtime.dart';
import "package:test/test.dart";

void main() {
  test("Ambiguous methods throws exception", () {
    try {
      // ignore: unnecessary_statements
      RuntimeContext.current;
      fail('unreachable');
      // ignore: avoid_catching_errors
    } on StateError catch (e) {
      expect(e.toString(), contains("Invalid controller"));
      expect(e.toString(), contains("'UnboundController'"));
      expect(e.toString(), contains("'getOne'"));
    }
  });
}

class UnboundController extends ResourceController {
  @Operation.get()
  Future<Response> getOne(@Bind.path("id") int id) async {
    return Response.ok(null);
  }
}
