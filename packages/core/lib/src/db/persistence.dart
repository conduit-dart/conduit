import 'dart:async';

import 'package:conduit_core/src/db/managed/context.dart';
import 'package:conduit_core/src/db/persistent_store/persistent_store.dart';

/// Unified handle for an application's persistence layer.
///
/// Conduit apps frequently use a relational store (Postgres, MySQL, SQLite,
/// CockroachDB, …) for their primary domain model and a graph store
/// (Neo4j, …) for relationship-heavy or multi-hop workloads. Wiring those
/// two backends as separate fields on an [ApplicationChannel] is fine, but
/// it leaves no single object to:
///
/// - hand a controller that needs both
/// - close in one call at shutdown
/// - probe for capability ("is graph configured in this deployment?")
///
/// [Persistence] is that object. It owns the relational [PersistentStore]
/// and the optional graph store, exposes capability flags, and provides a
/// single [close] entry point.
///
/// The generic parameter [G] is the application's graph-store type
/// (typically `GraphPersistentStore` from `package:conduit_graph`, or a
/// concrete backend such as `Neo4jPersistentStore`). `conduit_core` does
/// **not** depend on `conduit_graph`; the generic keeps the umbrella
/// graph-agnostic so graph remains an opt-in dependency for apps that
/// want it.
///
/// ## Usage
///
/// ```dart
/// import 'package:conduit_core/conduit_core.dart';
/// import 'package:conduit_graph/conduit_graph.dart';
/// import 'package:conduit_graph_neo4j/conduit_graph_neo4j.dart';
/// import 'package:conduit_postgresql/conduit_postgresql.dart';
///
/// class MyChannel extends ApplicationChannel {
///   late final Persistence<GraphPersistentStore> persistence;
///
///   @override
///   Future<void> prepare() async {
///     persistence = Persistence<GraphPersistentStore>(
///       sql: PostgreSQLPersistentStore.fromConnectionInfo(
///         'user', 'pass', 'localhost', 5432, 'mydb',
///       ),
///       graph: Neo4jPersistentStore(Uri.parse('bolt://localhost:7687')),
///     );
///     persistence.sqlContext = ManagedContext(
///       ManagedDataModel.fromCurrentMirrorSystem(),
///       persistence.sql,
///     );
///     persistence.graphContext = GraphContext(
///       GraphDataModel()..registerNode<User>(...),
///       persistence.graph,
///     );
///   }
///
///   @override
///   Future<void> close() async {
///     await persistence.close();
///     await super.close();
///   }
/// }
/// ```
///
/// ## What this class does *not* do
///
/// - **No cross-backend transactions.** Coordinating a SQL commit with a
///   graph commit (i.e. XA / two-phase commit across heterogeneous
///   backends) is out of scope. If your domain needs that, you have a
///   distributed-systems problem this umbrella does not solve — typical
///   answers are an outbox table on the SQL side, eventual consistency
///   to the graph, or accepting that one of the two writes can lag. Do
///   not paper over this with a `Persistence.transaction(...)` wrapper:
///   it would silently lie about atomicity.
/// - **No automatic context construction.** Building the [ManagedContext]
///   and graph context requires data models that only the application
///   knows about. The umbrella holds the contexts for you (in
///   [sqlContext] and [graphContext]) but does not build them.
class Persistence<G extends Object> {
  /// Creates a [Persistence] umbrella.
  ///
  /// Either [sql], [graph], or both may be provided. A [Persistence] with
  /// neither configured is legal but generally a programmer error — the
  /// only legitimate use is a deployment-time degraded-mode flag.
  Persistence({
    PersistentStore? sql,
    G? graph,
  })  : _sqlStore = sql,
        _graphStore = graph;

  final PersistentStore? _sqlStore;
  final G? _graphStore;

  /// The relational [ManagedContext] for this application.
  ///
  /// Mutable so the consumer can build it in [ApplicationChannel.prepare]
  /// after constructing this umbrella; the umbrella does not know the
  /// application's [ManagedDataModel].
  ManagedContext? sqlContext;

  /// The graph context for this application.
  ///
  /// Typed as [Object] (rather than `GraphContext`) because `conduit_core`
  /// must not take a hard dependency on `conduit_graph`. Cast to the
  /// concrete `GraphContext` type at the use site:
  ///
  /// ```dart
  /// final gc = persistence.graphContext! as GraphContext;
  /// ```
  ///
  /// In practice the cast happens once, in a controller field initializer
  /// or constructor — not on the hot path.
  Object? graphContext;

  /// Whether a relational store is configured.
  bool get hasSql => _sqlStore != null;

  /// Whether a graph store is configured.
  bool get hasGraph => _graphStore != null;

  /// The configured relational [PersistentStore].
  ///
  /// Throws [StateError] if no SQL store was provided to the constructor.
  /// Use [hasSql] to probe before access if the deployment may run
  /// without a relational store.
  PersistentStore get sql {
    final s = _sqlStore;
    if (s == null) {
      throw StateError(
        'Persistence: no SQL store configured. Construct Persistence with '
        '`sql:` or guard access with `if (persistence.hasSql) ...`.',
      );
    }
    return s;
  }

  /// The configured graph store, typed as [G].
  ///
  /// Throws [StateError] if no graph store was provided to the constructor.
  /// Use [hasGraph] to probe before access if the deployment may run
  /// without a graph store.
  G get graph {
    final g = _graphStore;
    if (g == null) {
      throw StateError(
        'Persistence: no graph store configured. Construct Persistence with '
        '`graph:` or guard access with `if (persistence.hasGraph) ...`.',
      );
    }
    return g;
  }

  /// Close all configured stores.
  ///
  /// Safe to call when only one (or neither) backend is configured. Each
  /// store's `close()` is awaited independently; errors from one do not
  /// short-circuit the other. A failure in either close is rethrown after
  /// both have been attempted.
  ///
  /// The graph store's `close()` is invoked dynamically (via
  /// `(_graphStore as dynamic).close()`) because [G] is unconstrained;
  /// in practice every implementation of `GraphPersistentStore` exposes
  /// a `Future<void> close()` — this is part of the contract.
  Future<void> close() async {
    Object? sqlError;
    Object? graphError;
    StackTrace? sqlTrace;
    StackTrace? graphTrace;

    final sqlStore = _sqlStore;
    if (sqlStore != null) {
      try {
        await sqlStore.close();
      } catch (e, st) {
        sqlError = e;
        sqlTrace = st;
      }
    }

    if (_graphStore != null) {
      try {
        // ignore: avoid_dynamic_calls
        await (_graphStore as dynamic).close();
      } catch (e, st) {
        graphError = e;
        graphTrace = st;
      }
    }

    if (sqlError != null) {
      Error.throwWithStackTrace(sqlError, sqlTrace!);
    }
    if (graphError != null) {
      Error.throwWithStackTrace(graphError, graphTrace!);
    }
  }
}
