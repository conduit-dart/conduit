import 'package:conduit_core/conduit_core.dart';

import 'column.dart';
import 'table.dart';

class ColumnSortBuilder extends ColumnBuilder {
  ColumnSortBuilder(TableBuilder table, String? key, QuerySortOrder order)
      : order = order == QuerySortOrder.ascending ? "ASC" : "DESC",
        super(table, table.entity.properties[key]);

  final String order;

  String get sqlOrderBy => "${sqlColumnName(withTableNamespace: true)} $order";
}

class ColumnSortPredicateBuilder extends ColumnSortBuilder {
  ColumnSortPredicateBuilder(
      TableBuilder table, String key, QuerySortOrder order)
      : _key = key,
        super(table, key, order);

  final String _key;

  @override
  String get sqlOrderBy => "$_key $order";
}
