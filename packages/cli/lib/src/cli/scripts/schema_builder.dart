// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:conduit/src/cli/migration_source.dart';
import 'package:conduit_core/src/db/postgresql/postgresql_persistent_store.dart';
import 'package:conduit_core/src/db/schema/schema.dart';
import 'package:conduit_isolate_exec/conduit_isolate_exec.dart';
import 'package:logging/logging.dart';

class SchemaBuilderExecutable extends Executable<Map<String, dynamic>> {
  SchemaBuilderExecutable(super.message)
      : inputSchema = Schema.fromMap(message["schema"] as Map<String, dynamic>),
        sources = (message["sources"] as List<Map>)
            .map((m) => MigrationSource.fromMap(m as Map<String, dynamic>))
            .toList();

  SchemaBuilderExecutable.input(this.sources, this.inputSchema)
      : super({
          "schema": inputSchema.asMap(),
          "sources": sources.map((source) => source.asMap()).toList()
        });

  final List<MigrationSource> sources;
  final Schema inputSchema;

  @override
  Future<Map<String, dynamic>> execute() async {
    hierarchicalLoggingEnabled = true;
    PostgreSQLPersistentStore.logger.level = Level.ALL;
    PostgreSQLPersistentStore.logger.onRecord.listen((r) => log(r.message));
    try {
      Schema? outputSchema = inputSchema;
      for (final source in sources) {
        final Migration instance = instanceOf(
          source.name!,
          positionalArguments: const [],
          namedArguments: const <Symbol, dynamic>{},
          constructorName: Symbol.empty,
        );
        instance.database = SchemaBuilder(null, outputSchema);
        await instance.upgrade();
        outputSchema = instance.currentSchema;
      }
      return outputSchema!.asMap();
    } on SchemaException catch (e) {
      return {
        "error":
            "There was an issue with the schema generated by replaying this project's migration files. Reason: ${e.message}"
      };
    }
  }

  static List<String> get imports => [
        "package:conduit_core/conduit_core.dart",
        "package:conduit/src/cli/migration_source.dart",
        "package:conduit_runtime/runtime.dart"
      ];
}
