import 'package:conduit/conduit.dart';

/// This class is used to define the default configuration use
/// by Unit Tests to connect to the postgres db.
///
/// We assume the user has setup their test environment using the provider
/// tool/docker-compose.yml file which creates a docker service on an alternate
/// port: 15432
class PostgresTestConfig {
  factory PostgresTestConfig() => _self;

  static late final PostgresTestConfig _self = PostgresTestConfig();

  static const host = 'localhost';
  static const port = 15432;
  static const username = 'dart';
  static const password = 'dart';
  static const dbName = 'dart_test';

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
}
