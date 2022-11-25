import 'package:conduit/src/db/managed/managed.dart';
import 'package:conduit/src/db/postgresql/builders/column.dart';
import 'package:conduit/src/db/postgresql/builders/table.dart';

class ColumnValueBuilder extends ColumnBuilder {
  ColumnValueBuilder(
    TableBuilder super.table,
    ManagedPropertyDescription super.property,
    dynamic value,
  ) {
    this.value = convertValueForStorage(value);
  }

  dynamic value;
}
