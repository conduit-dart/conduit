import 'dart:async';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_runtime/runtime.dart';
import 'package:test/test.dart';

void main() {
  test("Find default ApplicationChannel", () {
    expect(
      RuntimeContext.current.runtimes.iterable
          .whereType<ChannelRuntime>()
          .length,
      equals(1),
    );
    expect(
      RuntimeContext.current.runtimes.iterable
          .whereType<ChannelRuntime>()
          .first
          .channelType,
      equals(TestChannel),
    );
  });
}

class TestChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = Router();
    router.route("/controller/[:id]").link(() => FailingController());
    return router;
  }
}

class FailingController extends ResourceController {
  @Operation.get()
  Future<Response> get() async {
    return Response.ok(null);
  }
}
