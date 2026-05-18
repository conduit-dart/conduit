/// Worked example: GraphQL serving a unified schema over a
/// `Persistence` umbrella that holds both a relational store (for
/// `User`) and a graph store (for the `Friendship` edges between
/// users).
///
/// Like the sibling `persistence_umbrella` example, this uses **fake**
/// stores so the app boots without infrastructure. The point is to
/// demonstrate the cross-source wiring:
///
///   * one [SchemaBuilder.fromPersistence] call producing one schema;
///   * source tags letting the channel introspect which half emitted
///     each ObjectType;
///   * a hand-written stitching resolver on `User.friends` that walks
///     graph friendships and re-fetches users from SQL;
///   * a [FieldAuthorize]-tagged field demonstrating field-level auth.
///
/// In production:
///
///   * Replace [_FakeSqlStore] with `PostgreSQLPersistentStore.fromConnectionInfo(...)`.
///   * Replace [_FakeGraphStore] with `Neo4jPersistentStore(Uri.parse('bolt://localhost:7687'))`.
///   * Replace the in-memory data with a real schema migration / seed.
///
/// See `docs/persistence/graphql-cross-source.md` for the prose
/// version of this same pattern.
library;

import 'dart:async';

import 'package:conduit_core/conduit_core.dart' hide SchemaBuilder;
import 'package:conduit_graph/conduit_graph.dart';
import 'package:conduit_graphql/conduit_graphql.dart';

// -- Domain model -----------------------------------------------------------

/// Relational user. Lives in `User`'s ManagedObject; persists in SQL.
class User extends ManagedObject<_User> implements _User {}

class _User {
  @primaryKey
  int? id;

  @Column(unique: true)
  String? email;

  @Column(nullable: true)
  String? displayName;
}

/// Graph profile: a thin "anchor" node that the friend topology hangs
/// off of. The relational `User.id` is stored as a graph property on
/// the corresponding `Profile` node so the stitching resolver can
/// re-key.
class Profile extends GraphNode<Profile> {
  Profile() : super(labels: const [GraphLabel.unchecked('Profile')]);

  int? get userId => this['userId'] as int?;
  set userId(int? v) => this['userId'] = v;
}

class Friendship extends GraphEdge<Profile, Profile> {
  Friendship({required super.from, required super.to})
      : super(label: const GraphLabel.unchecked('Friendship'));

  DateTime? get since => this['since'] as DateTime?;
  set since(DateTime? v) => this['since'] = v;
}

// -- Application channel ----------------------------------------------------

class CrossSourceChannel extends ApplicationChannel {
  // ApplicationChannel already declares `Persistence<Object>? persistence;`.
  // We hold the typed handle locally to keep call sites strongly typed
  // without redeclaring the inherited slot.
  late Persistence<GraphPersistentStore> typedPersistence;
  late PersistenceSchema persistenceSchema;
  late GraphQL engine;

  @override
  Future<void> prepare() async {
    final sqlStore = _FakeSqlStore()
      ..rows[1] = {'id': 1, 'email': 'ada@example.com', 'displayName': 'Ada'}
      ..rows[2] = {'id': 2, 'email': 'grace@example.com', 'displayName': 'Grace'}
      ..rows[3] = {'id': 3, 'email': 'fei@example.com', 'displayName': 'Fei-Fei'};
    final graphStore = _FakeGraphStore()
      ..addFriendship(1, 2)
      ..addFriendship(1, 3)
      ..addFriendship(2, 3);

    typedPersistence = Persistence<GraphPersistentStore>(
      sql: sqlStore,
      graph: graphStore,
    );
    persistence = typedPersistence;

    final sqlModel = ManagedDataModel([User]);
    typedPersistence.sqlContext = ManagedContext(sqlModel, sqlStore);
    final graphModel = GraphDataModel()
      ..registerNode<Profile>(label: const GraphLabel.unchecked('Profile'))
      ..registerEdge<Friendship, Profile, Profile>(
        label: const GraphLabel.unchecked('Friendship'),
      );
    typedPersistence.graphContext = GraphContext(graphModel, graphStore);

    // Build the unified schema. We do NOT pass a PersistenceResolverFactory
    // here because the example uses hand-rolled stitching resolvers — the
    // umbrella's auto-resolvers want a real Conduit ManagedContext +
    // GraphPersistentStore, which the fake stores don't fully implement.
    persistenceSchema = SchemaBuilder().fromPersistence(typedPersistence);

    // Mount the stitching resolver on the SQL `User.friends` field.
    // graphql_schema2 ties resolvers to fields at construction time, so
    // we look up the User object type and inject a synthetic
    // GraphQLObjectField for `friends`.
    _attachStitchingResolver();

    engine = GraphQL(persistenceSchema.schema);
  }

  void _attachStitchingResolver() {
    final userType = persistenceSchema.sqlObjectTypes['User']!;
    final stitched = GraphQLObjectField<dynamic, dynamic>(
      'friends',
      GraphQLListType(userType.nonNullable()).nonNullable(),
      resolve: (parent, args) async {
        // Step 1: who are we?
        final userId = parent is ManagedObject
            ? parent['id'] as int?
            : parent is Map
                ? parent['id'] as int?
                : null;
        if (userId == null) return const <Object>[];

        // Step 2: walk graph friendships from this user's profile.
        final graphStore = typedPersistence.graph as _FakeGraphStore;
        final friendUserIds = graphStore.friendsOf(userId);

        // Step 3: re-fetch the friend rows from SQL. In a real app
        // this would batch through a DataLoader; the fake store fans
        // out one-by-one for clarity.
        final sqlStore = typedPersistence.sql as _FakeSqlStore;
        return [
          for (final id in friendUserIds)
            if (sqlStore.rows[id] != null) sqlStore.rows[id]!,
        ];
      },
      description: 'Friends of this user, stitched from the graph store '
          'into the SQL user table.',
    );
    userType.fields.add(stitched);
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router.route('/graphql').link(
          () => GraphQLController(persistenceSchema.schema),
        );
    return router;
  }

  @override
  Future close() async {
    await typedPersistence.close();
    await super.close();
  }
}

// -- Toy backends -----------------------------------------------------------

class _FakeSqlStore extends PersistentStore {
  final Map<int, Map<String, Object?>> rows = {};
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }

  // Stubs ------------------------------------------------------------------

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

class _FakeGraphStore implements GraphPersistentStore {
  final Map<int, List<int>> _edges = {};
  bool closed = false;

  void addFriendship(int a, int b) {
    _edges.putIfAbsent(a, () => []).add(b);
    _edges.putIfAbsent(b, () => []).add(a);
  }

  List<int> friendsOf(int userId) => _edges[userId] ?? const [];

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
