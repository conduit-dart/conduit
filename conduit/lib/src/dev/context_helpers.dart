import 'dart:async';

import 'package:conduit/conduit.dart';

/// TODO: I think these function should go into the test directory
/// but we first need to check if other packages are dependant on them.
/// For the moment I've copied each of these methods into
/// test/db/postgres/postgres_test_config.dart
/// and updated all unit tests to use those versions.
/// If it turns out that these libraries are share db other packages then
/// we should create a common_unit_test package to house these.
Future<ManagedContext> contextWithModels(List<Type> instanceTypes) async {
  var persistentStore =
      PostgreSQLPersistentStore("dart", "dart", "localhost", 5432, "dart_test");

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
