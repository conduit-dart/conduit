/// Neo4j-backed implementation of `GraphPersistentStore` (PR #266).
///
/// What this ships in v0
/// ---------------------
/// - One Bolt v4.x connection per store instance, lazily opened on
///   first call. Single connection, no pool — see
///   [Neo4jPersistentStore.runInTransaction] for the explicit-tx
///   caveat.
/// - Pattern-based reads via the Cypher emitter (`match`,
///   `executeQuery`, `traverse`).
/// - Node + edge create using `id(n)` as the assigned id (Neo4j's
///   internal numeric id).
/// - Always-on raw-Cypher escape hatch (`cypher`).
///
/// Deliberate non-goals
/// --------------------
/// - No connection pooling; multi-statement workloads serialize
///   through the single underlying socket. Pool work is queued for a
///   later phase.
/// - No clustering / routing (`neo4j://` scheme); v0 is `bolt://`
///   only.
/// - No migration system (`Schema*` is not part of `conduit_graph`,
///   so there is nothing to lower here).
/// - No causal consistency beyond "same connection" — bookmarks are
///   not implemented.
library;

import 'dart:async';

import 'package:conduit_graph/conduit_graph.dart';

import 'bolt/bolt.dart';
import 'cypher_emitter.dart';

/// Backend for `conduit_graph` that talks to Neo4j over Bolt v4.x.
class Neo4jPersistentStore implements GraphPersistentStore {
  /// Construct a new store.
  ///
  /// [uri] is a Bolt URI (`bolt://host:port`); the path is interpreted
  /// as the target database name when non-empty (overriding [database]).
  /// Username/password are optional — pass `null` for an unauthenticated
  /// connection (Neo4j Aura always requires auth; the dev sandbox
  /// disables it on `dbms.security.auth_enabled=false`).
  Neo4jPersistentStore(
    this.uri, {
    this.username,
    this.password,
    this.database = 'neo4j',
    this.userAgent = 'conduit_graph_neo4j/0.1',
    this.connectTimeout = const Duration(seconds: 30),
    GraphDataModel? dataModel,
    // ignore: prefer_initializing_formals
  }) : _dataModel = dataModel {
    if (uri.scheme != 'bolt') {
      throw ArgumentError.value(
        uri,
        'uri',
        "Neo4jPersistentStore only supports the 'bolt://' scheme in v0; "
            "got '${uri.scheme}'",
      );
    }
  }

  /// Bolt URI (e.g. `bolt://localhost:7687`).
  final Uri uri;

  /// Basic-auth principal, or `null` for anonymous.
  final String? username;

  /// Basic-auth credentials, or `null` for anonymous.
  final String? password;

  /// Target database name (Neo4j 4.x supports multi-database).
  final String database;

  /// `user_agent` value sent in HELLO. Surfaces in the Neo4j server log.
  final String userAgent;

  /// Timeout for the initial TCP + handshake.
  final Duration connectTimeout;

  /// Optional data model. If unset, the store falls back to the
  /// `GraphContext`-supplied model when [bindDataModel] is called.
  GraphDataModel? _dataModel;

  /// Bind the data model used to resolve node/edge entities. The
  /// `GraphContext` constructor doesn't currently push the model into
  /// the store automatically — call this once after constructing the
  /// context (or pass `dataModel:` to the constructor) so
  /// [createEdge] / [traverse] can resolve labels by Dart type.
  ///
  /// Calling this twice with a different model is rejected to avoid
  /// silently dropping registrations from one of them.
  void bindDataModel(GraphDataModel model) {
    if (_dataModel != null && !identical(_dataModel, model)) {
      throw StateError(
        'Neo4jPersistentStore is already bound to a different '
        'GraphDataModel; create a fresh store instead.',
      );
    }
    _dataModel = model;
  }

  /// The bound data model, if any.
  GraphDataModel? get dataModel => _dataModel;

  BoltConnection? _connection;
  Future<BoltConnection>? _connecting;
  bool _closed = false;

  // ---------------------------------------------------------------------
  // Connection lifecycle
  // ---------------------------------------------------------------------

  Future<BoltConnection> _ensureConnected() {
    if (_closed) {
      throw GraphConnectionError(
        'Neo4jPersistentStore is closed; create a new one to reconnect',
      );
    }
    final existing = _connection;
    if (existing != null) return Future.value(existing);
    return _connecting ??= _openConnection().whenComplete(() {
      _connecting = null;
    });
  }

  Future<BoltConnection> _openConnection() async {
    final host = uri.host;
    if (host.isEmpty) {
      throw GraphConnectionError(
        'Bolt URI must have a host: $uri',
      );
    }
    final port = uri.hasPort ? uri.port : 7687;
    try {
      final conn = await BoltConnection.connect(
        host,
        port,
        timeout: connectTimeout,
      );
      try {
        await conn.hello(
          userAgent: userAgent,
          username: username,
          password: password,
        );
      } catch (e) {
        await conn.close();
        if (e is BoltFailure) {
          throw GraphConnectionError(
            'Neo4j HELLO failed: ${e.code}: ${e.message}',
            cause: e,
          );
        }
        rethrow;
      }
      _connection = conn;
      return conn;
    } on BoltProtocolException catch (e) {
      throw GraphConnectionError(
        'Bolt handshake to $host:$port failed: ${e.message}',
        cause: e,
      );
    } catch (e) {
      throw GraphConnectionError(
        'Could not open Bolt connection to $host:$port',
        cause: e,
      );
    }
  }

  // ---------------------------------------------------------------------
  // GraphPersistentStore interface
  // ---------------------------------------------------------------------

  @override
  Future<List<N>> match<N extends GraphNode<N>>(
    GraphPattern<N> pattern,
  ) async {
    final stmt = emitPattern(pattern);
    final rows = await _runRaw(stmt.cypher, stmt.parameters);
    final anchorVar = pattern.root.variable;
    return rows
        .map((r) => _hydrateNodeFromRow<N>(r[anchorVar]))
        .toList(growable: false);
  }

  @override
  Future<List<N>> executeQuery<N extends GraphNode<N>>(
    GraphQuery<N> query,
  ) async {
    final stmt = emitQuery(query);
    final rows = await _runRaw(stmt.cypher, stmt.parameters);
    final anchorVar = query.pattern.root.variable;
    return rows
        .map((r) => _hydrateNodeFromRow<N>(r[anchorVar]))
        .toList(growable: false);
  }

  @override
  Future<N> create<N extends GraphNode<N>>(N node) async {
    final labels = node.labels.map((l) => l.name).toList();
    if (labels.isEmpty) {
      throw GraphInvalidQuery(
        'cannot persist a node with no labels',
      );
    }
    final labelClause = labels
        .map(_escapeIdentifierSafe)
        .map((l) => ':$l')
        .join();
    final stmt = 'CREATE (n$labelClause \$props) RETURN n';
    final rows = await _runRaw(stmt, {'props': _marshalProps(node.properties)});
    if (rows.isEmpty) {
      throw GraphConnectionError('CREATE returned no rows');
    }
    final created = rows.first['n'];
    final id = _extractId(created);
    if (id == null) {
      throw GraphConnectionError(
        'CREATE response did not include a node id',
      );
    }
    node.id = id;
    return node;
  }

  @override
  Future<E> createEdge<E extends GraphEdge<dynamic, dynamic>>(E edge) async {
    if (edge.from.id == null || edge.to.id == null) {
      throw GraphNotFoundError(
        'cannot persist edge — both endpoints must have an id assigned '
        '(call create on each node first)',
      );
    }
    final cypher =
        'MATCH (f), (t) WHERE id(f) = \$fromId AND id(t) = \$toId '
        'CREATE (f)-[r:${_escapeIdentifierSafe(edge.label.name)} \$props]->(t) '
        'RETURN r';
    final rows = await _runRaw(cypher, {
      'fromId': edge.from.id,
      'toId': edge.to.id,
      'props': _marshalProps(edge.properties),
    });
    if (rows.isEmpty) {
      throw GraphNotFoundError(
        'createEdge could not match endpoints '
        '(fromId=${edge.from.id}, toId=${edge.to.id})',
      );
    }
    final id = _extractId(rows.first['r']);
    edge.id = id;
    return edge;
  }

  @override
  Future<List<N>> traverse<N extends GraphNode<N>>(
    GraphNode<dynamic> from,
    Type edgeKind, {
    GraphRelationshipDirection direction =
        GraphRelationshipDirection.outgoing,
  }) async {
    if (from.id == null) {
      throw GraphNotFoundError(
        'cannot traverse — start node has no id (was it persisted?)',
      );
    }
    final edgeLabel = _resolveEdgeLabel(edgeKind);
    final arrow = _arrowFor(direction);
    final cypher = 'MATCH (a) WHERE id(a) = \$fromId '
        'MATCH (a)${arrow.open}[:${_escapeIdentifierSafe(edgeLabel)}]'
        '${arrow.close}(b) RETURN b';
    final rows = await _runRaw(cypher, {'fromId': from.id});
    return rows
        .map((r) => _hydrateNodeFromRow<N>(r['b']))
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, Object?>>> cypher(
    String rawQuery, {
    Map<String, Object?> params = const {},
  }) =>
      _runRaw(rawQuery, params);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final conn = _connection;
    _connection = null;
    if (conn != null) {
      await conn.close();
    }
  }

  /// Run [body] inside an explicit Bolt transaction.
  ///
  /// Commits on success, rolls back on any thrown exception. Useful
  /// when the caller needs multiple statements to be atomic — `match`
  /// / `create` calls the same store makes inside [body] are routed
  /// through the active transaction by [Neo4jPersistentStore]
  /// itself? **No.** v0 does not push the active transaction into the
  /// implicit `_runRaw` path — those still hit the autocommit channel.
  /// Use the [BoltTransaction.run] surface inside [body] when you need
  /// transactional semantics.
  Future<T> runInTransaction<T>(
    Future<T> Function(BoltTransaction tx) body,
  ) async {
    final conn = await _ensureConnected();
    final tx = await conn.beginTransaction(extra: {'db': database});
    try {
      final result = await body(tx);
      await tx.commit();
      return result;
    } catch (e) {
      try {
        await tx.rollback();
      } catch (_) {
        // Best-effort rollback; surface the original error.
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  Future<List<Map<String, Object?>>> _runRaw(
    String cypher,
    Map<String, Object?> params,
  ) async {
    final conn = await _ensureConnected();
    try {
      final result = await conn.runAndPull(
        cypher,
        parameters: _marshalProps(params),
        extra: {'db': database},
      );
      return result.rowsAsMaps();
    } on BoltFailure catch (e) {
      throw _failureToGraphException(e);
    } on BoltProtocolException catch (e) {
      throw GraphConnectionError(e.message, cause: e);
    }
  }

  /// Map common Neo4j error codes onto the standard `GraphException`
  /// kinds. Anything we don't recognize falls through as a generic
  /// `GraphConnectionError` (with the original `BoltFailure` as the
  /// cause so the caller can still inspect the code).
  GraphException _failureToGraphException(BoltFailure e) {
    final code = e.code;
    if (code.contains('ConstraintValidationFailed') ||
        code.contains('ConstraintViolation')) {
      return GraphConstraintViolation(e.message, cause: e);
    }
    if (code.contains('EntityNotFound')) {
      return GraphNotFoundError(e.message, cause: e);
    }
    if (code.contains('SyntaxError') ||
        code.contains('ParameterMissing') ||
        code.contains('TypeError')) {
      return GraphInvalidQuery(e.message, cause: e);
    }
    return GraphConnectionError(e.message, cause: e);
  }

  /// Convert a Dart property bag into a PackStream-friendly map.
  Map<String, Object?> _marshalProps(Map<String, Object?> input) {
    final out = <String, Object?>{};
    input.forEach((k, v) {
      out[k] = _marshalValue(v);
    });
    return out;
  }

  Object? _marshalValue(Object? v) {
    if (v == null || v is bool || v is num || v is String) return v;
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is List) return v.map(_marshalValue).toList();
    if (v is Map) {
      final m = <String, Object?>{};
      v.forEach((k, vv) {
        if (k is! String) {
          throw ArgumentError(
            'Neo4j property maps must be string-keyed; got '
            '${k.runtimeType}',
          );
        }
        m[k] = _marshalValue(vv);
      });
      return m;
    }
    // Last resort — surface as a string so we don't blow up on the
    // wire. Callers should pre-marshal exotic types themselves.
    return v.toString();
  }

  N _hydrateNodeFromRow<N extends GraphNode<N>>(Object? raw) {
    if (raw is! BoltStructure) {
      throw GraphConnectionError(
        'expected a Node structure in result row, got ${raw.runtimeType}',
      );
    }
    // Bolt v4.x Node tag is 0x4E ('N'). Fields: [id, labels, props].
    if (raw.tag != 0x4E) {
      throw GraphConnectionError(
        'expected a Node (tag 0x4E), got tag '
        '0x${raw.tag.toRadixString(16).padLeft(2, '0')}',
      );
    }
    if (raw.fields.length < 3) {
      throw GraphConnectionError(
        'Node structure has ${raw.fields.length} fields; expected 3',
      );
    }
    final id = raw.fields[0];
    final labelList = (raw.fields[1] as List).cast<String>();
    final props = (raw.fields[2] as Map).cast<String, Object?>();

    final factory = _resolveNodeFactory<N>(labelList);
    final node = factory();
    node.readFromMap(props);
    node.id = id;
    return node;
  }

  /// Find a no-arg factory for [N] in the bound data model. Falls back
  /// to throwing `GraphInvalidQuery` if no entity matches — at which
  /// point the caller is expected to use the `cypher()` escape hatch.
  ///
  /// **Note on factories.** `GraphDataModel` does not (yet) carry
  /// no-arg factories — node subclasses are user-defined and the
  /// model only knows their labels + Type. We require subclasses to
  /// expose either:
  ///
  ///   - a `nodeFactories` parameter passed to the store at
  ///     construction time, or
  ///   - a `dart:mirrors`-free runtime-registry style that the user
  ///     wires up themselves.
  ///
  /// For v0 we ship the factory-map approach. If [N] has no factory,
  /// we throw a clear `GraphInvalidQuery` rather than silently
  /// returning a dummy node.
  N Function() _resolveNodeFactory<N extends GraphNode<N>>(
    List<String> labels,
  ) {
    final factory = _factories[N];
    if (factory == null) {
      throw GraphInvalidQuery(
        "no node factory registered for $N — call "
        "Neo4jPersistentStore.registerNodeFactory<$N>(() => $N()) before "
        "match/executeQuery, or use cypher() and hydrate manually",
      );
    }
    return factory as N Function();
  }

  /// Type → no-arg factory map for hydration. Populated by
  /// [registerNodeFactory].
  final Map<Type, GraphNode<dynamic> Function()> _factories = {};

  /// Register a no-arg factory for node type [N]. Call this once per
  /// node type before issuing reads.
  void registerNodeFactory<N extends GraphNode<N>>(N Function() factory) {
    _factories[N] = factory;
  }

  Object? _extractId(Object? raw) {
    if (raw is BoltStructure) {
      // Node (0x4E) and Relationship (0x52) share `id` in field[0].
      if (raw.fields.isNotEmpty) return raw.fields[0];
    }
    if (raw is int) return raw;
    return null;
  }

  String _resolveEdgeLabel(Type edgeKind) {
    final model = _dataModel;
    if (model != null) {
      final entity = model.edgeEntities[edgeKind];
      if (entity != null) return entity.label.name;
    }
    // Fall back to the type name. Matches the convention
    // GraphDataModel uses by default.
    return edgeKind.toString();
  }

  ({String open, String close}) _arrowFor(GraphRelationshipDirection d) {
    switch (d) {
      case GraphRelationshipDirection.outgoing:
        return (open: '-', close: '->');
      case GraphRelationshipDirection.incoming:
        return (open: '<-', close: '-');
      case GraphRelationshipDirection.undirected:
        return (open: '-', close: '-');
    }
  }

  static final RegExp _safeIdent = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  String _escapeIdentifierSafe(String s) {
    if (_safeIdent.hasMatch(s)) return s;
    return '`${s.replaceAll('`', '``')}`';
  }
}
