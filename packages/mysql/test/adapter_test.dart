import 'dart:async';
import 'dart:io';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_mysql/conduit_mysql.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:test/test.dart';

import 'not_tests/mysql_test_config.dart';

void main() {
  group("Behavior", () {
    MySqlPersistentStore? persistentStore;

    tearDown(() async {
      await persistentStore?.close();
    });

    test("A down connection will restart", () async {
      persistentStore = MySqlTestConfig().persistentStore();
      var result = await persistentStore!.execute("select 1");
      expect(result, [
        {'1': 1}
      ]);

      await persistentStore!.close();

      result = await persistentStore!.execute("select 1");
      expect(result, [
        {'1': 1}
      ]);
    });

    test(
        "Ask for multiple connections at once, yield one successful connection",
        () async {
      persistentStore = MySqlTestConfig().persistentStore();
      final connections = await Future.wait(
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
            .map((_) => persistentStore!.getDatabaseConnectionPool()),
      );
      final first = connections.first;
      expect(connections, everyElement(first));
    });

    test("Make multiple requests at once, yield one successful connection",
        () async {
      persistentStore = MySqlTestConfig().persistentStore();
      final expectedValues = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      final values = await Future.wait(
        expectedValues.map((i) => persistentStore!.execute("select $i")),
      );

      expect(
        values,
        expectedValues
            .map(
              (v) => [
                {'$v': v}
              ],
            )
            .toList(),
      );
    });

    test("Make multiple requests at once, all fail because db connect fails",
        () async {
      persistentStore =
          MySqlTestConfig().persistentStore(dbName: 'xyzxyznotadb');

      final expectedValues = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      final values = await Future.wait(
        expectedValues.map(
          (i) => persistentStore!.execute("select $i").catchError((e) => e),
        ),
      );
      expect(values, everyElement(const TypeMatcher<QueryException>()));
    });

    test(
        "Make multiple requests at once, first few fails because db connect fails (but eventually succeeds)",
        () async {
      persistentStore = MySqlTestConfig().persistentStore(port: 15434);

      var expectedValues = [1, 2, 3, 4, 5];
      var values = await Future.wait(
        expectedValues.map(
          (i) => persistentStore!.execute("select $i").catchError((e) => e),
        ),
      );
      expect(values, everyElement(const TypeMatcher<QueryException>()));

      SocketProxy proxy =
          SocketProxy(15434, int.parse(Platform.environment['MYSQL_PORT']!));
      await proxy.open();

      expectedValues = [5, 6, 7, 8, 9];
      values = await Future.wait(
        expectedValues.map((i) => persistentStore!.execute("select $i")),
      );
      expect(
        values,
        expectedValues
            .map(
              (v) => [
                {'$v': v}
              ],
            )
            .toList(),
      );
      proxy.close();
    });

    test("Connect to bad db fails gracefully, can then be used again",
        () async {
      persistentStore = MySqlTestConfig().persistentStore(port: 15433);

      try {
        await persistentStore!.executeQuery("SELECT 1", {}, 20);
        expect(true, false);
      } on QueryException {
        //empty
      }

      SocketProxy proxy =
          SocketProxy(15433, int.parse(Platform.environment['MYSQL_PORT']!));
      await proxy.open();

      final x = await persistentStore!.executeQuery("SELECT 1", {}, 20);
      expect((x as ResultSet).rows.first.typedAssoc(), {'1': 1});
      proxy.close();
    });
  });
}

class SocketProxy {
  SocketProxy(this.src, this.dest);

  final int src;
  final int dest;

  bool isEnabled = true;

  ServerSocket? _server;
  final List<SocketPair> _pairs = [];

  Future open() async {
    _server = await ServerSocket.bind("0.0.0.0", src);
    _server!.listen((socket) async {
      final outgoing = await Socket.connect("0.0.0.0", dest);

      outgoing.listen((bytes) {
        if (isEnabled) {
          socket.add(bytes);
        }
      });

      socket.listen((bytes) {
        if (isEnabled) {
          outgoing.add(bytes);
        }
      });

      _pairs.add(SocketPair(socket, outgoing));
    });
  }

  Future close() async {
    isEnabled = false;
    await _server?.close();
    await Future.wait(
      _pairs.map((sp) async {
        await sp.src.close();
        await sp.dest.close();
      }),
    );
  }
}

class SocketPair {
  SocketPair(this.src, this.dest);

  final Socket src;
  final Socket dest;
}
