import 'dart:async';
import 'dart:io';
import 'package:conduit/conduit.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  const port = 8888;
  const urlPrefix = 'ws://localhost:$port';

  group("Upgrade to WebSocket", () {
    var app = Application<TestChannel>();
    app.options.port = port;

    setUpAll(() async {
      return await app.startOnCurrentIsolate();
    });

    tearDownAll(() async {
      return await app.stop();
    });

    test("Send single message", () async {
      final url = Uri.parse('$urlPrefix/test');
      final socket = WebSocketChannel.connect(url);
      const msg = 'this message is transfered over WebSocket connection';
      socket.sink.add(msg);
      var response = await socket.stream
          .first; //the TestChannel should respond with hash code of the message
      expect(response.toString(), msg.hashCode.toString());
    });
  });
}

class TestChannel extends ApplicationChannel {
  late ManagedContext context;

  @override
  Future prepare() async {}

  @override
  Controller get entryPoint {
    final router = Router();
    router.route("/test").link(() => TestController());

    return router;
  }
}

class TestController extends ResourceController {
  Future _processConnection(WebSocket socket) {
    socket.listen((message) {
      socket.add('${message.hashCode}');
      socket.close(WebSocketStatus.normalClosure, 'request to stop');
    });
    return Future.value();
  }

  @Operation.get()
  Future<Response?> testMethod() {
    final httpRequest = request!.raw;
    WebSocketTransformer.upgrade(httpRequest).then(_processConnection);
    return Future.value(
        null); //upgrade the HTTP connection to WebSocket by returning null
  }
}
