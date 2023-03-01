import 'dart:io';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_postgresql/conduit_postgresql.dart';

/// This class is used to define the default configuration used
/// by Unit Tests to connect to the postgres db.
///
/// This class provide three levels of configuration:
///
/// environment variables:
/// If an environment variable is found for one of the settings
/// then it overrides any of the following source.
///
/// .settings.yaml file
/// If an .settings.yaml file is found then and no environment variable exists
/// then the setting is taking from .settings.yaml
///
/// default values
/// If no environment variable exists and the .settings.yaml file doesn't
/// exist then the default value is used.
///
class PostgresTestConfig {
  factory PostgresTestConfig() => _self;

  PostgresTestConfig._internal();

  static final PostgresTestConfig _self = PostgresTestConfig._internal();

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
    if (_port == null) {
      /// Check for an environment variable.
      const key = 'POSTGRES_PORT';
      if (Platform.environment.containsKey(key)) {
        final value = Platform.environment[key];
        if (value != null) {
          _port = int.tryParse(value);
        }
        if (_port == null) {
          throw ArgumentError(
              "The Environment Variable $key does not contain a valid integer. Found: $value");
        }
      }
    }
    return _port!;
  }

  String? _host;
  String get host => _host ??= _fromEnv('POSTGRES_HOST')!;

  String? _username;
  String get username => _username ??= _fromEnv('POSTGRES_USER')!;

  String? _password;
  String get password => _password ??= _fromEnv('POSTGRES_PASSWORD')!;

  String? _dbName;
  String get dbName => _dbName ??= _fromEnv('POSTGRES_DB')!;

  String? _fromEnv(String key) {
    String? value;

    /// Check for an environment variable.
    if (Platform.environment.containsKey(key)) {
      value = Platform.environment[key];
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
