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

    test("Send single message", () async {
      final url = Uri.parse('$urlPrefix/test');
      final socket = WebSocketChannel.connect(url);
      final incoming = socket.stream.asBroadcastStream();
      print('websocket extensions: ${socket.protocol}');
      const msg = 'this message is transfered over WebSocket connection';
      socket.sink.add(msg);
      socket.sink.add('stop');
      socket.sink.add('another');

      var response = await incoming
          .first; //the TestChannel should respond with hash code of the message
      expect(response.toString(), msg.hashCode.toString());
      //await socket.sink.close(WebSocketStatus.normalClosure, 'all is good');
      await Future.delayed(const Duration(seconds: 1));
      print('waiting for the socket to close');
//      await socket.sink.close(WebSocketStatus.normalClosure, 'all is good');
      await socket.sink.done;
      print('the socket closed with reason ${socket.closeReason}');
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
      await socket.sink.close(WebSocketStatus.normalClosure, 'all is good');
      await socket.sink.done;
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
      final farewell = await rxUser2.first;
      expect(farewell, 'bye');

      await user1.sink.done;
      print('close reason: ${user1.closeReason}');
      user2.sink.add('{"to" : "user1", "msg": "bye"}');
      await user2.sink.done;
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
  Future _processConnection(WebSocket socket) async {
    await for (var message in socket) {
      print('inocming message $message');
      socket.add('${message.hashCode}');
      if (message == 'stop') {
        break;
      }
    }
    await socket.close(WebSocketStatus.normalClosure, 'request to stop');
    print('test controller closed the connection');
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
      _socket[user]!.close(WebSocketStatus.normalClosure, 'bye');
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
