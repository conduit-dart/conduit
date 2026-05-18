import 'dart:io';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_postgresql/conduit_postgresql.dart';

/// Default configuration used by unit tests to connect to the test
/// Postgres instance.
///
/// Resolution order per setting:
///   1. Environment variable (`POSTGRES_HOST`, `POSTGRES_PORT`,
///      `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`).
///   2. Default matching `ci/docker-compose.yaml` — bring it up with
///      `docker compose -f ci/docker-compose.yaml up -d`.
class PostgresTestConfig {
  factory PostgresTestConfig() => _self;

  PostgresTestConfig._internal();

  static final PostgresTestConfig _self = PostgresTestConfig._internal();

  static const String _defaultHost = 'localhost';
  static const int _defaultPort = 15432;
  static const String _defaultUsername = 'conduit_test_user';
  static const String _defaultPassword = 'conduit!';
  static const String _defaultDbName = 'conduit_test_db';

  String get connectionUrl =>
      "postgres://$username:$password@$host:$port/$dbName";

  /// Returns a [PostgreSQLPersistentStore] that has been initialised
  /// using the  db settings configured via .settings.yaml
  /// You can override all of some of these settings by passing
  /// in a non-null value to any of the named arguments.
  PostgreSQLPersistentStore persistentStore(
      {String? username,
      String? password,
      String? host,
      int? port,
      String? dbName}) {
    username ??= this.username;
    password ??= this.password;
    host ??= this.host;
    port ??= this.port;
    dbName ??= this.dbName;

    return PostgreSQLPersistentStore(username, password, host, port, dbName);
  }

  DatabaseConfiguration databaseConfiguration() =>
      DatabaseConfiguration.withConnectionInfo(
          username, password, host, port, dbName);

  Future<ManagedContext> contextWithModels(List<Type> instanceTypes) async {
    final persistentStore =
        PostgreSQLPersistentStore(username, password, host, port, dbName);

    final dataModel = ManagedDataModel(instanceTypes);
    final commands = commandsFromDataModel(dataModel, temporary: true);
    final context = ManagedContext(dataModel, persistentStore);

    for (var cmd in commands) {
      await persistentStore.execute(cmd);
    }

    return context;
  }

  List<String> commandsFromDataModel(ManagedDataModel dataModel,
      {bool temporary = false}) {
    final targetSchema = Schema.fromDataModel(dataModel);
    final builder = SchemaBuilder.toSchema(
        PostgreSQLPersistentStore(null, null, null, port, null), targetSchema,
        isTemporary: temporary);
    return builder.commands;
  }

  List<String> commandsForModelInstanceTypes(List<Type> instanceTypes,
      {bool temporary = false}) {
    final dataModel = ManagedDataModel(instanceTypes);
    return commandsFromDataModel(dataModel, temporary: temporary);
  }

  Future dropSchemaTables(Schema schema, PersistentStore store) async {
    final tables = List<SchemaTable>.from(schema.tables);
    while (tables.isNotEmpty) {
      try {
        await store.execute("DROP TABLE IF EXISTS ${tables.last.name}");
        tables.removeLast();
      } catch (_) {
        tables.insert(0, tables.removeLast());
      }
    }
  }

  int? _port;
  int get port {
    if (_port != null) return _port!;
    final raw = Platform.environment['POSTGRES_PORT']?.trim();
    if (raw == null || raw.isEmpty) return _port = _defaultPort;
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      throw ArgumentError(
          'POSTGRES_PORT must be an integer; got "$raw"');
    }
    return _port = parsed;
  }

  String? _host;
  String get host => _host ??= _envOr('POSTGRES_HOST', _defaultHost);

  String? _username;
  String get username =>
      _username ??= _envOr('POSTGRES_USER', _defaultUsername);

  String? _password;
  String get password =>
      _password ??= _envOr('POSTGRES_PASSWORD', _defaultPassword);

  String? _dbName;
  String get dbName => _dbName ??= _envOr('POSTGRES_DB', _defaultDbName);

  static String _envOr(String key, String fallback) {
    final value = Platform.environment[key]?.trim();
    if (value == null || value.isEmpty) return fallback;
    return value;
  }
}
