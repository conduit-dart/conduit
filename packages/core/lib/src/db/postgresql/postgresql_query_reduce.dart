import 'dart:async';

import 'package:conduit_core/src/db/managed/object.dart';
import 'package:conduit_core/src/db/managed/property_description.dart';
import 'package:conduit_core/src/db/postgresql/builders/column.dart';
import 'package:conduit_core/src/db/postgresql/postgresql_persistent_store.dart';
import 'package:conduit_core/src/db/postgresql/postgresql_query.dart';
import 'package:conduit_core/src/db/postgresql/query_builder.dart';
import 'package:conduit_core/src/db/query/query.dart';

// ignore_for_file: constant_identifier_names
enum _Reducer {
  AVG,
  COUNT,
  MAX,
  MIN,
  SUM,
}

class PostgresQueryReduce<T extends ManagedObject>
    extends QueryReduceOperation<T> {
  PostgresQueryReduce(this.query) : builder = PostgresQueryBuilder(query);

  final PostgresQuery<T> query;
  final PostgresQueryBuilder builder;

  @override
  Future<double?> average(num? Function(T object) selector) {
    return _execute<double?>(
      _Reducer.AVG,
      query.entity.identifyAttribute(selector),
    );
  }

  @override
  Future<int> count() {
    return _execute<int>(_Reducer.COUNT);
  }

  @override
  Future<U?> maximum<U>(U? Function(T object) selector) {
    return _execute<U?>(_Reducer.MAX, query.entity.identifyAttribute(selector));
  }

  @override
  Future<U?> minimum<U>(U? Function(T object) selector) {
    return _execute<U?>(_Reducer.MIN, query.entity.identifyAttribute(selector));
  }

  @override
  Future<U?> sum<U extends num>(U? Function(T object) selector) {
    return _execute<U?>(_Reducer.SUM, query.entity.identifyAttribute(selector));
  }

  String _columnName(ManagedAttributeDescription? property) {
    if (property == null) {
      // This should happen only in count
      return "1";
    }
    final columnBuilder = ColumnBuilder(builder, property);
    return columnBuilder.sqlColumnName(withTableNamespace: true);
  }

  String _function(_Reducer reducer, ManagedAttributeDescription? property) {
    return "${reducer.toString().split('.').last}" // The aggregation function
        "(${_columnName(property)})" // The Column for the aggregation
        "${reducer == _Reducer.AVG ? '::float' : ''}"; // Optional cast to float for AVG
  }

  Future<U> _execute<U>(
    _Reducer reducer, [
    ManagedAttributeDescription? property,
  ]) async {
    if (builder.containsSetJoins) {
      throw StateError(
        "Invalid query. Cannot use 'join(set: ...)' with 'reduce' query.",
      );
    }
    final buffer = StringBuffer();
    buffer.write("SELECT ${_function(reducer, property)} ");
    buffer.write("FROM ${builder.sqlTableName} ");

    if (builder.containsJoins) {
      buffer.write("${builder.sqlJoin} ");
    }

    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    }

    final store = query.context.persistentStore as PostgreSQLPersistentStore;
    final connection = await store.executionContext;
    try {
      final result = await connection!
          .query(buffer.toString(), substitutionValues: builder.variables)
          .timeout(Duration(seconds: query.timeoutInSeconds));
      return result.first.first as U;
    } on TimeoutException catch (e) {
      throw QueryException.transport(
        "timed out connecting to database",
        underlyingException: e,
      );
    }
  }
}
