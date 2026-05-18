import 'dart:async';

import 'package:conduit_core/conduit_core.dart';
import 'package:mysql_dart/exception.dart' as mx;
import 'package:mysql_dart/mysql_dart.dart' as md;

import 'mysql_query.dart';
import 'mysql_schema_generator.dart';

/// MySQL / MariaDB-backed `PersistentStore`.
///
/// Schema management, raw `execute`/`executeQuery`/`transaction`, and
/// the full ORM `newQuery<T>` path are all wired up — the latter
/// piggybacks on the dialect-agnostic `QueryBuilder` family lifted
/// out of `conduit_postgresql`.
///
/// Driver: `mysql_dart` 1.2.1 (native Dart, MySQL 5.7/8 + MariaDB
/// 10/11 tested). The driver accepts both `:name` and positional `?`
/// placeholders. The QueryBuilder path emits `:name` (driver
/// internally rewrites to positional); the predicate AST visitor
/// emits positional `?` directly when called via
/// `SqlDialect.renderExpression`.
class MysqlPersistentStore extends PersistentStore with MysqlSchemaGenerator {
  MysqlPersistentStore(
    this.username,
    this.password,
    this.host,
    this.port,
    this.databaseName, {
    this.secure = false,
    this.timeZone = '+00:00',
  });

  /// Same shape as the Postgres store's `fromConnectionInfo` — kept
  /// for API parity / future migrations of code that switches
  /// backends.
  MysqlPersistentStore.fromConnectionInfo(
    this.username,
    this.password,
    this.host,
    this.port,
    this.databaseName, {
    this.secure = false,
    this.timeZone = '+00:00',
  });

  static final Logger _logger = Logger('conduit');

  final String username;
  final String password;
  final String host;
  final int port;
  final String databaseName;

  /// Whether to enable TLS. The driver defaults to `secure: true`,
  /// but local-dev MySQL boxes rarely have a cert configured. We
  /// flip the default off here so the developer experience matches
  /// the Postgres store (which defaults to `sslMode: disable`); set
  /// to `true` for production.
  final bool secure;

  /// Time zone passed to the connection. `+00:00` matches the
  /// Postgres store's UTC default.
  final String timeZone;

  md.MySQLConnection? _connection;
  bool _inTransaction = false;
  bool _mariadb = false;

  /// `true` if the server returned a MariaDB version string at
  /// connect time. Currently exposed for caller diagnostics; the
  /// dialect doesn't diverge between MySQL and MariaDB at this
  /// version.
  bool get isMariaDB => _mariadb;

  /// Connection state.
  bool get isConnected => _connection?.connected ?? false;

  Future<md.MySQLConnection> _ensureConnected() async {
    final existing = _connection;
    if (existing != null && existing.connected) {
      return existing;
    }
    try {
      final conn = await md.MySQLConnection.createConnection(
        host: host,
        port: port,
        userName: username,
        password: password,
        databaseName: databaseName,
        secure: secure,
      );
      await conn.connect();
      // Best-effort time-zone alignment so DATETIME literals round-trip
      // in UTC. MySQL accepts `SET time_zone = '+00:00'`; older MariaDB
      // builds do too. Failure here is non-fatal.
      try {
        await conn.execute("SET time_zone = '$timeZone'");
      } catch (e) {
        _logger.fine('time_zone set failed (non-fatal): $e');
      }
      // Detect MariaDB once. Used by callers; not used by the dialect.
      try {
        final res = await conn.execute('SELECT VERSION() AS v');
        final row = res.rows.isNotEmpty ? res.rows.first : null;
        final version = row?.colAt(0) ?? '';
        _mariadb = version.toLowerCase().contains('mariadb');
      } catch (_) {
        _mariadb = false;
      }
      _connection = conn;
      return conn;
    } catch (e) {
      throw QueryException.transport(
        'unable to connect to mysql',
        underlyingException: e,
      );
    }
  }

  @override
  Query<T> newQuery<T extends ManagedObject>(
    ManagedContext context,
    ManagedEntity entity, {
    T? values,
  }) {
    return mysqlNewQuery<T>(context, entity, values: values);
  }

  /// Coerce a Conduit-style parameter map into the form mysql_dart
  /// expects. The framework emits maps like `{'foo': 1, 'bar': 2}`
  /// (no leading punctuation) — the driver accepts this for `:name`
  /// placeholders directly. For positional `?` placeholders the
  /// driver wants a `List`. Callers of [executeQuery] supply a map
  /// (the legacy shape); this method converts based on whether the
  /// SQL contains `?` or `:` placeholders.
  ///
  /// In v0 the schema-management path uses positional `?` exclusively
  /// (the dialect's `parameterPlaceholder`), so the conversion is
  /// always `Map → List` ordered by first-appearance in the SQL. We
  /// also strip the postgres `TypedValue` wrapper if present — the
  /// driver doesn't recognize it.
  Object? _coerceParams(String sql, Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) {
      // Driver accepts `null` for parameter-less SQL.
      return null;
    }
    if (sql.contains('?')) {
      // Positional path: caller supplied a map keyed by name. Build
      // the positional list by walking the SQL and pulling values
      // from the map in order. If a placeholder doesn't have a
      // matching key we fall back to inserting `null` rather than
      // failing — the bind will error downstream with a clearer
      // mismatch message.
      //
      // In practice the framework's predicate AST renders directly
      // to a positional list (see `RenderedExpression
      // .positionalParameters`); the only callers reaching this
      // branch are the schema-management code paths that construct
      // `Map<String, dynamic>` for the version-table existence check
      // and similar one-off queries.
      final out = <Object?>[];
      // Preserve insertion order — which is the natural order for
      // the schema-management paths.
      for (final entry in params.entries) {
        out.add(_unwrap(entry.value));
      }
      return out;
    }
    // Named-parameter path (`:name`).
    final out = <String, Object?>{};
    for (final entry in params.entries) {
      out[entry.key] = _unwrap(entry.value);
    }
    return out;
  }

  /// Strip a postgres `TypedValue` wrapper if the caller passed one
  /// in (legacy code path). Not used in MySQL-only code, but the
  /// schema-management flow goes through dialect-shared helpers that
  /// historically returned TypedValue.
  Object? _unwrap(Object? v) {
    if (v == null) return null;
    try {
      final dyn = v as dynamic;
      // ignore: avoid_dynamic_calls
      final inner = dyn.value;
      return inner ?? v;
    } catch (_) {
      return v;
    }
  }

  @override
  Future<dynamic> execute(
    String sql, {
    Map<String, dynamic>? substitutionValues,
    Duration? timeout,
  }) async {
    final conn = await _ensureConnected();
    final start = DateTime.now();
    try {
      final coerced = _coerceParams(sql, substitutionValues);
      final result = await _executeOn(conn, sql, coerced);
      _logExecute(sql, substitutionValues, start);
      // Match the Postgres `execute` return shape: a list of rows,
      // each as a `List<Object?>`.
      return _materializeRows(result);
    } on mx.MySQLServerException catch (e) {
      throw _translate(e, sql);
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
    final conn = await _ensureConnected();
    final start = DateTime.now();
    try {
      final coerced = _coerceParams(formatString, values);
      final result = await _executeOn(conn, formatString, coerced);
      _logExecute(formatString, values, start);
      if (returnType == PersistentStoreQueryReturnType.rows) {
        return _materializeRows(result);
      }
      return result.affectedRows.toInt();
    } on mx.MySQLServerException catch (e) {
      throw _translate(e, formatString);
    }
  }

  Future<md.IResultSet> _executeOn(
    md.MySQLConnection conn,
    String sql,
    Object? params,
  ) async {
    if (params == null) {
      return conn.execute(sql);
    }
    return conn.execute(sql, params);
  }

  /// Materialize a mysql_dart result into the
  /// `List<List<Object?>>` shape Conduit's row instantiator expects.
  ///
  /// MySQL's text-protocol result set returns every value as a String
  /// (even integers and timestamps); the row instantiator's
  /// validators will reject e.g. `'42'` as the value of an `int`
  /// column. We convert per-column based on the column-type metadata
  /// the driver exposes via `cols`. The mapping mirrors mysql_dart's
  /// own `typedAssoc()` helper (private to a row, not the result
  /// set), but works at result-set scope so it costs only one column
  /// metadata walk per result.
  List<List<Object?>> _materializeRows(md.IResultSet result) {
    final cols = result.cols.toList();
    final converters = cols.map(_converterForColumn).toList();
    final out = <List<Object?>>[];
    for (final row in result.rows) {
      final values = <Object?>[];
      for (var i = 0; i < row.numOfColumns; i++) {
        values.add(converters[i](row.colAt(i)));
      }
      out.add(values);
    }
    return out;
  }

  /// Returns a function that coerces a mysql_dart raw column value
  /// (always a String for the text protocol) into the Dart type
  /// Conduit's row instantiator expects for that column. Falls back
  /// to identity for column types without a typed mapping.
  ///
  /// `MySQLColumnType` does not override `operator ==`, so we
  /// compare on `.intVal` rather than the const instance. The
  /// numeric codes are the wire-protocol field-type bytes — they're
  /// fixed by the MySQL spec, so comparing raw codes is just as
  /// stable as the named constants.
  Object? Function(Object?) _converterForColumn(md.ResultSetColumn col) {
    final code = col.type.intVal;
    // Integer column codes: TINY (1), SHORT (2), LONG (3), LONGLONG (8),
    // INT24 (9), YEAR (13). BOOLEAN is TINYINT(1) — encoded as TINY here;
    // Conduit binds bool ↔ INTEGER 0/1 anyway.
    if (code == 1 || code == 2 || code == 3 || code == 8 ||
        code == 9 || code == 13) {
      return (v) => v == null ? null : int.parse(v.toString());
    }
    // FLOAT (4), DOUBLE (5).
    if (code == 4 || code == 5) {
      return (v) => v == null ? null : double.parse(v.toString());
    }
    // DECIMAL (0), NEW_DECIMAL (0xf6).
    if (code == 0 || code == 0xf6) {
      return (v) => v == null ? null : num.parse(v.toString());
    }
    // DATETIME (0x0c), DATETIME2 (0x12), TIMESTAMP (0x07),
    // TIMESTAMP2 (0x11), DATE (0x0a), NEW_DATE (0x0e).
    if (code == 0x0c || code == 0x12 || code == 0x07 ||
        code == 0x11 || code == 0x0a || code == 0x0e) {
      return (v) {
        if (v == null) return null;
        final s = v.toString().replaceFirst(' ', 'T');
        return DateTime.parse(s);
      };
    }
    return (v) => v;
  }

  @override
  Future<T> transaction<T>(
    ManagedContext transactionContext,
    Future<T> Function(ManagedContext transaction) transactionBlock,
  ) async {
    final conn = await _ensureConnected();
    if (_inTransaction) {
      // Nested transactions via SAVEPOINT to mirror the Postgres /
      // SQLite stores' semantics. MySQL supports SAVEPOINT in InnoDB.
      final spName = 'sp_${DateTime.now().microsecondsSinceEpoch}';
      await conn.execute('SAVEPOINT $spName');
      try {
        final result = await transactionBlock(transactionContext);
        await conn.execute('RELEASE SAVEPOINT $spName');
        return result;
      } on Rollback {
        await conn.execute('ROLLBACK TO SAVEPOINT $spName');
        rethrow;
      } catch (_) {
        await conn.execute('ROLLBACK TO SAVEPOINT $spName');
        rethrow;
      }
    }

    _inTransaction = true;
    try {
      // mysql_dart's `transactional()` would be cleaner, but it
      // re-binds the connection passed to the block, which our
      // `transactionBlock` signature can't see. Drive BEGIN/COMMIT
      // manually so the same connection (and any saved state) is
      // available to nested calls.
      await conn.execute('START TRANSACTION');
      try {
        final result = await transactionBlock(transactionContext);
        await conn.execute('COMMIT');
        return result;
      } on Rollback {
        await conn.execute('ROLLBACK');
        rethrow;
      } catch (_) {
        await conn.execute('ROLLBACK');
        rethrow;
      }
    } finally {
      _inTransaction = false;
    }
  }

  @override
  Future<int> get schemaVersion async {
    try {
      final conn = await _ensureConnected();
      final res = await conn.execute(
        'SELECT versionNumber, dateOfUpgrade FROM $versionTableName '
        'ORDER BY dateOfUpgrade ASC',
      );
      if (res.rows.isEmpty) return 0;
      final last = res.rows.last;
      // typedColAt may return Decimal/Number/etc; the version column
      // is INTEGER so a parse round-trip is safe.
      final raw = last.colAt(0);
      if (raw == null) return 0;
      return int.parse(raw);
    } on mx.MySQLServerException catch (e) {
      // MySQL error 1146 = "Table doesn't exist". Pre-create runs
      // legitimately hit this; treat as version 0.
      if (e.errorCode == 1146 ||
          e.message.toLowerCase().contains("doesn't exist")) {
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
    final conn = await _ensureConnected();
    Schema schema = fromSchema;

    await conn.execute('START TRANSACTION');
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

        final existing = await conn.execute(
          'SELECT versionNumber, dateOfUpgrade FROM $versionTableName '
          'WHERE versionNumber >= ?',
          [migration.version],
        );
        if (existing.rows.isNotEmpty) {
          final date = existing.rows.first.colAt(1);
          throw MigrationException(
            'Trying to upgrade database to version ${migration.version}, '
            'but that migration has already been performed on $date.',
          );
        }

        _logger.info('Applying migration version ${migration.version}...');
        await migration.upgrade();

        for (final cmd in migration.database.commands) {
          _logger.info('\t$cmd');
          await conn.execute(cmd);
        }

        _logger.info(
          'Seeding data from migration version ${migration.version}...',
        );
        await migration.seed();

        await conn.execute(
          'INSERT INTO $versionTableName (versionNumber, dateOfUpgrade) '
          "VALUES (${migration.version}, '${DateTime.now().toUtc().toIso8601String()}')",
        );

        _logger.info(
          'Applied schema version ${migration.version} successfully.',
        );

        schema = migration.currentSchema;
      }

      await conn.execute('COMMIT');
    } catch (_) {
      await conn.execute('ROLLBACK');
      rethrow;
    }

    return schema;
  }

  @override
  Future close() async {
    final conn = _connection;
    if (conn != null && conn.connected) {
      await conn.close();
    }
    _connection = null;
  }

  Future<void> _createVersionTableIfNecessary(bool temporary) async {
    final conn = await _ensureConnected();
    final tbl = versionTable;
    final commands = createTable(tbl, isTemporary: temporary);
    final exists = await conn.execute(
      dialect.tableExistsQuery(),
      {'tableName': tbl.name},
    );
    if (exists.rows.isNotEmpty) return;

    _logger.info('Initializing database...');
    for (final cmd in commands) {
      _logger.info('\t$cmd');
      await conn.execute(cmd);
    }
  }

  /// Translate a mysql_dart driver exception into one of conduit's
  /// standard `QueryException` kinds. MySQL primary error codes are
  /// well-defined; we pattern-match on the well-known ones (duplicate
  /// key = 1062, foreign-key violation = 1452, NOT NULL violation =
  /// 1048).
  QueryException<mx.MySQLServerException> _translate(
    mx.MySQLServerException e,
    String sql,
  ) {
    final code = e.errorCode;
    if (code == 1062) {
      return QueryException.conflict(
        'entity_already_exists',
        const [],
        underlyingException: e,
      );
    }
    if (code == 1048) {
      return QueryException.input(
        'non_null_violation',
        const [],
        underlyingException: e,
      );
    }
    if (code == 1451 || code == 1452) {
      return QueryException.input(
        'foreign_key_violation',
        const [],
        underlyingException: e,
      );
    }
    return QueryException.transport(e.message, underlyingException: e);
  }

  void _logExecute(String sql, Object? params, DateTime start) {
    _logger.fine(() {
      final dt = DateTime.now().difference(start).inMilliseconds;
      return 'Query (${dt}ms) $sql ${params ?? '{}'}';
    });
  }
}
