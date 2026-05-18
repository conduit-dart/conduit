import 'dart:async';

import 'package:conduit_core/src/db/managed/context.dart';
import 'package:conduit_core/src/db/managed/entity.dart';
import 'package:conduit_core/src/db/managed/object.dart';
import 'package:conduit_core/src/db/persistent_store/sql_dialect.dart';
import 'package:conduit_core/src/db/query/query.dart';
import 'package:conduit_core/src/db/schema/schema.dart';

enum PersistentStoreQueryReturnType { rowCount, rows }

/// An interface for implementing persistent storage.
///
/// You rarely need to use this class directly. See [Query] for how to interact with instances of this class.
/// Implementors of this class serve as the bridge between [Query]s and a specific database.
abstract class PersistentStore {
  /// The SQL dialect used by this store. Drives identifier quoting,
  /// parameter placeholder syntax, type mapping, and operator
  /// spelling. Subclasses should override; the default returns a
  /// stock `SqlDialect` for backends that haven't yet been migrated
  /// to consult the dialect (e.g. graph backends, where the SQL
  /// surface doesn't apply). The dialect-agnostic query builders in
  /// `db/query/builders/` consult this getter when composing SQL
  /// fragments.
  SqlDialect get dialect => const _DefaultSqlDialect();

  /// Creates a new database-specific [Query].
  ///
  /// Subclasses override this method to provide a concrete implementation of [Query]
  /// specific to this type. Objects returned from this method must implement [Query]. They
  /// should mixin [QueryMixin] to most of the behavior provided by a query.
  Query<T> newQuery<T extends ManagedObject>(
    ManagedContext context,
    ManagedEntity entity, {
    T? values,
  });

  /// Executes an arbitrary command.
  Future execute(String sql, {Map<String, dynamic>? substitutionValues});

  Future<dynamic> executeQuery(
    String formatString,
    Map<String, dynamic> values,
    int timeoutInSeconds, {
    PersistentStoreQueryReturnType? returnType,
  });

  Future<T> transaction<T>(
    ManagedContext transactionContext,
    Future<T> Function(ManagedContext transaction) transactionBlock,
  );

  /// Closes the underlying database connection.
  Future close();

  // -- Schema Ops --

  List<String> createTable(SchemaTable table, {bool isTemporary = false});

  List<String> renameTable(SchemaTable table, String name);

  List<String> deleteTable(SchemaTable table);

  List<String> addTableUniqueColumnSet(SchemaTable table);

  List<String> deleteTableUniqueColumnSet(SchemaTable table);

  List<String> addColumn(
    SchemaTable table,
    SchemaColumn column, {
    String? unencodedInitialValue,
  });

  List<String> deleteColumn(SchemaTable table, SchemaColumn column);

  List<String> renameColumn(
    SchemaTable table,
    SchemaColumn column,
    String name,
  );

  List<String> alterColumnNullability(
    SchemaTable table,
    SchemaColumn column,
    String? unencodedInitialValue,
  );

  List<String> alterColumnUniqueness(SchemaTable table, SchemaColumn column);

  List<String> alterColumnDefaultValue(SchemaTable table, SchemaColumn column);

  List<String> alterColumnDeleteRule(SchemaTable table, SchemaColumn column);

  List<String> addIndexToColumn(SchemaTable table, SchemaColumn column);

  List<String> renameIndex(
    SchemaTable table,
    SchemaColumn column,
    String newIndexName,
  );

  List<String> deleteIndexFromColumn(SchemaTable table, SchemaColumn column);

  Future<int> get schemaVersion;

  Future<Schema> upgrade(
    Schema fromSchema,
    List<Migration> withMigrations, {
    bool temporary = false,
  });
}

/// Stock dialect used as the [PersistentStore.dialect] default for
/// backends that do not implement a SQL surface (e.g. graph
/// backends). It satisfies the abstract interface without claiming
/// any specific spelling — the only call sites that hit this default
/// are non-SQL backends that don't consult the dialect, so the
/// `tableExistsQuery` body is never reached in practice.
class _DefaultSqlDialect extends SqlDialect {
  const _DefaultSqlDialect();

  @override
  String get name => 'default';

  @override
  String? columnDefinitionType(String typeString,
          {required bool autoincrement}) =>
      null;

  @override
  String tableExistsQuery() =>
      throw UnsupportedError(
          'PersistentStore did not override .dialect; cannot generate SQL.');
}
