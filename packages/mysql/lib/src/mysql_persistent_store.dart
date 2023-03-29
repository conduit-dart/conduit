import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit_core/conduit_core.dart';
import 'package:mysql_client/exception.dart';
import 'package:mysql_client/mysql_client.dart';

import 'mysql_schema_generator.dart';
import 'mysql_query.dart';

/// The database layer responsible for carrying out [Query]s against MySql databases.
///
/// To interact with a MySql database, a [ManagedContext] must have an instance of this class.
/// Instances of this class are configured to connect to a particular MySql database.
class MySqlPersistentStore extends PersistentStore with MySqlSchemaGenerator {
  /// Creates an instance of this type from connection info.
  MySqlPersistentStore(
    this.username,
    this.password,
    this.host,
    this.port,
    this.databaseName, {
    bool useSSL = true,
  }) : isSSLConnection = useSSL;

  /// Same constructor as default constructor.
  ///
  /// Kept for backwards compatability.
  MySqlPersistentStore.fromConnectionInfo(
    this.username,
    this.password,
    this.host,
    this.port,
    this.databaseName, {
    bool useSSL = false,
  }) : isSSLConnection = useSSL;

  MySqlPersistentStore._from(MySqlPersistentStore from)
      : isSSLConnection = from.isSSLConnection,
        username = from.username,
        password = from.password,
        host = from.host,
        port = from.port,
        databaseName = from.databaseName;

  /// The logger used by instances of this class.
  static Logger logger = Logger("conduit");

  /// The username of the database user for the database this instance connects to.
  final String? username;

  /// The password of the database user for the database this instance connects to.
  final String? password;

  /// The host of the database this instance connects to.
  final String? host;

  /// The port of the database this instance connects to.
  final int? port;

  /// The name of the database this instance connects to.
  final String? databaseName;

  /// Whether this connection is established over SSL.
  final bool isSSLConnection;

  /// Amount of time to wait before connection fails to open.
  ///
  /// Defaults to 30 seconds.
  final Duration connectTimeout = const Duration(seconds: 30);

  static final Finalizer<MySQLConnectionPool> _finalizer =
      Finalizer((connection) => connection.close());

  MySQLConnectionPool? _databaseConnectionPool;
  MySQLConnection? _singleThread;
  Completer<MySQLConnectionPool>? _pendingConnectionCompleter;

  /// Retrieves a connection to the database this instance connects to.
  ///
  /// If no connection exists, one will be created. A store will have no more than one connection at a time.
  ///
  /// When executing queries, prefer to use [executionContext] instead. Failure to do so might result
  /// in issues when executing queries during a transaction.
  Future<MySQLConnectionPool> getDatabaseConnectionPool() async {
    if (_databaseConnectionPool == null) {
      if (_pendingConnectionCompleter == null) {
        _pendingConnectionCompleter = Completer<MySQLConnectionPool>();

        _connect().timeout(connectTimeout).then((pool) {
          _databaseConnectionPool = pool;
          _pendingConnectionCompleter!.complete(_databaseConnectionPool);
          _pendingConnectionCompleter = null;
          _finalizer.attach(this, _databaseConnectionPool!, detach: this);
        }).catchError((e) {
          _pendingConnectionCompleter!.completeError(
            QueryException.transport(
              "unable to connect to database",
              underlyingException: e,
            ),
          );
          _pendingConnectionCompleter = null;
        });
      }

      return _pendingConnectionCompleter!.future;
    }

    return _databaseConnectionPool!;
  }

  Future<MySQLConnection> _getPersistentThread() async {
    if (_databaseConnectionPool == null) {
      await getDatabaseConnectionPool()
          .then((pool) => pool.withConnection((conn) {
                _singleThread = conn;
              }));
    } else if (_singleThread == null) {
      await _databaseConnectionPool!.withConnection((conn) {
        _singleThread = conn;
      });
    }
    return _singleThread!;
  }

  @override
  Query<T> newQuery<T extends ManagedObject>(
    ManagedContext context,
    ManagedEntity entity, {
    T? values,
  }) {
    final query = MySqlQuery<T>.withEntity(context, entity);
    if (values != null) {
      query.values = values;
    }
    return query;
  }

  @override
  Future<dynamic> execute(
    String sql, {
    Map<String, dynamic>? substitutionValues,
    Duration? timeout,
  }) async {
    timeout ??= const Duration(seconds: 30);
    final now = DateTime.now().toUtc();
    try {
      final conn = await _getPersistentThread();
      substitutionValues?.updateAll((_, v) {
        if (v is Map || v is List) {
          return jsonEncode(v);
        }
        return v;
      });
      final result = await conn.execute(
        sql,
        substitutionValues,
      );

      final mappedRows = result.rows.map((row) => row.typedAssoc()).toList();
      logger.finest(
        () =>
            "Query:execute (${DateTime.now().toUtc().difference(now).inMilliseconds}ms) $sql -> $mappedRows",
      );
      return mappedRows;
    } on MySQLServerException catch (e) {
      final interpreted = _interpretException(e);
      if (interpreted != null) {
        throw interpreted;
      }

      rethrow;
    } on SocketException catch (e) {
      throw QueryException.transport(e.message);
    }
  }

  @override
  Future close() async {
    _finalizer.detach(this);
    _databaseConnectionPool = null;
  }

  @override
  Future<T?> transaction<T>(
    ManagedContext transactionContext,
    Future<T?> Function(ManagedContext transaction) transactionBlock,
  ) async {
    final dbConnection = await getDatabaseConnectionPool();

    T? output;
    Rollback? rollback;
    try {
      await dbConnection.transactional((dbTransactionContext) async {
        transactionContext.persistentStore = _TransactionProxy(
          this,
          dbTransactionContext,
        );

        try {
          output = await transactionBlock(transactionContext);
        } on Rollback catch (e) {
          /// user triggered a manual rollback.
          /// TODO: there is currently no reliable way for a user to detect
          /// that a manual rollback occured.
          /// The documented method of checking the return value from this method
          /// does not work.
          rollback = e;
          dbTransactionContext.close();
        }
      });
    } on MySQLServerException catch (e) {
      final interpreted = _interpretException(e);
      if (interpreted != null) {
        throw interpreted;
      }

      rethrow;
    }

    if (rollback != null) {
      throw rollback!;
    }

    return output;
  }

  @override
  Future<int> get schemaVersion async {
    try {
      final values = await execute(
        "SELECT versionNumber, dateOfUpgrade FROM $versionTableName ORDER BY dateOfUpgrade ASC",
      ) as List<Map<String, dynamic>>;
      if (values.isEmpty) {
        return 0;
      }

      return values.last['versionNumber']!;
    } on MySQLServerException catch (e) {
      if (e.errorCode == 1146) {
        return 0;
      }
      rethrow;
    }
  }

  @override
  Future<Schema?> upgrade(
    Schema? fromSchema,
    List<Migration> withMigrations, {
    bool temporary = false,
  }) async {
    final connection = await getDatabaseConnectionPool();

    Schema? schema = fromSchema;

    await connection.transactional((ctx) async {
      final transactionStore = _TransactionProxy(this, ctx);
      await _createVersionTableIfNecessary(ctx, temporary);

      withMigrations.sort((m1, m2) => m1.version!.compareTo(m2.version!));

      for (final migration in withMigrations) {
        migration.database =
            SchemaBuilder(transactionStore, schema, isTemporary: temporary);
        migration.database.store = transactionStore;

        final prepared = await ctx.prepare(
          "SELECT versionNumber, dateOfUpgrade FROM $versionTableName WHERE versionNumber >= ?",
        );
        final existingVersionRows = await prepared.execute([migration.version]);
        if (existingVersionRows.rows.isNotEmpty) {
          final date = existingVersionRows.rows.last;
          throw MigrationException(
            "Trying to upgrade database to version ${migration.version}, but that migration has already been performed on $date.",
          );
        }

        logger.info("Applying migration version ${migration.version}...");
        await migration.upgrade();

        for (final cmd in migration.database.commands) {
          logger.info("\t$cmd");
          await ctx.execute(cmd);
        }

        logger.info(
          "Seeding data from migration version ${migration.version}...",
        );
        await migration.seed();
        await ctx.execute(
          "INSERT INTO $versionTableName (versionNumber, dateOfUpgrade) VALUES (${migration.version}, NOW())",
        );

        logger
            .info("Applied schema version ${migration.version} successfully.");

        schema = migration.currentSchema;
      }
    });

    return schema;
  }

  @override
  Future<dynamic> executeQuery(
    String formatString,
    Map<String, dynamic> values,
    int timeoutInSeconds, {
    PersistentStoreQueryReturnType? returnType =
        PersistentStoreQueryReturnType.rows,
  }) async {
    final now = DateTime.now().toUtc();
    try {
      var pool = await getDatabaseConnectionPool();
      values.updateAll((_, v) {
        if (v is Map || v is List) {
          return jsonEncode(v);
        }
        return v;
      });
      MySQLConnection? conn;
      try {
        conn = await pool.withConnection((conn) => conn);
      } catch (_) {
        _databaseConnectionPool = null;
        pool = await getDatabaseConnectionPool();
      }
      while (conn == null || !conn.connected) {
        conn = await pool.withConnection((conn) => conn);
      }

      final IResultSet results = await conn.execute(formatString, values);
      logger.fine(
        () =>
            "Query (${DateTime.now().toUtc().difference(now).inMilliseconds}ms) $formatString Substitutes: $values -> $results",
      );
      return results;
    } on SocketException catch (e) {
      throw QueryException.transport(
        e.message,
        underlyingException: e,
      );
    } on TimeoutException catch (e) {
      throw QueryException.transport(
        "timed out connection to database",
        underlyingException: e,
      );
    } on MySQLServerException catch (e) {
      logger.fine(
        () =>
            "Query (${DateTime.now().toUtc().difference(now).inMilliseconds}ms) $formatString $values",
      );
      logger.warning(e.toString);
      final interpreted = _interpretException(e);
      if (interpreted != null) {
        throw interpreted;
      }

      rethrow;
    }
  }

  QueryException<MySQLServerException>? _interpretException(
    MySQLServerException exception,
  ) {
    switch (exception.errorCode) {
      case 1050:
      case 1062:
      case 1136:
      case 1169:
      case 3730:
        return QueryException.conflict(
          exception.message,
          [],
          underlyingException: exception,
        );
      case 1044:
      case 1048:
      case 1170:
        return QueryException.input(
          exception.message,
          [],
          underlyingException: exception,
        );
    }

    return null;
  }

  Future _createVersionTableIfNecessary(
    MySQLConnection context,
    bool temporary,
  ) async {
    final table = versionTable;
    final commands = createTable(table, isTemporary: temporary);
    final exists = await context.execute(
      """SELECT COUNT(*)
        FROM information_schema.tables
        WHERE table_schema = 'databaseName' AND table_name = 'tableName';""",
      {"tableName": table.name, 'databaseName': databaseName},
    );

    if (exists.rows.isEmpty) {
      return;
    }

    logger.info("Initializating database...");
    try {
      for (final cmd in commands) {
        logger.info("\t$cmd");
        await context.execute(cmd);
      }
    } on MySQLServerException catch (e) {
      if (e.errorCode == 1050) {
        return;
      }
      rethrow;
    }
  }

  Future<MySQLConnectionPool> _connect() async {
    logger.info("MySql connecting, $username@$host:$port/$databaseName.");

    return MySQLConnectionPool(
      host: host!,
      port: port!,
      databaseName: databaseName,
      userName: username!,
      password: password,
      secure: isSSLConnection,
      maxConnections: 100,
    );
  }
}

// TODO: Either PR for mysql1 package or create error code table here
// class MySqlErrorCode {
//   static const String duplicateTable = "42P07";
//   static const String undefinedTable = "42P01";
//   static const String undefinedColumn = "42703";
//   static const String uniqueViolation = "23505";
//   static const String notNullViolation = "23502";
//   static const String foreignKeyViolation = "23503";
// }

class _TransactionProxy extends MySqlPersistentStore {
  _TransactionProxy(this.parent, this.context) : super._from(parent);

  final MySqlPersistentStore parent;
  final MySQLConnection context;
}
