// Tests for the [Persistence] umbrella.
//
// These tests use fake stores (no infrastructure) so the umbrella's
// behavior — capability flags, getter throws, close() shutdown — is
// exercised in isolation from any real backend.

import 'dart:async';

import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

void main() {
  group('Persistence umbrella — capability flags', () {
    test('hasSql/hasGraph false when neither configured', () {
      final p = Persistence<_FakeGraphStore>();
      expect(p.hasSql, isFalse);
      expect(p.hasGraph, isFalse);
    });

    test('hasSql true when only SQL configured', () {
      final p = Persistence<_FakeGraphStore>(sql: _FakeSqlStore());
      expect(p.hasSql, isTrue);
      expect(p.hasGraph, isFalse);
    });

    test('hasGraph true when only graph configured', () {
      final p = Persistence<_FakeGraphStore>(graph: _FakeGraphStore());
      expect(p.hasSql, isFalse);
      expect(p.hasGraph, isTrue);
    });

    test('hasSql/hasGraph both true when both configured', () {
      final p = Persistence<_FakeGraphStore>(
        sql: _FakeSqlStore(),
        graph: _FakeGraphStore(),
      );
      expect(p.hasSql, isTrue);
      expect(p.hasGraph, isTrue);
    });
  });

  group('Persistence umbrella — store getters', () {
    test('sql returns the configured store', () {
      final store = _FakeSqlStore();
      final p = Persistence<_FakeGraphStore>(sql: store);
      expect(identical(p.sql, store), isTrue);
    });

    test('graph returns the configured store', () {
      final store = _FakeGraphStore();
      final p = Persistence<_FakeGraphStore>(graph: store);
      expect(identical(p.graph, store), isTrue);
    });

    test('sql throws StateError when not configured', () {
      final p = Persistence<_FakeGraphStore>(graph: _FakeGraphStore());
      expect(() => p.sql, throwsA(isA<StateError>()));
    });

    test('graph throws StateError when not configured', () {
      final p = Persistence<_FakeGraphStore>(sql: _FakeSqlStore());
      expect(() => p.graph, throwsA(isA<StateError>()));
    });

    test('sql/graph throw on completely-empty Persistence', () {
      final p = Persistence<_FakeGraphStore>();
      expect(() => p.sql, throwsA(isA<StateError>()));
      expect(() => p.graph, throwsA(isA<StateError>()));
    });
  });

  group('Persistence umbrella — context fields', () {
    test('sqlContext and graphContext default to null', () {
      final p = Persistence<_FakeGraphStore>(
        sql: _FakeSqlStore(),
        graph: _FakeGraphStore(),
      );
      expect(p.sqlContext, isNull);
      expect(p.graphContext, isNull);
    });

    test('sqlContext is mutable', () {
      final store = _FakeSqlStore();
      final p = Persistence<_FakeGraphStore>(sql: store);
      // ManagedDataModel([]) is the simplest way to construct a context
      // for this test without a Postgres connection.
      final ctx = ManagedContext(ManagedDataModel([]), store);
      p.sqlContext = ctx;
      expect(identical(p.sqlContext, ctx), isTrue);
    });

    test('graphContext is mutable and accepts arbitrary objects', () {
      // graphContext is typed as Object? so it can hold a GraphContext
      // (from conduit_graph) without conduit_core taking that dependency.
      final p = Persistence<_FakeGraphStore>(graph: _FakeGraphStore());
      final marker = _FakeGraphContext();
      p.graphContext = marker;
      expect(identical(p.graphContext, marker), isTrue);
    });
  });

  group('Persistence umbrella — close()', () {
    test('closes both stores when both configured', () async {
      final sql = _FakeSqlStore();
      final graph = _FakeGraphStore();
      final p = Persistence<_FakeGraphStore>(sql: sql, graph: graph);

      expect(sql.closed, isFalse);
      expect(graph.closed, isFalse);

      await p.close();

      expect(sql.closed, isTrue);
      expect(graph.closed, isTrue);
    });

    test('closes SQL only when graph absent', () async {
      final sql = _FakeSqlStore();
      final p = Persistence<_FakeGraphStore>(sql: sql);

      await p.close();
      expect(sql.closed, isTrue);
    });

    test('closes graph only when SQL absent', () async {
      final graph = _FakeGraphStore();
      final p = Persistence<_FakeGraphStore>(graph: graph);

      await p.close();
      expect(graph.closed, isTrue);
    });

    test('close() on empty Persistence is a no-op', () async {
      final p = Persistence<_FakeGraphStore>();
      // Must not throw.
      await p.close();
    });

    test('close() attempts both even if SQL throws', () async {
      final sql = _FakeSqlStore(throwOnClose: true);
      final graph = _FakeGraphStore();
      final p = Persistence<_FakeGraphStore>(sql: sql, graph: graph);

      await expectLater(p.close(), throwsA(isA<StateError>()));
      // Even though SQL.close() threw, graph.close() must still have run.
      expect(graph.closed, isTrue);
    });

    test('close() rethrows graph error after SQL succeeds', () async {
      final sql = _FakeSqlStore();
      final graph = _FakeGraphStore(throwOnClose: true);
      final p = Persistence<_FakeGraphStore>(sql: sql, graph: graph);

      await expectLater(p.close(), throwsA(isA<StateError>()));
      expect(sql.closed, isTrue);
    });
  });

  group('Persistence umbrella — generic-parameter typing', () {
    test('preserves concrete graph store type', () {
      final store = _FakeGraphStore();
      final p = Persistence<_FakeGraphStore>(graph: store);
      // p.graph should be statically typed as _FakeGraphStore — this is a
      // compile-time check; the runtime assertion is just identity.
      final _FakeGraphStore typed = p.graph;
      expect(identical(typed, store), isTrue);
    });

    test('Persistence<Specific> is assignable to Persistence<Object>?', () {
      // ApplicationChannel.persistence is typed as Persistence<Object>?;
      // a Persistence<_FakeGraphStore> must be assignable into it via
      // Dart's covariant generics. This is a compile-time check.
      final concrete = Persistence<_FakeGraphStore>(
        graph: _FakeGraphStore(),
      );
      final Persistence<Object> widened = concrete;
      expect(widened.hasGraph, isTrue);
    });
  });

  group('ApplicationChannel.attachPersistence', () {
    test('builds sqlContext when sqlModel + sql store provided', () {
      final channel = _TestChannel();
      final p = Persistence<_FakeGraphStore>(sql: _FakeSqlStore());
      channel.attachPersistence(p, sqlModel: ManagedDataModel([]));
      expect(p.sqlContext, isNotNull);
    });

    test('leaves sqlContext null when sqlModel omitted', () {
      final channel = _TestChannel();
      final p = Persistence<_FakeGraphStore>(sql: _FakeSqlStore());
      channel.attachPersistence(p);
      expect(p.sqlContext, isNull);
    });

    test('does not throw when persistence has no SQL store', () {
      final channel = _TestChannel();
      final p = Persistence<_FakeGraphStore>(graph: _FakeGraphStore());
      channel.attachPersistence(p, sqlModel: ManagedDataModel([]));
      expect(p.sqlContext, isNull);
    });

    test('returns the same Persistence for fluent use', () {
      final channel = _TestChannel();
      final p = Persistence<_FakeGraphStore>(sql: _FakeSqlStore());
      final returned = channel.attachPersistence(p);
      expect(identical(returned, p), isTrue);
    });
  });
}

/// Minimal channel subclass for testing helper methods that don't depend
/// on the runtime wiring.
class _TestChannel extends ApplicationChannel {
  @override
  Controller get entryPoint => Router();
}

// -- Test doubles -----------------------------------------------------------

/// Minimal [PersistentStore] stub. Only [close] is exercised by these tests;
/// the rest throw to make accidental use loud.
class _FakeSqlStore extends PersistentStore {
  _FakeSqlStore({this.throwOnClose = false});

  final bool throwOnClose;
  bool closed = false;

  @override
  Future close() async {
    closed = true;
    if (throwOnClose) {
      throw StateError('fake sql close failure');
    }
  }

  @override
  Query<T> newQuery<T extends ManagedObject>(
    ManagedContext context,
    ManagedEntity entity, {
    T? values,
  }) =>
      throw UnimplementedError();

  @override
  Future execute(String sql, {Map<String, dynamic>? substitutionValues}) =>
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

  // Concrete PersistentStore has additional methods past 6.0.0 — fall
  // through with noSuchMethod so this stub stays small even if the
  // interface grows.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #close) {
      closed = true;
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

/// Stand-in for `GraphPersistentStore`. Exposes `close()` because the
/// umbrella invokes it dynamically — that contract is documented on
/// [Persistence.close].
class _FakeGraphStore {
  _FakeGraphStore({this.throwOnClose = false});

  final bool throwOnClose;
  bool closed = false;

  Future<void> close() async {
    closed = true;
    if (throwOnClose) {
      throw StateError('fake graph close failure');
    }
  }
}

/// Stand-in for `GraphContext` (which lives in conduit_graph). The umbrella
/// holds it as `Object?` so we can use any value here.
class _FakeGraphContext {}
