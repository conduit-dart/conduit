/// Load-test target for the k6 harness (see tool/load/README.md).
///
/// Everything is configured by environment variables so a run matrix can
/// be scripted without editing files:
///
///   PORT       HTTP port (default 8888)
///   ISOLATES   number of isolates; 0 = run on the main isolate (default 0)
///   POOL_SIZE  PostgreSQLPersistentStore.maxConnectionCount (default 1)
///   POSTGRES_HOST / POSTGRES_PORT / POSTGRES_USER / POSTGRES_PASSWORD /
///   POSTGRES_DB   database coordinates (defaults match ci/docker-compose.yaml)
///
/// Start with the VM service enabled so the isolate monitor can attach:
///
///   dart run --enable-vm-service=8181 --disable-service-auth-codes bin/main.dart
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_postgresql/conduit_postgresql.dart';

int _envInt(String key, int fallback) =>
    int.tryParse(Platform.environment[key] ?? "") ?? fallback;

String _envStr(String key, String fallback) {
  final v = Platform.environment[key];
  return (v == null || v.isEmpty) ? fallback : v;
}

Future main() async {
  final isolates = _envInt("ISOLATES", 0);
  final app = Application<LoadChannel>()..options.port = _envInt("PORT", 8888);

  if (isolates == 0) {
    await app.startOnCurrentIsolate();
  } else {
    await app.start(numberOfInstances: isolates);
  }

  print(
    "load_target up on :${app.options.port} "
    "(isolates: $isolates, pool: ${_envInt("POOL_SIZE", 1)})",
  );
}

class LoadChannel extends ApplicationChannel {
  late ManagedContext context;

  @override
  Future prepare() async {
    final store = PostgreSQLPersistentStore(
      _envStr("POSTGRES_USER", "conduit_test_user"),
      _envStr("POSTGRES_PASSWORD", "conduit!"),
      _envStr("POSTGRES_HOST", "localhost"),
      _envInt("POSTGRES_PORT", 15432),
      _envStr("POSTGRES_DB", "conduit_test_db"),
      maxConnectionCount: _envInt("POOL_SIZE", 1),
    );

    context = ManagedContext(
      ManagedDataModel.fromCurrentMirrorSystem(),
      store,
    );

    // Idempotent so every isolate can run it. Unquoted identifiers match
    // what the ORM emits for the _Item table definition.
    await store.execute(
      "CREATE TABLE IF NOT EXISTS _item "
      "(id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL)",
    );
  }

  @override
  Controller get entryPoint {
    return Router()
      ..route("/healthz").linkFunction((req) async => Response.ok("ok"))
      ..route("/items").link(() => ItemController(context))
      ..route("/tx").link(() => TxController(context))
      ..route("/slow").link(() => SlowQueryController(context));
  }
}

class ItemController extends ResourceController {
  ItemController(this.context);

  final ManagedContext context;

  @Operation.get()
  Future<Response> readItems(@Bind.query("limit") int? limit) async {
    final q = Query<Item>(context)..fetchLimit = min(limit ?? 20, 500);
    return Response.ok(await q.fetch());
  }

  @Operation.post()
  Future<Response> createItem() async {
    final q = Query<Item>(context)
      ..values.name = "item-${DateTime.now().microsecondsSinceEpoch}";
    return Response.ok(await q.insert());
  }
}

/// Exercises transaction checkout: on a pooled store each request's
/// transaction holds a dedicated connection while it runs.
class TxController extends ResourceController {
  TxController(this.context);

  final ManagedContext context;

  @Operation.get()
  Future<Response> insertAndCount() async {
    final int count = await context.transaction((t) async {
      final q = Query<Item>(t)
        ..values.name = "tx-${DateTime.now().microsecondsSinceEpoch}";
      await q.insert();
      return (await Query<Item>(t).reduce.count()) ?? 0;
    });
    return Response.ok({"count": count});
  }
}

/// Simulates a slow query with pg_sleep. This is the pooling showcase:
/// with POOL_SIZE=1 concurrent /slow requests serialize per isolate; with
/// POOL_SIZE=N they overlap up to N deep.
class SlowQueryController extends ResourceController {
  SlowQueryController(this.context);

  final ManagedContext context;

  @Operation.get()
  Future<Response> slow(@Bind.query("ms") int? ms) async {
    // Clamped and interpolated as a numeric literal — never a raw string.
    final seconds = (ms ?? 100).clamp(0, 5000) / 1000.0;
    await context.persistentStore.execute("SELECT pg_sleep($seconds)");
    return Response.ok({"slept_ms": (seconds * 1000).round()});
  }
}

class Item extends ManagedObject<_Item> implements _Item {}

class _Item {
  @primaryKey
  int? id;

  String? name;
}
