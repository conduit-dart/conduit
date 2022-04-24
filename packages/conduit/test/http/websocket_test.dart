import 'dart:async';
import 'dart:convert';
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
      return await app.start(numberOfInstances: 1);
    });

    tearDownAll(() async {
      return await app.stop();
    });

    test("Send single message. Await broadcast incoming stream", () async {
      final url = Uri.parse('$urlPrefix/test');
      final socket = WebSocketChannel.connect(url);
      final incoming = socket.stream.asBroadcastStream();
      const msg = 'this message is transfered over WebSocket connection';
      socket.sink.add(msg);
      socket.sink.add('stop'); //the server will stop the connection

      //the TestChannel should respond with hash code of the message
      var response = await incoming.first;
      expect(response.toString(), msg.hashCode.toString());
      await socket.sink.done;
      expect(socket.closeReason, 'stop acknowledged');
    });

    test("Send stream of messages", () async {
      final url = Uri.parse('$urlPrefix/test');
      final socket = WebSocketChannel.connect(url);

      var i = 0;
      final stopHash = 'stop'.hashCode.toString();
      final messages = <String>[for (var x = 0; x < 100; ++x) 'message $x'];
      socket.stream.listen((rx) async {
        var hash = rx.toString();
        if (hash == stopHash) {
          await socket.sink.done;
        } else {
          expect(messages[i++].hashCode.toString(),
              rx.toString()); //check confirmation of each message
        }
      });

      messages.forEach(socket.sink.add);
      socket.sink.add('stop');

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
    await for (var message in socket) {
      await Future.delayed(const Duration(milliseconds: 5));
      socket.add('${message.hashCode}');
      if (message == 'stop') {
        break;
      }
    }
    await socket.close(WebSocketStatus.normalClosure, 'stop acknowledged');
    print('test controller closed the connection');
    return Future.value();
  }

  @Operation.get()
  Future<Response?> testMethod() {
    _stopwatch.start();
    final httpRequest = request!.raw;
    WebSocketTransformer.upgrade(httpRequest).then(_processConnection);
    return Future.value(
        null); //upgrade the HTTP connection to WebSocket by returning null
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

    return Future.value(
        null); //upgrade the HTTP connection to WebSocket by returning null
  }
}
