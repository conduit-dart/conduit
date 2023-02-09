import 'package:conduit_core/conduit_core.dart';
import 'column.dart';
import 'table.dart';

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
