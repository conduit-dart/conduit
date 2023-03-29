import 'dart:async';

import 'package:conduit_core/conduit_core.dart';
import 'package:mysql_client/mysql_client.dart';
import 'mysql_query_reduce.dart';
import 'query_builder.dart';

class MySqlQuery<InstanceType extends ManagedObject> extends Object
    with QueryMixin<InstanceType>
    implements Query<InstanceType> {
  MySqlQuery(this.context);

  MySqlQuery.withEntity(this.context, this._entity);

  @override
  ManagedContext context;

  @override
  ManagedEntity get entity => _entity;

  late ManagedEntity _entity = context.dataModel!.entityForType(InstanceType);

  @override
  QueryReduceOperation<InstanceType> get reduce {
    return MySqlQueryReduce(this);
  }

  @override
  Future<InstanceType> insert() async {
    validateInput(Validating.insert);

    final builder = MySqlQueryBuilder(this);

    final buffer = StringBuffer();
    buffer.write("INSERT INTO ${builder.sqlTableName} ");
    final valuesToInsert = entity.properties.keys.map((e) => ':$e').join(',');
    buffer.write("VALUES ($valuesToInsert)");
    print(buffer.toString());
    print(builder.variables);
    for (final element in entity.properties.keys) {
      builder.variables[element!] = builder.variables[element];
    }
    print(builder.variables);
    var results = await context.persistentStore
        .execute(buffer.toString(), substitutionValues: builder.variables);
    if (builder.returning.isNotEmpty) {
      String where = '';

      final clauses = builder.variables.entries
          .where((e) => e.key != entity.primaryKey)
          .map((e) {
        if (e.value is! num) {
          if (e.value == null) {
            return "${e.key} IS NULL";
          }
          return "${e.key}='${e.value}'";
        }
        return "${e.key}=${e.value}";
      });
      if (clauses.isNotEmpty) {
        where = 'WHERE ${clauses.join(' AND ')}';
      }

      final returning = 'SELECT * FROM ${builder.sqlTableName} $where';
      results = await context.persistentStore.execute(returning);
    }

    return builder
        .instancesForRows<InstanceType>(_entity.primaryKey, results)
        .last;
  }

  @override
  Future<List<InstanceType>> insertMany(List<InstanceType?> objects) async {
    if (objects.isEmpty) {
      return [];
    }

    final buffer = StringBuffer();

    final allColumns = <String?>{};
    final builders = <MySqlQueryBuilder>[];

    for (int i = 0; i < objects.length; i++) {
      values = objects[i];
      validateInput(Validating.insert);

      builders.add(MySqlQueryBuilder(this, "$i"));
      allColumns.addAll(builders.last.columnValueKeys);
    }

    buffer.write("INSERT INTO ${builders.first.sqlTableName} ");

    if (allColumns.isEmpty) {
      buffer.write("VALUES ");
    } else {
      buffer.write("(${allColumns.join(',')}) VALUES ");
    }

    final valuesToInsert = <String>[];
    final allVariables = <String, dynamic>{};

    for (final builder in builders) {
      valuesToInsert.add("($valuesToInsert)");
      allVariables.addAll(builder.variables);
    }

    buffer.writeAll(valuesToInsert, ",");
    buffer.write(" ");

    if (builders.first.returning.isNotEmpty) {
      buffer.write("RETURNING ${builders.first.sqlColumnsToReturn}");
    }

    IResultSet results = await context.persistentStore
        .executeQuery(buffer.toString(), allVariables, timeoutInSeconds);

    return builders.first.instancesForRows<InstanceType>(
        _entity.primaryKey, results.rows.map((e) => e.typedAssoc()).toList());
  }

  @override
  Future<List<InstanceType>> update() async {
    validateInput(Validating.update);
    final builder = MySqlQueryBuilder(this);

    final buffer = StringBuffer();
    buffer.write("UPDATE ${builder.sqlTableName} ");
    buffer.write("SET ${builder.sqlColumnsAndValuesToUpdate} ");

    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    } else if (!canModifyAllInstances) {
      throw canModifyAllInstancesError;
    }
    IResultSet results = await context.persistentStore
        .executeQuery(buffer.toString(), builder.variables, timeoutInSeconds);

    if (builder.returning.isNotEmpty) {
      final returning =
          'SELECT ${builder.sqlColumnsToReturn} FROM ${builder.sqlTableName} WHERE ${builder.sqlWhereClause}';
      results = await context.persistentStore
          .executeQuery(returning, builder.variables, timeoutInSeconds);
    }

    return builder.instancesForRows(
        _entity.primaryKey, results.rows.map((e) => e.typedAssoc()).toList());
  }

  @override
  Future<InstanceType?> updateOne() async {
    final results = await update();
    if (results.length == 1) {
      return results.first;
    } else if (results.isEmpty) {
      return null;
    }

    throw StateError(
        "Query error. 'updateOne' modified more than one row in '${entity.tableName}'. "
        "This was likely unintended and may be indicativate of a more serious error. Query "
        "should add 'where' constraints on a unique column.");
  }

  @override
  Future<int?> delete() async {
    final builder = MySqlQueryBuilder(this);

    final buffer = StringBuffer();
    buffer.write("DELETE FROM ${builder.sqlTableName} ");

    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    } else if (!canModifyAllInstances) {
      throw canModifyAllInstancesError;
    }

    final result = await context.persistentStore.executeQuery(
      buffer.toString(),
      builder.variables,
      timeoutInSeconds,
      returnType: PersistentStoreQueryReturnType.rowCount,
    );
    return result as int?;
  }

  @override
  Future<InstanceType?> fetchOne() async {
    final builder = createFetchBuilder();

    if (!builder.containsJoins) {
      fetchLimit = 1;
    }

    final results = await _fetch(builder);
    if (results.length == 1) {
      return results.first;
    } else if (results.length > 1) {
      throw StateError(
          "Query error. 'fetchOne' returned more than one row from '${entity.tableName}'. "
          "This was likely unintended and may be indicativate of a more serious error. Query "
          "should add 'where' constraints on a unique column.");
    }

    return null;
  }

  @override
  Future<List<InstanceType>> fetch() async {
    return _fetch(createFetchBuilder());
  }

  //////

  MySqlQueryBuilder createFetchBuilder() {
    final builder = MySqlQueryBuilder(this);

    if (pageDescriptor != null) {
      validatePageDescriptor();
    }

    if (builder.containsJoins && pageDescriptor != null) {
      throw StateError(
        "Invalid query. Cannot set both 'pageDescription' and use 'join' in query.",
      );
    }

    return builder;
  }

  Future<List<InstanceType>> _fetch(MySqlQueryBuilder builder) async {
    final buffer = StringBuffer();
    buffer.write("SELECT ${builder.sqlColumnsToReturn.join(',')} ");
    buffer.write("FROM ${builder.sqlTableName} ");

    if (builder.containsJoins) {
      buffer.write("${builder.sqlJoin} ");
    }

    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    }

    buffer.write("${builder.sqlOrderBy} ");

    if (fetchLimit != 0) {
      buffer.write("LIMIT $fetchLimit ");
    }

    if (offset != 0) {
      buffer.write("OFFSET $offset ");
    }
    IResultSet results = await context.persistentStore
        .executeQuery(buffer.toString(), builder.variables, timeoutInSeconds);
    return builder.instancesForRows(
        _entity.primaryKey, results.rows.map((e) => e.typedAssoc()).toList());
  }

  void validatePageDescriptor() {
    final prop = entity.attributes[pageDescriptor!.propertyName];
    if (prop == null) {
      throw StateError(
        "Invalid query page descriptor. Column '${pageDescriptor!.propertyName}' does not exist for table '${entity.tableName}'",
      );
    }

    if (pageDescriptor!.boundingValue != null &&
        !prop.isAssignableWith(pageDescriptor!.boundingValue)) {
      throw StateError(
        "Invalid query page descriptor. Bounding value for column '${pageDescriptor!.propertyName}' has invalid type.",
      );
    }
  }

  static final StateError canModifyAllInstancesError = StateError(
    "Invalid Query<T>. Query is either update or delete query with no WHERE clause. To confirm this query is correct, set 'canModifyAllInstances' to true.",
  );
}
