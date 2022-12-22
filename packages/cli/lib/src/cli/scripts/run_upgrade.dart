// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:mirrors';

import 'package:conduit/src/cli/migration_source.dart';
import 'package:conduit_core/src/db/persistent_store/persistent_store.dart';
import 'package:conduit_core/src/db/postgresql/postgresql_persistent_store.dart';
import 'package:conduit_core/src/db/query/error.dart';
import 'package:conduit_core/src/db/schema/schema.dart';
import 'package:conduit_isolate_exec/conduit_isolate_exec.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';

class RunUpgradeExecutable extends Executable<Map<String, dynamic>> {
  RunUpgradeExecutable(super.message)
      : inputSchema = Schema.fromMap(message["schema"] as Map<String, dynamic>),
        dbInfo = DBInfo.fromMap(message["dbInfo"] as Map<String, dynamic>),
        sources = (message["migrations"] as List<Map>)
            .map((m) => MigrationSource.fromMap(m as Map<String, dynamic>))
            .toList(),
        currentVersion = message["currentVersion"] as int?;

  RunUpgradeExecutable.input(
    this.inputSchema,
    this.dbInfo,
    this.sources,
    this.currentVersion,
  ) : super({
          "schema": inputSchema.asMap(),
          "dbInfo": dbInfo.asMap(),
          "migrations": sources.map((source) => source.asMap()).toList(),
          "currentVersion": currentVersion
        });

  final Schema inputSchema;
  final DBInfo dbInfo;
  final List<MigrationSource> sources;
  final int? currentVersion;

  @override
  Future<Map<String, dynamic>> execute() async {
    hierarchicalLoggingEnabled = true;

    PostgreSQLPersistentStore.logger.level = Level.ALL;
    PostgreSQLPersistentStore.logger.onRecord.listen((r) => log(r.message));

    late PersistentStore store;
    if (dbInfo.flavor == "postgres") {
      store = PostgreSQLPersistentStore(
        dbInfo.username,
        dbInfo.password,
        dbInfo.host,
        dbInfo.port,
        dbInfo.databaseName,
        timeZone: dbInfo.timeZone,
        useSSL: dbInfo.useSSL,
      );
    }

    final migrationTypes =
        currentMirrorSystem().isolate.rootLibrary.declarations.values.where(
              (dm) =>
                  dm is ClassMirror && dm.isSubclassOf(reflectClass(Migration)),
            );

    final instances = sources.map((s) {
      final type = migrationTypes.firstWhere((cm) {
        return cm is ClassMirror &&
            MirrorSystem.getName(cm.simpleName) == s.name;
      }) as ClassMirror;
      final migration =
          type.newInstance(Symbol.empty, []).reflectee as Migration;
      migration.version = s.versionNumber;
      return migration;
    }).toList();

    try {
      final updatedSchema = (await store.upgrade(inputSchema, instances))!;
      await store.close();

      return updatedSchema.asMap();
    } on QueryException catch (e) {
      if (e.event == QueryExceptionEvent.transport) {
        final databaseUrl =
            "${dbInfo.username}:${dbInfo.password}@${dbInfo.host}:${dbInfo.port}/${dbInfo.databaseName}";
        return {
          "error":
              "There was an error connecting to the database '$databaseUrl'. Reason: ${e.message}."
        };
      }

      rethrow;
    } on MigrationException catch (e) {
      return {"error": e.message};
    } on SchemaException catch (e) {
      return {
        "error":
            "There was an issue with the schema generated by a migration file. Reason: ${e.message}"
      };
    } on PostgreSQLException catch (e) {
      if (e.severity == PostgreSQLSeverity.error &&
          e.message!.contains("contains null values")) {
        return {
          "error": "There was an issue when adding or altering column '${e.tableName}.${e.columnName}'. "
              "This column cannot be null, but there already exist rows that would violate this constraint. "
              "Use 'unencodedInitialValue' in your migration file to provide a value for any existing columns."
        };
      }

      return {
        "error":
            "There was an issue. Reason: ${e.message}. Table: ${e.tableName} Column: ${e.columnName}"
      };
    }
  }

  static List<String> get imports => [
        "package:conduit_core/conduit_core.dart",
        "package:logging/logging.dart",
        "package:postgres/postgres.dart",
        "package:conduit/src/cli/migration_source.dart",
        "package:conduit_runtime/runtime.dart"
      ];
}

class DBInfo {
  DBInfo(
    this.flavor,
    this.username,
    this.password,
    this.host,
    this.port,
    this.databaseName,
    this.timeZone, {
    this.useSSL = false,
  });

  DBInfo.fromMap(Map<String, dynamic> map)
      : flavor = map["flavor"] as String?,
        username = map["username"] as String?,
        password = map["password"] as String?,
        host = map["host"] as String?,
        port = map["port"] as int?,
        databaseName = map["databaseName"] as String?,
        timeZone = map["timeZone"] as String?,
        useSSL = (map["useSSL"] ?? false) as bool;

  final String? flavor;
  final String? username;
  final String? password;
  final String? host;
  final int? port;
  final String? databaseName;
  final String? timeZone;
  final bool useSSL;

  Map<String, dynamic> asMap() {
    return {
      "flavor": flavor,
      "username": username,
      "password": password,
      "host": host,
      "port": port,
      "databaseName": databaseName,
      "timeZone": timeZone,
      "useSSL": useSSL
    };
  }
}
