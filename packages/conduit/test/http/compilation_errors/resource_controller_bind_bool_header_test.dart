// ignore_for_file: avoid_catching_errors

import 'dart:async';

import 'package:conduit/conduit.dart';
import 'package:conduit_runtime/runtime.dart';
import "package:test/test.dart";

void main() {
  test("Cannot bind bool to header", () {
    try {
      // ignore: unnecessary_statements
      RuntimeContext.current;
      fail('unreachable');
    } on StateError catch (e) {
      expect(
        e.toString(),
        // ignore: missing_whitespace_between_adjacent_strings
        "Bad state: Invalid binding 'x' on 'ErrorDefaultBool.get1':"
        "Parameter type does not implement static parse method.",
      );
    }
  });
}

class ErrorDefaultBool extends ResourceController {
  @Operation.get()
  // ignore: avoid_positional_boolean_parameters
  Future<Response> get1(@Bind.header("foo") bool x) async {
    return Response.ok(null);
  }
}
