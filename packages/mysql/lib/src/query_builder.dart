import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:conduit_core/conduit_core.dart';
import 'builders/sort.dart';
import 'builders/table.dart';
import 'builders/value.dart';
import 'mysql_query.dart';
import 'row_instantiator.dart';

class MySqlQueryBuilder extends TableBuilder {
  MySqlQueryBuilder(MySqlQuery query, [String prefixIndex = ""])
      : placeholderKeyPrefix = ":",
        super(query) {
    for (var key in entity.defaultProperties) {
      addColumnValueBuilder(
          key, (query.valueMap ?? query.values.backing.contents)?[key]);
    }
    finalize(variables);
  }

  final String placeholderKeyPrefix;

  final Map<String, dynamic> variables = {};

  final Map<String, ColumnValueBuilder> columnValueBuildersByKey = {};

  Iterable<String?> get columnValueKeys =>
      columnValueBuildersByKey.keys.toList().reversed;

  Iterable<ColumnValueBuilder> get columnValueBuilders =>
      columnValueBuildersByKey.values;

  String? get sqlWhereClause {
    if (predicate?.format == null) {
      return null;
    }
    if (predicate!.format.isEmpty) {
      return null;
    }
    return predicate!.format;
  }

  void addColumnValueBuilder(String? key, dynamic value) {
    final builder = _createColumnValueBuilder(key, value)!;
    columnValueBuildersByKey[builder.sqlColumnName()] = builder;
    var val = builder.value;
    if (builder.value is Map) {
      val = json.encode(val);
    }
    variables[builder.sqlColumnName()] = val;
  }

  List<T> instancesForRows<T extends ManagedObject>(
      String? primaryKey, List<Map<String, dynamic>> rows) {
    final instantiator = RowInstantiator(this, returning);
    final res = instantiator.instancesForRows<T>(primaryKey, rows);
    return res;
  }

  ColumnValueBuilder? _createColumnValueBuilder(String? key, dynamic value) {
    final property = entity.properties[key];
    if (property == null) {
      throw ArgumentError("Invalid query. Column '$key' does "
          "not exist for table '${entity.tableName}'");
    }

    if (property is ManagedRelationshipDescription) {
      if (property.relationshipType != ManagedRelationshipType.belongsTo) {
        return null;
      }

      if (value != null) {
        if (value is ManagedObject || value is Map) {
          return ColumnValueBuilder(
            this,
            property,
            value[property.destinationEntity.primaryKey],
          );
        }

        throw ArgumentError("Invalid query. Column '$key' in "
            "'${entity.tableName}' does not exist. '$key' recognized as ORM relationship. "
            "Provided value must be 'Map' or ${property.destinationEntity.name}.");
      }
    }

    return ColumnValueBuilder(this, property, value);
  }

  /*
      Methods that return portions of a SQL statement for this object
   */

  String get sqlColumnsAndValuesToUpdate {
    return columnValueBuilders.map((m) {
      final columnName = m.sqlColumnName();
      final variableName = m.sqlColumnName(
        withPrefix: placeholderKeyPrefix,
      );
      return "$columnName=$variableName";
    }).join(",");
  }

  String get sqlColumnsToInsert => columnValueKeys.join(",");

  List<String> get sqlColumnsToReturn {
    return flattenedColumnsToReturn
        .map((p) => p.sqlColumnName(withTableNamespace: containsJoins))
        .toList();
  }

  String get sqlOrderBy {
    final allSorts = List<ColumnSortBuilder>.from(columnSortBuilders);

    final nestedSorts =
        returning.whereType<TableBuilder>().expand((m) => m.columnSortBuilders);
    allSorts.addAll(nestedSorts);

    if (allSorts.isEmpty) {
      return "";
    }

    return "ORDER BY ${allSorts.map((s) => s.sqlOrderBy).join(",")}";
  }
}
