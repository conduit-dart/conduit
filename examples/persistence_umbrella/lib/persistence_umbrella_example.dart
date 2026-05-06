/// Worked example of Conduit's `Persistence` umbrella.
///
/// This example uses **fake** stores — no Postgres, no Neo4j — so the app
/// boots in any environment. The point is to demonstrate the wiring
/// (channel construction, controller injection, capability checks,
/// shutdown) without infrastructure dependencies.
///
/// Replace [_FakeSqlStore] with `PostgreSQLPersistentStore` (or
/// `MySqlPersistentStore` / `SqlitePersistentStore` / `CockroachPersistentStore`)
/// and [_FakeGraphStore] with `Neo4jPersistentStore` to convert this into
/// a real application.
library;

import 'dart:async';

import 'package:conduit_core/conduit_core.dart';

/// Application channel that wires both backends behind a single
/// [Persistence] umbrella.
class ExampleChannel extends ApplicationChannel {
  @override
  Future<void> prepare() async {
    persistence = Persistence<_FakeGraphStore>(
      sql: _FakeSqlStore()
        ..rows['users'] = [
          {'id': 1, 'name': 'Ada Lovelace'},
          {'id': 2, 'name': 'Grace Hopper'},
        ],
      graph: _FakeGraphStore()
        ..edges[1] = [2]
        ..edges[2] = [1],
    );

    // SQL context wiring is delegated to the helper.
    attachPersistence(
      persistence! as Persistence<_FakeGraphStore>,
      // An empty data model is sufficient for this example — no
      // ManagedObject types are involved. Real apps pass
      // `ManagedDataModel.fromCurrentMirrorSystem()` or an explicit list.
      sqlModel: ManagedDataModel([]),
    );

    // Graph context wiring is one line on the consumer side; conduit_core
    // does not depend on conduit_graph, so the helper does not know about
    // GraphContext.
    persistence!.graphContext = _FakeGraphContext(
      persistence!.graph as _FakeGraphStore,
    );
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router.route('/me/[:id]').link(() => MeController(persistence!));
    return router;
  }

  @override
  Future close() async {
    await persistence?.close();
    await super.close();
  }
}

/// Controller that touches both backends to assemble a single response.
class MeController extends ResourceController {
  MeController(this.persistence);

  /// Typed against the `Object` upper bound of the channel field, but
  /// the controller knows the concrete graph-store type so it casts at
  /// the boundary. This pattern keeps the channel base class graph-
  /// agnostic without leaking dynamic typing into business logic.
  final Persistence<Object> persistence;

  @Operation.get('id')
  Future<Response> getMe(@Bind.path('id') int id) async {
    if (!persistence.hasSql) {
      return Response.serverError(body: {'error': 'sql not configured'});
    }

    final sql = persistence.sql as _FakeSqlStore;
    final row = sql.rows['users']!
        .cast<Map<String, Object?>>()
        .firstWhere((r) => r['id'] == id, orElse: () => const {});
    if (row.isEmpty) {
      return Response.notFound();
    }

    final body = <String, Object?>{'user': row};
    if (persistence.hasGraph) {
      final gc = persistence.graphContext! as _FakeGraphContext;
      body['friends'] = gc.friendsOf(id);
    }
    return Response.ok(body);
  }
}

// ---------------------------------------------------------------------------
// Fake stores — replace with real backends in a production app.
// ---------------------------------------------------------------------------

/// Toy in-memory SQL store. Implements the [PersistentStore] contract
/// minimally; only [close] is exercised by this example. Real apps
/// substitute `PostgreSQLPersistentStore.fromConnectionInfo(...)`.
class _FakeSqlStore extends PersistentStore {
  final Map<String, List<Map<String, Object?>>> rows = {};
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Query<T> newQuery<T extends ManagedObject>(
    ManagedContext context,
    ManagedEntity entity, {
    T? values,
  }) =>
      throw UnimplementedError();

  @override
  Future<dynamic> execute(
    String sql, {
    Map<String, dynamic>? substitutionValues,
  }) =>
      throw UnimplementedError();

  @override
  Future<dynamic> executeQuery(
    String formatString,
    Map<String, dynamic> values,
    int timeoutInSeconds, {
    PersistentStoreQueryReturnType? returnType,
  }) =>
      throw UnimplementedError();

  @override
  Future<T> transaction<T>(
    ManagedContext transactionContext,
    Future<T> Function(ManagedContext transaction) transactionBlock,
  ) =>
      throw UnimplementedError();

  @override
  List<String> createTable(SchemaTable table, {bool isTemporary = false}) =>
      throw UnimplementedError();
  @override
  List<String> renameTable(SchemaTable table, String name) =>
      throw UnimplementedError();
  @override
  List<String> deleteTable(SchemaTable table) => throw UnimplementedError();
  @override
  List<String> addTableUniqueColumnSet(SchemaTable table) =>
      throw UnimplementedError();
  @override
  List<String> deleteTableUniqueColumnSet(SchemaTable table) =>
      throw UnimplementedError();
  @override
  List<String> addColumn(
    SchemaTable table,
    SchemaColumn column, {
    String? unencodedInitialValue,
  }) =>
      throw UnimplementedError();
  @override
  List<String> deleteColumn(SchemaTable table, SchemaColumn column) =>
      throw UnimplementedError();
  @override
  List<String> renameColumn(
    SchemaTable table,
    SchemaColumn column,
    String name,
  ) =>
      throw UnimplementedError();
  @override
  List<String> alterColumnNullability(
    SchemaTable table,
    SchemaColumn column,
    String? unencodedInitialValue,
  ) =>
      throw UnimplementedError();
  @override
  List<String> alterColumnUniqueness(SchemaTable table, SchemaColumn column) =>
      throw UnimplementedError();
  @override
  List<String> alterColumnDefaultValue(
    SchemaTable table,
    SchemaColumn column,
  ) =>
      throw UnimplementedError();
  @override
  List<String> alterColumnDeleteRule(SchemaTable table, SchemaColumn column) =>
      throw UnimplementedError();
  @override
  List<String> addIndexToColumn(SchemaTable table, SchemaColumn column) =>
      throw UnimplementedError();
  @override
  List<String> renameIndex(
    SchemaTable table,
    SchemaColumn column,
    String newIndexName,
  ) =>
      throw UnimplementedError();
  @override
  List<String> deleteIndexFromColumn(
    SchemaTable table,
    SchemaColumn column,
  ) =>
      throw UnimplementedError();

  @override
  Future<int> get schemaVersion async => 0;

  @override
  Future<Schema> upgrade(
    Schema fromSchema,
    List<Migration> withMigrations, {
    bool temporary = false,
  }) =>
      throw UnimplementedError();
}

/// Toy in-memory graph store. Stand-in for `Neo4jPersistentStore` /
/// `GraphPersistentStore` without taking a dependency on `conduit_graph`
/// in this example pubspec — the umbrella works fine with any object
/// type via its generic parameter.
class _FakeGraphStore {
  final Map<int, List<int>> edges = {};
  bool closed = false;

  Future<void> close() async {
    closed = true;
  }

  List<int> friendsOf(int id) => edges[id] ?? const [];
}

/// Stand-in for `GraphContext`. Wraps the fake store and exposes the
/// domain operations the controller cares about.
class _FakeGraphContext {
  _FakeGraphContext(this.store);

  final _FakeGraphStore store;

  List<int> friendsOf(int id) => store.friendsOf(id);
}
