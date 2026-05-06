import 'dart:async';

import 'package:conduit_core/conduit_core.dart';
import 'package:sqlite3/sqlite3.dart' as s3;

import 'sqlite_schema_generator.dart';

/// SQLite-backed `PersistentStore`. **v0 scope: schema management +
/// migrations + raw `execute` / `executeQuery` / `transaction` only.**
/// The full ORM query path (`newQuery<T>`) is deferred until the query
/// builders are extracted from the postgresql package into core; until
/// then this store throws `UnimplementedError` from `newQuery`.
///
/// Why ship before the ORM path is wired: the schema management half is
/// what closes the test-harness gap (in-memory SQLite for migrations and
/// fixture seeding without Docker). Apps that want full ORM queries
/// against SQLite should track the multi-backend ORM roadmap; for now,
/// postgres remains the only backend with `newQuery` support.
///
/// Two factories:
///
/// * [SqlitePersistentStore.file] — opens a database at the given path,
///   creating it if absent.
/// * [SqlitePersistentStore.memory] — opens a transient in-memory
///   database; gone when the process or the store is closed.
class SqlitePersistentStore extends PersistentStore with SqliteSchemaGenerator {
  SqlitePersistentStore._(this._database);

  /// Open or create a SQLite database at [path]. Foreign-key enforcement
  /// is enabled by default (off historically; documented to be the
  /// default in v3.6+).
  factory SqlitePersistentStore.file(String path) {
    final db = s3.sqlite3.open(path);
    db.execute('PRAGMA foreign_keys = ON');
    return SqlitePersistentStore._(db);
  }

  /// Open a transient in-memory SQLite database. The database lives only
  /// for the lifetime of this store; no disk persistence.
  factory SqlitePersistentStore.memory() {
    final db = s3.sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys = ON');
    return SqlitePersistentStore._(db);
  }

  static final Logger _logger = Logger('conduit');

  s3.Database? _database;
  bool _inTransaction = false;

  @override
  Query<T> newQuery<T extends ManagedObject>(
    ManagedContext context,
    ManagedEntity entity, {
    T? values,
  }) {
    throw UnimplementedError(
      'SqlitePersistentStore.newQuery is not yet implemented. The ORM '
      'query path (predicate construction, joins, returning rows as '
      'ManagedObjects) requires the postgresql package\'s query builders '
      'to be extracted into core; that refactor is tracked separately. '
      'For now, use execute()/executeQuery() with raw SQL for arbitrary '
      'queries against SQLite.',
    );
  }

  @override
  Future<dynamic> execute(
    String sql, {
    Map<String, dynamic>? substitutionValues,
    Duration? timeout,
  }) async {
    final db = _requireOpen();
    final start = DateTime.now();
    try {
      final stmt = db.prepare(sql);
      try {
        final params = _coerceParams(substitutionValues);
        // `selectWith` returns rows for SELECTs and an empty result set
        // for DML/DDL — uniform path means we don't have to sniff the
        // statement kind from the SQL string.
        final result = stmt.selectWith(s3.StatementParameters.named(params));
        _logExecute(sql, substitutionValues, start);
        return result.rows;
      } finally {
        stmt.dispose();
      }
    } on s3.SqliteException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<dynamic> executeQuery(
    String formatString,
    Map<String, dynamic>? values,
    int timeoutInSeconds, {
    PersistentStoreQueryReturnType? returnType =
        PersistentStoreQueryReturnType.rows,
  }) async {
    final db = _requireOpen();
    final start = DateTime.now();
    try {
      final stmt = db.prepare(formatString);
      try {
        final params = _coerceParams(values);
        if (returnType == PersistentStoreQueryReturnType.rows) {
          final result = stmt.selectWith(s3.StatementParameters.named(params));
          _logExecute(formatString, values, start);
          return result.rows;
        }
        stmt.executeWith(s3.StatementParameters.named(params));
        _logExecute(formatString, values, start);
        return db.updatedRows;
      } finally {
        stmt.dispose();
      }
    } on s3.SqliteException catch (e) {
      throw _translate(e);
    }
  }

  /// Coerce a Conduit parameter map into the form sqlite3 expects:
  /// keys prefixed with `:` to match the placeholder in the SQL, and
  /// values unwrapped from any driver-specific typed-value containers.
  ///
  /// Conduit's call sites pass `Map<String, dynamic>` with bare names
  /// (e.g. `{'n': 42}`). The sqlite3 driver looks up parameters via
  /// `sqlite3_bind_parameter_index` using the *full* placeholder name
  /// including its prefix, so `:n` is the lookup key. We add the prefix
  /// here once.
  Map<String, Object?> _coerceParams(Map<String, dynamic>? params) {
    if (params == null) return const {};
    final out = <String, Object?>{};
    for (final entry in params.entries) {
      final key = entry.key.startsWith(':') ? entry.key : ':${entry.key}';
      out[key] = _unwrapDriverValue(entry.value);
    }
    return out;
  }

  Object? _unwrapDriverValue(Object? v) {
    if (v == null) return null;
    // postgres `TypedValue` exposes a `.value` getter; keep this dialect
    // independent of postgres' types by reflecting via dynamic.
    try {
      final dyn = v as dynamic;
      // ignore: avoid_dynamic_calls
      final inner = dyn.value;
      // Avoid recursion if a driver wraps its own `value` getter back
      // into a wrapper — single unwrap is enough for known drivers.
      return inner ?? v;
    } catch (_) {
      return v;
    }
  }

  @override
  Future<T> transaction<T>(
    ManagedContext transactionContext,
    Future<T> Function(ManagedContext transaction) transactionBlock,
  ) async {
    final db = _requireOpen();
    if (_inTransaction) {
      // Use SAVEPOINT for nested transactions. The Postgres backend
      // supports the same semantic via runTx; expose the equivalent.
      final spName = 'sp_${DateTime.now().microsecondsSinceEpoch}';
      db.execute('SAVEPOINT $spName');
      try {
        final result = await transactionBlock(transactionContext);
        db.execute('RELEASE $spName');
        return result;
      } on Rollback {
        db.execute('ROLLBACK TO $spName');
        rethrow;
      } catch (_) {
        db.execute('ROLLBACK TO $spName');
        rethrow;
      }
    }

    _inTransaction = true;
    db.execute('BEGIN');
    try {
      final result = await transactionBlock(transactionContext);
      db.execute('COMMIT');
      return result;
    } on Rollback {
      db.execute('ROLLBACK');
      rethrow;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      _inTransaction = false;
    }
  }

  @override
  Future<int> get schemaVersion async {
    final db = _requireOpen();
    try {
      final rows = db.select(
        "SELECT versionNumber, dateOfUpgrade "
        "FROM $versionTableName ORDER BY dateOfUpgrade ASC",
      );
      if (rows.isEmpty) return 0;
      return rows.last['versionNumber'] as int;
    } on s3.SqliteException catch (e) {
      // SQLite returns "no such table" with code 1 + extended messaging.
      if (e.message.contains('no such table')) {
        return 0;
      }
      rethrow;
    }
  }

  @override
  Future<Schema> upgrade(
    Schema fromSchema,
    List<Migration> withMigrations, {
    bool temporary = false,
  }) async {
    final db = _requireOpen();
    Schema schema = fromSchema;

    db.execute('BEGIN');
    try {
      await _createVersionTableIfNecessary(temporary);

      withMigrations.sort((m1, m2) => m1.version!.compareTo(m2.version!));

      for (final migration in withMigrations) {
        migration.database = SchemaBuilder(
          this,
          schema,
          isTemporary: temporary,
        );
        migration.database.store = this;

        final existing = db.select(
          "SELECT versionNumber, dateOfUpgrade FROM $versionTableName "
          "WHERE versionNumber >= ?",
          [migration.version],
        );
        if (existing.isNotEmpty) {
          final date = existing.first['dateOfUpgrade'];
          throw MigrationException(
            'Trying to upgrade database to version ${migration.version}, '
            'but that migration has already been performed on $date.',
          );
        }

        _logger.info('Applying migration version ${migration.version}...');
        await migration.upgrade();

        for (final cmd in migration.database.commands) {
          _logger.info('\t$cmd');
          db.execute(cmd);
        }

        _logger.info(
          'Seeding data from migration version ${migration.version}...',
        );
        await migration.seed();

        db.execute(
          "INSERT INTO $versionTableName (versionNumber, dateOfUpgrade) "
          "VALUES (${migration.version}, "
          "'${DateTime.now().toUtc().toIso8601String()}')",
        );

        _logger.info(
          'Applied schema version ${migration.version} successfully.',
        );

        schema = migration.currentSchema;
      }

      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }

    return schema;
  }

  @override
  Future close() async {
    _database?.dispose();
    _database = null;
  }

  // -- internals -------------------------------------------------------------

  s3.Database _requireOpen() {
    final db = _database;
    if (db == null) {
      throw QueryException.transport(
        'SqlitePersistentStore is closed; cannot execute queries.',
      );
    }
    return db;
  }

  Future _createVersionTableIfNecessary(bool temporary) async {
    final db = _requireOpen();
    final tbl = versionTable;
    final commands = createTable(tbl, isTemporary: temporary);
    final exists = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      [tbl.name],
    );
    if (exists.isNotEmpty) return;

    _logger.info('Initializing database...');
    for (final cmd in commands) {
      _logger.info('\t$cmd');
      db.execute(cmd);
    }
  }

  /// Translate a SQLite driver exception into one of conduit's standard
  /// `QueryException` kinds. SQLite's primary error codes overlap with
  /// extended codes (e.g. SQLITE_CONSTRAINT_UNIQUE = 19 + 8). We
  /// pattern-match the message because the extended-code surface is the
  /// most stable identifier across versions.
  QueryException<s3.SqliteException> _translate(s3.SqliteException e) {
    final msg = e.message;
    if (msg.contains('UNIQUE constraint failed')) {
      return QueryException.conflict(
        'entity_already_exists',
        [_extractConstraintTarget(msg)],
        underlyingException: e,
      );
    }
    if (msg.contains('NOT NULL constraint failed')) {
      return QueryException.input(
        'non_null_violation',
        [_extractConstraintTarget(msg)],
        underlyingException: e,
      );
    }
    if (msg.contains('FOREIGN KEY constraint failed')) {
      return QueryException.input(
        'foreign_key_violation',
        const [],
        underlyingException: e,
      );
    }
    return QueryException.transport(msg, underlyingException: e);
  }

  String _extractConstraintTarget(String msg) {
    // Messages look like: "UNIQUE constraint failed: users.email"
    // or "NOT NULL constraint failed: users.name"
    final colonIdx = msg.indexOf(': ');
    if (colonIdx == -1) return msg;
    return msg.substring(colonIdx + 2).trim();
  }

  void _logExecute(String sql, Object? params, DateTime start) {
    _logger.fine(() {
      final dt = DateTime.now().difference(start).inMilliseconds;
      return 'Query (${dt}ms) $sql ${params ?? '{}'}';
    });
  }
}
