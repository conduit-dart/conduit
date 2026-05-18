/// Test helpers for constructing a [Persistence] umbrella without
/// requiring real Postgres / Neo4j infrastructure.
///
/// The fakes only need to satisfy the `is`-checks and getter contracts
/// the [SchemaBuilder.fromPersistence] code-path exercises — they do
/// NOT implement query semantics.
library;

import 'dart:async';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_graph/conduit_graph.dart';

class FakeSqlStore extends PersistentStore {
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Query<T> newQuery<T extends ManagedObject<dynamic>>(
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

/// Minimal [GraphPersistentStore] stub. Throws on every operation
/// except [close] — schema-derivation code never invokes query methods,
/// so the throws are dead branches at test time.
class FakeGraphStore implements GraphPersistentStore {
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<List<N>> match<N extends GraphNode<N>>(GraphPattern<N> pattern) =>
      throw UnimplementedError();

  @override
  Future<List<N>> executeQuery<N extends GraphNode<N>>(GraphQuery<N> query) =>
      throw UnimplementedError();

  @override
  Future<N> create<N extends GraphNode<N>>(N node) =>
      throw UnimplementedError();

  @override
  Future<E> createEdge<E extends GraphEdge<dynamic, dynamic>>(E edge) =>
      throw UnimplementedError();

  @override
  Future<List<N>> traverse<N extends GraphNode<N>>(
    GraphNode<dynamic> from,
    Type edgeKind, {
    GraphRelationshipDirection direction =
        GraphRelationshipDirection.outgoing,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, Object?>>> cypher(
    String rawQuery, {
    Map<String, Object?> params = const {},
  }) =>
      throw UnimplementedError();
}

/// Builds a [Persistence] umbrella with both halves wired to
/// no-infrastructure fakes plus the supplied data models.
Persistence<GraphPersistentStore> buildFakePersistence({
  ManagedDataModel? sqlModel,
  GraphDataModel? graphModel,
}) {
  final sqlStore = sqlModel != null ? FakeSqlStore() : null;
  final graphStore = graphModel != null ? FakeGraphStore() : null;
  final p = Persistence<GraphPersistentStore>(
    sql: sqlStore,
    graph: graphStore,
  );
  if (sqlStore != null && sqlModel != null) {
    p.sqlContext = ManagedContext(sqlModel, sqlStore);
  }
  if (graphStore != null && graphModel != null) {
    p.graphContext = GraphContext(graphModel, graphStore);
  }
  return p;
}
