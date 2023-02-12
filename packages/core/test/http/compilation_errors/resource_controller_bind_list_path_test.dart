import 'dart:async';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_runtime/runtime.dart';
import "package:test/test.dart";

void main() {
  test("Cannot bind dynamic to header", () {
    try {
      // ignore: unnecessary_statements
      RuntimeContext.current;
      fail('unreachable');
    } on StateError catch (e) {
      expect(
        e.toString(),
        contains("Invalid binding 'x' on 'ErrorListPath.get1'"),
      );
    }
  });
}

class ErrorListPath extends ResourceController {
  @Operation.get('id')
  Future<Response> get1(@Bind.path("id") List<String> x) async {
    return Response.ok(null);
  }
}
