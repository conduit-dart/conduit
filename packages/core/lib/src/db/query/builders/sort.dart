/// Dialect-agnostic sort builders. Lifted from
/// `packages/postgresql/lib/src/builders/sort.dart` so SQLite and
/// MySQL can reuse them without depending on the postgresql package.
library;

import 'package:conduit_core/src/db/query/builders/column.dart';
import 'package:conduit_core/src/db/query/builders/table.dart';
import 'package:conduit_core/src/db/query/query.dart';

class ColumnSortBuilder(TableBuilder table, String key, QuerySortOrder order)
    extends ColumnBuilder {
  this : super(table, table.entity.properties[key]);

  final String order = order == QuerySortOrder.ascending ? "ASC" : "DESC";

  String get sqlOrderBy => "${sqlColumnName(withTableNamespace: true)} $order";
}

class ColumnSortPredicateBuilder extends ColumnSortBuilder {
  new(super.table, super.key, super.order) : _key = key;

  final String _key;

  @override
  String get sqlOrderBy => "$_key $order";
}
