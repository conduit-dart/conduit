// ignore_for_file: avoid_dynamic_calls

@Timeout(Duration(seconds: 120))
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  const port = 8888;
  const urlPrefix = 'ws://localhost:$port';

  group("Upgrade to WebSocket", () {
    final app = Application<TestChannel>();
    app.options.port = port;

    setUpAll(() async {
      return app.start();
    });

    tearDownAll(() async {
      return app.stop();
    });

    test("Single message, use broadcast stream", () async {
      final url = Uri.parse('$urlPrefix/test');
      final socket = WebSocketChannel.connect(url);
      final incoming = socket.stream.asBroadcastStream();
      const msg = 'this message is transfered over WebSocket connection';
      socket.sink.add(msg);
      socket.sink.add('stop'); //the server will stop the connection

      //the TestChannel should respond with hash code of the message
      final response = await incoming.first;
      expect(response.toString(), msg.hashCode.toString());
      //incoming is broadcast stream - still listenable after the await

      //wait for the server to close the connection. We will receive its status code
      await socket.sink.done;
      expect(socket.closeReason, 'stop acknowledged');
    });

    test("Send single message. Await single subscription stream", () async {
      final url = Uri.parse('$urlPrefix/test');
      final socket = WebSocketChannel.connect(url);
      const msg = 'this message is transfered over WebSocket connection';
      socket.sink.add(msg);

      //the TestChannel should respond with hash code of the message
      final response = await socket.stream.first;
      expect(response.toString(), msg.hashCode.toString());

      //the socket stream is now complete. We can't listen for events any more
      socket.sink.add('we can send another message');
      await Future.delayed(const Duration(milliseconds: 100));
      socket.sink.add('even more messages are being sent');
      //but there is no way that we receive data - we've already listened to the stream

      socket.sink.add('stop'); //the server will stop the connection
      //but we can't get that info. No status code is sent to us
      //if we try to wait for socket.sink.done notification from the server
      //we will block forever - no data from the server is available
      //close our side for cleanup
      await socket.sink.close();
    });

    test("Send stream of messages", () async {
      final url = Uri.parse('$urlPrefix/test');
      final socket = WebSocketChannel.connect(url);

      var i = 0;
      final stopHash = 'stop'.hashCode.toString();
      final messages = <String>[for (var x = 0; x < 50; ++x) 'message $x'];
      socket.stream.listen((rx) async {
        final hash = rx.toString();
        if (hash == stopHash) {
          await socket.sink.done;
        } else {
          expect(
            messages[i++].hashCode.toString(),
            rx.toString(),
          ); //check confirmation of each message
        }
      });

      messages.forEach(socket.sink.add);
      socket.sink.add('stop');

      //we didn't close the listening stream as in the await case
      //its OK to listen for server accepting the stop
      await socket.sink.done;
      expect(socket.closeReason, 'stop acknowledged');
    });

    test("chat", () async {
      final url1 = Uri.parse('$urlPrefix/chat?user=user1');
      final url2 = Uri.parse('$urlPrefix/chat?user=user2');
      final user1 = WebSocketChannel.connect(url1);
      final user2 = WebSocketChannel.connect(url2);
      final rxUser1 = user1.stream.asBroadcastStream();
      final rxUser2 = user2.stream.asBroadcastStream();

      const sentMsg1 = "hello user 2";
      const send1 = '{"to": "user2", "msg": "$sentMsg1"}';

      user1.sink.add(send1);
      final msg = await rxUser2.first;
      expect(msg, sentMsg1);

      const sentMsg2 = "hello user 1";
      const send2 = '{"to": "user1", "msg": "$sentMsg2"}';
      user2.sink.add(send2);
      final data = await rxUser1.first;
      expect(data, sentMsg2);

      user1.sink.add('{"to" : "user2", "msg": "bye"}');
      final lastMsg = await rxUser2.first;
      expect(lastMsg, 'bye');

      await user1.sink.done;
      expect(user1.closeReason, 'farewell user1');

      user2.sink.add('{"to" : "user1", "msg": "bye"}');
      await user2.sink.done;
      expect(user2.closeReason, 'farewell user2');
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
    router.route('/chat').link(() => ChatController());

    return router;
  }
}

class TestController extends ResourceController {
  final _stopwatch = Stopwatch();
  Future _processConnection(WebSocket socket) async {
    await for (final message in socket) {
      //await the response for more realistic async behaviour
      await Future.delayed(const Duration(milliseconds: 5));
      socket.add('${message.hashCode}');
      if (message == 'stop') {
        break;
      }
    }
    await socket.close(WebSocketStatus.normalClosure, 'stop acknowledged');
    return Future.value();
  }

  @Operation.get()
  Future<Response?> testMethod() {
    _stopwatch.start();
    final httpRequest = request!.raw;
    WebSocketTransformer.upgrade(httpRequest).then(_processConnection);
    return Future
        .value(); //upgrade the HTTP connection to WebSocket by returning null
  }
}

class ChatController extends ResourceController {
  static final _socket = <String, WebSocket>{};

  void handleEvent(String event, String user) {
    final json = jsonDecode(event);
    final to = json['to'] as String;
    final msg = json['msg'] as String;
    if (_socket.containsKey(to)) {
      _socket[to]!.add(msg);
    }
    if (msg == 'bye' && _socket.containsKey(user)) {
      _socket[user]!.close(WebSocketStatus.normalClosure, 'farewell $user');
      _socket.remove(user);
    }
  }

  @Operation.get()
  Future<Response?> newChat(@Bind.query('user') String user) async {
    final httpRequest = request!.raw;
    _socket[user] = await WebSocketTransformer.upgrade(httpRequest);
    _socket[user]!.listen((event) => handleEvent(event as String, user));

    return Future
        .value(); //upgrade the HTTP connection to WebSocket by returning null
  }
}
