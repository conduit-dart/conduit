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
      socket.sink.add('stop');
      var response = await socket.stream
          .first; //the TestChannel should respond with hash code of the message
      expect(response.toString(), msg.hashCode.toString());
      exit(0);
    });

    test("Send stream of messages", () async {
      final url = Uri.parse('$urlPrefix/test');
      final socket = WebSocketChannel.connect(url);
      final messages = <String>[for (var x = 0; x < 100; ++x) 'message $x'];
      messages.forEach(socket.sink.add);
      socket.sink.add('stop');
      var i = 0;
      final stopHash = 'stop'.hashCode.toString();
      await for (var rx in socket.stream) {
        var hash = rx.toString();
        if (hash == stopHash) {
          break;
        }

        expect(messages[i++].hashCode.toString(),
            rx.toString()); //check confirmation of each message
      }
      exit(0);
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
  Future _processConnection(WebSocket socket) async {
    await for (var message in socket) {
      socket.add('${message.hashCode}');
      if (message == 'stop') {
        break;
      }
    }
    await socket.close(WebSocketStatus.normalClosure, 'request to stop');
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
