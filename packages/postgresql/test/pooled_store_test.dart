import 'dart:async';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_postgresql/conduit_postgresql.dart';
import 'package:test/test.dart';

import 'not_tests/postgres_test_config.dart';

void main() {
  final config = PostgresTestConfig();

  PostgreSQLPersistentStore pooledStore({int maxConnectionCount = 3}) =>
      PostgreSQLPersistentStore(
        config.username,
        config.password,
        config.host,
        config.port,
        config.dbName,
        maxConnectionCount: maxConnectionCount,
      );

  group("Default store (maxConnectionCount: 1)", () {
    late PostgreSQLPersistentStore store;

    setUp(() {
      store = config.persistentStore();
    });

    tearDown(() async {
      await store.close();
    });

    test("is not pooled", () {
      expect(store.isPooled, false);
      expect(store.maxConnectionCount, 1);
    });

    test("serializes concurrent queries on a single backend", () async {
      final rows = await Future.wait(
        List.generate(
          3,
          (_) => store.execute("SELECT pg_backend_pid() FROM pg_sleep(0.2)"),
        ),
      );
      final pids = rows.map((r) => (r as List).first.first).toSet();
      expect(pids, hasLength(1));
    });
  });

  group("Pooled store", () {
    late PostgreSQLPersistentStore store;

    setUp(() {
      store = pooledStore();
    });

    tearDown(() async {
      await store.close();
    });

    test("reports pooled state", () async {
      expect(store.isPooled, true);
      expect(store.isConnected, false);
      await store.execute("SELECT 1");
      expect(store.isConnected, true);
    });

    test("executes concurrent queries on multiple backends", () async {
      final rows = await Future.wait(
        List.generate(
          3,
          (_) => store.execute("SELECT pg_backend_pid() FROM pg_sleep(0.2)"),
        ),
      );
      final pids = rows.map((r) => (r as List).first.first).toSet();
      expect(pids.length, greaterThan(1));
    });

    test("getDatabaseConnection throws StateError", () async {
      await expectLater(
        store.getDatabaseConnection(),
        throwsA(isA<StateError>()),
      );
    });

    test("can execute again after close (pool is recreated)", () async {
      await store.execute("SELECT 1");
      await store.close();
      expect(store.isConnected, false);

      final rows = await store.execute("SELECT 1") as List;
      expect(rows.first.first, 1);
    });
  });

  group("Transactions on a pooled store", () {
    late PostgreSQLPersistentStore store;
    late ManagedContext context;
    late Schema schema;

    setUp(() async {
      store = pooledStore();
      final dataModel = ManagedDataModel([PoolModel]);
      schema = Schema.fromDataModel(dataModel);
      for (final cmd in config.commandsFromDataModel(dataModel)) {
        await store.execute(cmd);
      }
      context = ManagedContext(dataModel, store);
    });

    tearDown(() async {
      await config.dropSchemaTables(schema, store);
      await context.close();
    });

    test("transaction commits and returns closure value", () async {
      final String? name = await context.transaction((t) async {
        final o = await Query.insertObject(t, PoolModel()..name = "Bob");
        return o.name;
      });
      expect(name, "Bob");

      final rows = await Query<PoolModel>(context).fetch();
      expect(rows, hasLength(1));
      expect(rows.first.name, "Bob");
    });

    test("transaction rolls back when the block throws", () async {
      await expectLater(
        context.transaction((t) async {
          await Query.insertObject(t, PoolModel()..name = "doomed");
          throw StateError("abort");
        }),
        throwsStateError,
      );

      expect(await Query<PoolModel>(context).fetch(), isEmpty);
    });

    test(
        "outer-context query proceeds on another connection while a transaction is open",
        () async {
      // On a single-connection store this pattern deadlocks (and issuing the
      // outer query from inside the block throws a runTx error). On a pooled
      // store the transaction holds one pooled connection while the outer
      // query checks out another.
      final release = Completer<void>();
      final tx = context.transaction((t) async {
        await Query.insertObject(t, PoolModel()..name = "in-tx");
        await release.future;
      });

      final visibleDuringTx = await Query<PoolModel>(context).fetch();
      expect(visibleDuringTx, isEmpty);

      release.complete();
      await tx;

      final visibleAfterTx = await Query<PoolModel>(context).fetch();
      expect(visibleAfterTx, hasLength(1));
      expect(visibleAfterTx.first.name, "in-tx");
    });
  });
}

class _PoolModel {
  @primaryKey
  int? id;

  String? name;
}

class PoolModel extends ManagedObject<_PoolModel> implements _PoolModel {}
