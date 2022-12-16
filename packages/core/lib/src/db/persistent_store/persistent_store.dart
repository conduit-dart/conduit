import 'dart:async';

import 'package:conduit_core/src/db/managed/context.dart';
import 'package:conduit_core/src/db/managed/entity.dart';
import 'package:conduit_core/src/db/managed/object.dart';
import 'package:conduit_core/src/db/query/mixin.dart';
import 'package:conduit_core/src/db/query/query.dart';
import 'package:conduit_core/src/db/schema/schema.dart';

enum PersistentStoreQueryReturnType { rowCount, rows }

/// An interface for implementing persistent storage.
///
/// You rarely need to use this class directly. See [Query] for how to interact with instances of this class.
/// Implementors of this class serve as the bridge between [Query]s and a specific database.
abstract class PersistentStore {
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

  Future<T?> transaction<T>(
    ManagedContext transactionContext,
    Future<T?> Function(ManagedContext transaction) transactionBlock,
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

  Future<Schema?> upgrade(
    Schema fromSchema,
    List<Migration> withMigrations, {
    bool temporary = false,
  });
}

class EmptyStore implements PersistentStore {
  @override
  List<String> addColumn(
    SchemaTable table,
    SchemaColumn column, {
    String? unencodedInitialValue,
  }) {
    // TODO: implement addColumn
    throw UnimplementedError();
  }

  @override
  List<String> addIndexToColumn(SchemaTable table, SchemaColumn column) {
    // TODO: implement addIndexToColumn
    throw UnimplementedError();
  }

  @override
  List<String> addTableUniqueColumnSet(SchemaTable table) {
    // TODO: implement addTableUniqueColumnSet
    throw UnimplementedError();
  }

  @override
  List<String> alterColumnDefaultValue(SchemaTable table, SchemaColumn column) {
    // TODO: implement alterColumnDefaultValue
    throw UnimplementedError();
  }

  @override
  List<String> alterColumnDeleteRule(SchemaTable table, SchemaColumn column) {
    // TODO: implement alterColumnDeleteRule
    throw UnimplementedError();
  }

  @override
  List<String> alterColumnNullability(
    SchemaTable table,
    SchemaColumn column,
    String? unencodedInitialValue,
  ) {
    // TODO: implement alterColumnNullability
    throw UnimplementedError();
  }

  @override
  List<String> alterColumnUniqueness(SchemaTable table, SchemaColumn column) {
    // TODO: implement alterColumnUniqueness
    throw UnimplementedError();
  }

  @override
  Future close() {
    // TODO: implement close
    throw UnimplementedError();
  }

  @override
  List<String> createTable(SchemaTable table, {bool isTemporary = false}) {
    // TODO: implement createTable
    throw UnimplementedError();
  }

  @override
  List<String> deleteColumn(SchemaTable table, SchemaColumn column) {
    // TODO: implement deleteColumn
    throw UnimplementedError();
  }

  @override
  List<String> deleteIndexFromColumn(SchemaTable table, SchemaColumn column) {
    // TODO: implement deleteIndexFromColumn
    throw UnimplementedError();
  }

  @override
  List<String> deleteTable(SchemaTable table) {
    // TODO: implement deleteTable
    throw UnimplementedError();
  }

  @override
  List<String> deleteTableUniqueColumnSet(SchemaTable table) {
    // TODO: implement deleteTableUniqueColumnSet
    throw UnimplementedError();
  }

  @override
  Future execute(String sql, {Map<String, dynamic>? substitutionValues}) {
    // TODO: implement execute
    throw UnimplementedError();
  }

  @override
  Future executeQuery(
    String formatString,
    Map<String, dynamic> values,
    int timeoutInSeconds, {
    PersistentStoreQueryReturnType? returnType,
  }) {
    // TODO: implement executeQuery
    throw UnimplementedError();
  }

  @override
  Query<T> newQuery<T extends ManagedObject>(
    ManagedContext context,
    ManagedEntity entity, {
    T? values,
  }) {
    // TODO: implement newQuery
    throw UnimplementedError();
  }

  @override
  List<String> renameColumn(
    SchemaTable table,
    SchemaColumn column,
    String name,
  ) {
    // TODO: implement renameColumn
    throw UnimplementedError();
  }

  @override
  List<String> renameIndex(
    SchemaTable table,
    SchemaColumn column,
    String newIndexName,
  ) {
    // TODO: implement renameIndex
    throw UnimplementedError();
  }

  @override
  List<String> renameTable(SchemaTable table, String name) {
    // TODO: implement renameTable
    throw UnimplementedError();
  }

  @override
  // TODO: implement schemaVersion
  Future<int> get schemaVersion => throw UnimplementedError();

  @override
  Future<T?> transaction<T>(
    ManagedContext transactionContext,
    Future<T?> Function(ManagedContext transaction) transactionBlock,
  ) {
    // TODO: implement transaction
    throw UnimplementedError();
  }

  @override
  Future<Schema?> upgrade(
    Schema fromSchema,
    List<Migration> withMigrations, {
    bool temporary = false,
  }) {
    // TODO: implement upgrade
    throw UnimplementedError();
  }
}
