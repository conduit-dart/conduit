import 'dart:io';

import 'package:conduit/conduit.dart';

/// This class is used to define the default configuration use
/// by Unit Tests to connect to the postgres db.
///
/// We assume the user has setup their test environment using the provider
/// tool/docker-compose.yml file which creates a docker service on an alternate
/// port: 5432
class PostgresTestConfig {
  factory PostgresTestConfig() => _self;

  PostgresTestConfig._internal();

  static late final PostgresTestConfig _self = PostgresTestConfig._internal();

  static const defaultHost = 'localhost';
  static const defaultPort = 5432;
  static const defaultUsername = 'dart';
  static const defaultPassword = 'dart';
  static const defaultDbName = 'dart_test';

  String get connectionUrl =>
      "postgres://$username:$password@$host:$port/$dbName";

  PostgreSQLPersistentStore persistentStore() =>
      PostgreSQLPersistentStore(username, password, host, port, dbName);

  DatabaseConfiguration databaseConfiguration() =>
      DatabaseConfiguration.withConnectionInfo(
          username, password, host, port, dbName);

  Future<ManagedContext> contextWithModels(List<Type> instanceTypes) async {
    var persistentStore =
        PostgreSQLPersistentStore(username, password, host, port, dbName);

    var dataModel = ManagedDataModel(instanceTypes);
    var commands = commandsFromDataModel(dataModel, temporary: true);
    var context = ManagedContext(dataModel, persistentStore);

    for (var cmd in commands) {
      await persistentStore.execute(cmd);
    }

    return context;
  }

  List<String> commandsFromDataModel(ManagedDataModel dataModel,
      {bool temporary = false}) {
    var targetSchema = Schema.fromDataModel(dataModel);
    var builder = SchemaBuilder.toSchema(
        PostgreSQLPersistentStore(null, null, null, 5432, null), targetSchema,
        isTemporary: temporary);
    return builder.commands;
  }

  List<String> commandsForModelInstanceTypes(List<Type> instanceTypes,
      {bool temporary = false}) {
    var dataModel = ManagedDataModel(instanceTypes);
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
    if (_port == null) {
      /// Check for an environment variable.
      const _key = 'PSQL_PORT';
      if (Platform.environment.containsKey(_key)) {
        var value = Platform.environment[_key];
        if (value != null) {
          _port = int.tryParse(value);
        }
        if (_port == null) {
          throw ArgumentError(
              "The Environment Variable $_key does not contain a valid integer. Found: $value");
        }
      } else {
        _port = defaultPort;
      }
    }
    return _port!;
  }

  String? _host;
  String get host => _host ??= _initialise('PSQL_HOST', defaultHost);

  String? _username;
  String get username =>
      _username ??= _initialise('PSQL_USERNAME', defaultUsername);

  String? _password;
  String get password =>
      _password ??= _initialise('PSQL_PASSWORD', defaultPassword);

  String? _dbName;
  String get dbName => _dbName ??= _initialise('PSQL_DBNAME', defaultDbName);

  String _initialise(String key, String defaultValue) {
    var value = defaultValue;

    /// Check for an environment variable.
    if (Platform.environment.containsKey(key)) {
      var value = Platform.environment[key];
      if (value != null) {
        value = value.trim();
      }
      if (value == null || value.isEmpty) {
        throw ArgumentError(
            "The Environment Variable $key does not contain a valid String. Found null or an empty string.");
      }
    }
    return value;
  }
}
