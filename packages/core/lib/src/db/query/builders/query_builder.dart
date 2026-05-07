/// Dialect-agnostic query-builder facade.
///
/// Lifted from `packages/postgresql/lib/src/query_builder.dart`. The
/// only Postgres-specific dependency was the `PostgresQuery` type in
/// the constructor; that is now any `QueryMixin`. Backends compose
/// SQL strings off this builder's `sqlTableName`, `sqlWhereClause`,
/// `sqlColumnsToInsert`, etc. — the shape of each fragment is
/// identical across dialects, only the placeholder syntax (which the
/// dialect controls) varies.
library;

import 'package:conduit_core/src/db/managed/managed.dart';
import 'package:conduit_core/src/db/managed/relationship_type.dart';
import 'package:conduit_core/src/db/query/builders/row_instantiator.dart';
import 'package:conduit_core/src/db/query/builders/sort.dart';
import 'package:conduit_core/src/db/query/builders/table.dart';
import 'package:conduit_core/src/db/query/builders/value.dart';
import 'package:conduit_core/src/db/query/mixin.dart';

class QueryBuilder extends TableBuilder {
  QueryBuilder(QueryMixin query, [String prefixIndex = ""])
      : valueKeyPrefix = "v${prefixIndex}_",
        super(query) {
    (query.valueMap ?? query.values.backing.contents)
        .forEach(addColumnValueBuilder);
    finalize(variables);
  }

  /// Prefix used when generating parameter binding keys (the keys
  /// that appear in the parameter map). Stays the same across
  /// dialects — the dialect's `parameterPlaceholder` is what varies.
  final String valueKeyPrefix;

  final Map<String, dynamic> variables = {};

  final Map<String, ColumnValueBuilder> columnValueBuildersByKey = {};

  Iterable<String> get columnValueKeys =>
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

  void addColumnValueBuilder(String key, dynamic value) {
    final builder = _createColumnValueBuilder(key, value)!;
    columnValueBuildersByKey[builder.sqlColumnName()] = builder;
    variables[builder.sqlColumnName(withPrefix: valueKeyPrefix)] =
        builder.value;
  }

  List<T> instancesForRows<T extends ManagedObject>(List<List<dynamic>> rows) {
    final instantiator = RowInstantiator(this, returning);
    return instantiator.instancesForRows<T>(rows);
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
      final placeholder = dialect.parameterPlaceholder(
        m.sqlColumnName(withPrefix: valueKeyPrefix),
      );
      return "$columnName=$placeholder";
    }).join(",");
  }

  String get sqlColumnsToInsert => columnValueKeys.join(",");

  String get sqlValuesToInsert => valuesToInsert(columnValueKeys);

  String valuesToInsert(Iterable<String> forKeys) {
    if (forKeys.isEmpty) {
      return "DEFAULT";
    }
    return forKeys.map(_valueToInsert).join(",");
  }

  String? _valueToInsert(String? key) {
    final builder = columnValueBuildersByKey[key];
    if (builder == null) {
      return "DEFAULT";
    }

    return dialect.parameterPlaceholder(
      builder.sqlColumnName(withPrefix: valueKeyPrefix),
    );
  }

  String get sqlColumnsToReturn {
    return flattenedColumnsToReturn
        .map((p) => p.sqlColumnName(withTableNamespace: containsJoins))
        .join(",");
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
