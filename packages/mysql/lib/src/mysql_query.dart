import 'dart:async';

import 'package:conduit_core/conduit_core.dart';

/// MySQL / MariaDB-flavored `Query<T>` implementation.
///
/// Mirrors `PostgresQuery` and `SqliteQuery` — the SQL composition
/// logic lives in the dialect-agnostic [QueryBuilder] in
/// `package:conduit_core`, this class is a thin shell that strings
/// together INSERT / UPDATE / DELETE / SELECT statements off the
/// builder's getters.
///
/// MySQL has no `RETURNING` clause (the standard MySQL distribution
/// does not implement it; MariaDB has a vendor extension as of
/// 10.5+). The implementation here is conservative and uses the
/// portable two-phase pattern: SELECT the matching primary keys, run
/// the INSERT/UPDATE, SELECT the rows back by primary key. The
/// driver auto-prepares each statement so the round-trip cost is one
/// network round-trip per phase.
class MysqlQuery<InstanceType extends ManagedObject>
    with QueryMixin<InstanceType>
    implements Query<InstanceType> {
  MysqlQuery(this.context);

  MysqlQuery.withEntity(this.context, this._entity);

  @override
  ManagedContext context;

  @override
  ManagedEntity get entity => _entity;

  late ManagedEntity _entity = context.dataModel!.entityForType(InstanceType);

  @override
  QueryReduceOperation<InstanceType> get reduce {
    return _MysqlQueryReduce<InstanceType>(this);
  }

  @override
  Future<InstanceType> insert() async {
    validateInput(Validating.insert);

    final builder = QueryBuilder(this);
    final buffer = StringBuffer();
    buffer.write("INSERT INTO ${builder.sqlTableName} ");

    if (builder.columnValueBuilders.isNotEmpty) {
      buffer.write("(${builder.sqlColumnsToInsert}) ");
    }
    buffer.write("VALUES (${builder.sqlValuesToInsert})");

    await context.persistentStore
        .executeQuery(buffer.toString(), builder.variables, timeoutInSeconds);

    final pkColumn = entity.primaryKey;
    final pkValueBuilder = builder.columnValueBuildersByKey[pkColumn];

    final Object? rawPkValue;
    if (pkValueBuilder != null && pkValueBuilder.value != null) {
      rawPkValue = pkValueBuilder.value;
    } else {
      // mysql_dart exposes the same affected-rows + last-insert-id
      // metadata as `executeQuery`'s rowCount path, but the value we
      // need is the *id* not the count. Read it via SELECT
      // LAST_INSERT_ID() on the same connection (driver re-uses the
      // pooled connection for the same store instance).
      final rows = await context.persistentStore.executeQuery(
        "SELECT LAST_INSERT_ID()",
        const {},
        timeoutInSeconds,
      ) as List<List<dynamic>>;
      rawPkValue = rows.first.first;
    }

    final selectQuery = MysqlQuery<InstanceType>.withEntity(context, entity);
    final selectBuilder = QueryBuilder(selectQuery);
    final selectBuf = StringBuffer();
    selectBuf.write("SELECT ${selectBuilder.sqlColumnsToReturn} ");
    selectBuf.write("FROM ${selectBuilder.sqlTableName} ");
    selectBuf.write("WHERE $pkColumn = :__pk_value__");

    final results = await context.persistentStore.executeQuery(
      selectBuf.toString(),
      {'__pk_value__': rawPkValue},
      timeoutInSeconds,
    ) as List<List<dynamic>>;

    return selectBuilder
        .instancesForRows<InstanceType>(results)
        .first;
  }

  @override
  Future<List<InstanceType>> insertMany(List<InstanceType?> objects) async {
    if (objects.isEmpty) {
      return [];
    }
    final inserted = <InstanceType>[];
    for (final o in objects) {
      values = o;
      inserted.add(await insert());
    }
    return inserted;
  }

  @override
  Future<List<InstanceType>> update() async {
    validateInput(Validating.update);

    final builder = QueryBuilder(this);

    final pkColumn = entity.primaryKey;
    final selectIdsBuf = StringBuffer();
    selectIdsBuf.write("SELECT $pkColumn FROM ${builder.sqlTableName} ");
    if (builder.sqlWhereClause != null) {
      selectIdsBuf.write("WHERE ${builder.sqlWhereClause} ");
    } else if (!canModifyAllInstances) {
      throw canModifyAllInstancesError;
    }
    final selectIdsSql = selectIdsBuf.toString();
    final selectIdsParams = _filterParams(selectIdsSql, builder.variables);
    final pkRows = await context.persistentStore.executeQuery(
      selectIdsSql,
      selectIdsParams,
      timeoutInSeconds,
    ) as List<List<dynamic>>;
    final pkValues = pkRows.map((r) => r.first).toList();

    final updBuf = StringBuffer();
    updBuf.write("UPDATE ${builder.sqlTableName} ");
    updBuf.write("SET ${builder.sqlColumnsAndValuesToUpdate} ");
    if (builder.sqlWhereClause != null) {
      updBuf.write("WHERE ${builder.sqlWhereClause} ");
    }
    await context.persistentStore.executeQuery(
      updBuf.toString(),
      builder.variables,
      timeoutInSeconds,
      returnType: PersistentStoreQueryReturnType.rowCount,
    );

    if (pkValues.isEmpty) return <InstanceType>[];

    final fetchQuery = MysqlQuery<InstanceType>.withEntity(context, entity);
    final fetchBuilder = QueryBuilder(fetchQuery);
    final placeholders = <String>[];
    final pkParams = <String, dynamic>{};
    for (var i = 0; i < pkValues.length; i++) {
      final key = '__pk_${i}__';
      placeholders.add(':$key');
      pkParams[key] = pkValues[i];
    }
    final fetchBuf = StringBuffer();
    fetchBuf.write("SELECT ${fetchBuilder.sqlColumnsToReturn} ");
    fetchBuf.write("FROM ${fetchBuilder.sqlTableName} ");
    fetchBuf.write("WHERE $pkColumn IN (${placeholders.join(',')})");
    final results = await context.persistentStore.executeQuery(
      fetchBuf.toString(),
      pkParams,
      timeoutInSeconds,
    ) as List<List<dynamic>>;
    return fetchBuilder.instancesForRows(results);
  }

  @override
  Future<InstanceType?> updateOne() async {
    final results = await update();
    if (results.length == 1) return results.first;
    if (results.isEmpty) return null;
    throw StateError(
      "Query error. 'updateOne' modified more than one row in '${entity.tableName}'.",
    );
  }

  @override
  Future<int> delete() async {
    final builder = QueryBuilder(this);
    final buffer = StringBuffer();
    buffer.write("DELETE FROM ${builder.sqlTableName} ");
    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    } else if (!canModifyAllInstances) {
      throw canModifyAllInstancesError;
    }
    final int result = await context.persistentStore.executeQuery(
      buffer.toString(),
      builder.variables,
      timeoutInSeconds,
      returnType: PersistentStoreQueryReturnType.rowCount,
    );
    return result;
  }

  @override
  Future<InstanceType?> fetchOne() async {
    final builder = createFetchBuilder();
    if (!builder.containsJoins) fetchLimit = 1;
    final results = await _fetch(builder);
    if (results.length == 1) return results.first;
    if (results.length > 1) {
      throw StateError(
        "Query error. 'fetchOne' returned more than one row from '${entity.tableName}'.",
      );
    }
    return null;
  }

  @override
  Future<List<InstanceType>> fetch() async => _fetch(createFetchBuilder());

  QueryBuilder createFetchBuilder() {
    final builder = QueryBuilder(this);
    if (pageDescriptor != null) {
      validatePageDescriptor();
      if (builder.containsJoins) {
        throw StateError(
          "Invalid query. Cannot set both 'pageDescription' and use 'join' in query.",
        );
      }
    }
    return builder;
  }

  Future<List<InstanceType>> _fetch(QueryBuilder builder) async {
    final buffer = StringBuffer();
    buffer.write("SELECT ${builder.sqlColumnsToReturn} ");
    buffer.write("FROM ${builder.sqlTableName} ");
    if (builder.containsJoins) {
      buffer.write("${builder.sqlJoin} ");
    }
    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    }
    buffer.write("${builder.sqlOrderBy} ");
    if (fetchLimit != 0) buffer.write("LIMIT $fetchLimit ");
    if (offset != 0) buffer.write("OFFSET $offset ");
    final results = await context.persistentStore
        .executeQuery(buffer.toString(), builder.variables, timeoutInSeconds);
    return builder.instancesForRows(results as List<List<dynamic>>);
  }

  void validatePageDescriptor() {
    final pd = pageDescriptor!;
    final prop = entity.attributes[pd.propertyName];
    if (prop == null) {
      throw StateError(
        "Invalid query page descriptor. Column '${pd.propertyName}' does not exist for table '${entity.tableName}'",
      );
    }
    if (pd.boundingValue != null && !prop.isAssignableWith(pd.boundingValue)) {
      throw StateError(
        "Invalid query page descriptor. Bounding value for column '${pd.propertyName}' has invalid type.",
      );
    }
  }

  Map<String, dynamic> _filterParams(String sql, Map<String, dynamic> params) {
    final out = <String, dynamic>{};
    for (final entry in params.entries) {
      if (sql.contains(':${entry.key}')) out[entry.key] = entry.value;
    }
    return out;
  }

  static final StateError canModifyAllInstancesError = StateError(
    "Invalid Query<T>. Query is either update or delete query with no WHERE clause. To confirm this query is correct, set 'canModifyAllInstances' to true.",
  );
}

enum _Reducer { avg, count, max, min, sum }

class _MysqlQueryReduce<T extends ManagedObject>
    extends QueryReduceOperation<T> {
  _MysqlQueryReduce(this.query) : builder = QueryBuilder(query);

  final MysqlQuery<T> query;
  final QueryBuilder builder;

  @override
  Future<double?> average(num? Function(T object) selector) {
    return _execute<double?>(
      _Reducer.avg,
      query.entity.identifyAttribute(selector),
    );
  }

  @override
  Future<int> count() => _execute<int>(_Reducer.count);

  @override
  Future<U?> maximum<U>(U? Function(T object) selector) {
    return _execute<U?>(_Reducer.max, query.entity.identifyAttribute(selector));
  }

  @override
  Future<U?> minimum<U>(U? Function(T object) selector) {
    return _execute<U?>(_Reducer.min, query.entity.identifyAttribute(selector));
  }

  @override
  Future<U?> sum<U extends num>(U? Function(T object) selector) {
    return _execute<U?>(_Reducer.sum, query.entity.identifyAttribute(selector));
  }

  String _columnName(ManagedAttributeDescription? property) {
    if (property == null) return "1";
    final cb = ColumnBuilder(builder, property);
    return cb.sqlColumnName(withTableNamespace: true);
  }

  String _function(_Reducer reducer, ManagedAttributeDescription? property) {
    final col = _columnName(property);
    final fn = reducer.toString().split('.').last;
    return "$fn($col)";
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
    if (builder.containsJoins) buffer.write("${builder.sqlJoin} ");
    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    }
    final result = await query.context.persistentStore.executeQuery(
      buffer.toString(),
      builder.variables,
      query.timeoutInSeconds,
    ) as List<List<dynamic>>;
    if (result.isEmpty) return null as U;
    return result.first.first as U;
  }
}

Query<T> mysqlNewQuery<T extends ManagedObject>(
  ManagedContext context,
  ManagedEntity entity, {
  T? values,
}) {
  final q = MysqlQuery<T>.withEntity(context, entity);
  if (values != null) {
    q.values = values;
  }
  return q;
}
