import 'dart:async';
import 'dart:io';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_postgresql/conduit_postgresql.dart';
import 'package:test/test.dart';

import 'not_tests/postgres_test_config.dart';

void main() {
  group("Behavior", () {
    PostgreSQLPersistentStore? persistentStore;
    SocketProxy? proxy;

    tearDown(() async {
      await persistentStore?.close();
      await proxy?.close();
    });

    test("A down connection will restart", () async {
      persistentStore = PostgresTestConfig().persistentStore();
      var result = await persistentStore!.execute("select 1");
      expect(result, [
        [1]
      ]);

      await persistentStore!.close();

      result = await persistentStore!.execute("select 1");
      expect(result, [
        [1]
      ]);
    });

    test(
        "Ask for multiple connections at once, yield one successful connection",
        () async {
      persistentStore = PostgresTestConfig().persistentStore();
      final connections = await Future.wait(
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
            .map((_) => persistentStore!.getDatabaseConnection()),
      );
      final first = connections.first;
      expect(connections, everyElement(first));
    });

    test("Make multiple requests at once, yield one successful connection",
        () async {
      persistentStore = PostgresTestConfig().persistentStore();
      final expectedValues = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      final values = await Future.wait(
        expectedValues.map((i) => persistentStore!.execute("select $i")),
      );

      expect(
        values,
        expectedValues
            .map(
              (v) => [
                [v]
              ],
            )
            .toList(),
      );
    });

    test("Make multiple requests at once, all fail because db connect fails",
        () async {
      persistentStore =
          PostgresTestConfig().persistentStore(dbName: 'xyzxyznotadb');

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
      persistentStore = PostgresTestConfig().persistentStore(port: 15434);

      var expectedValues = [1, 2, 3, 4, 5];
      var values = await Future.wait(
        expectedValues.map(
          (i) => persistentStore!.execute("select $i").catchError((e) => e),
        ),
      );
      expect(values, everyElement(const TypeMatcher<QueryException>()));

      proxy =
          SocketProxy(15434, int.parse(Platform.environment['POSTGRES_PORT']!));
      await proxy?.open();

      expectedValues = [5, 6, 7, 8, 9];
      values = await Future.wait(
        expectedValues.map((i) => persistentStore!.execute("select $i")),
      );
      expect(
        values,
        expectedValues
            .map(
              (v) => [
                [v]
              ],
            )
            .toList(),
      );
    });

    test("Connect to bad db fails gracefully, can then be used again",
        () async {
      persistentStore = PostgresTestConfig().persistentStore(port: 15433);

      try {
        await persistentStore!.executeQuery("SELECT 1", null, 20);
        expect(true, false);
      } on QueryException {
        //empty
      }

      proxy =
          SocketProxy(15433, int.parse(Platform.environment['POSTGRES_PORT']!));
      await proxy!.open();

      final x = await persistentStore!.executeQuery("SELECT 1", null, 20);
      expect(x, [
        [1]
      ]);
    });
  });

  group("Registration", () {
    test("Create with default constructor registers and handles shutdown",
        () async {
      final store = PostgresTestConfig().persistentStore();

      await store.execute("SELECT 1");
      expect(store.isConnected, true);

      await store.close();

      expect(store.isConnected, false);
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
    _server = await ServerSocket.bind("localhost", src);
    _server!.listen((socket) async {
      final outgoing = await Socket.connect("localhost", dest);

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
