import 'package:conduit_core/conduit_core.dart';
import 'package:postgres/postgres.dart';
import 'column.dart';
import 'table.dart';

class ColumnValueBuilder extends ColumnBuilder {
  ColumnValueBuilder(
    TableBuilder super.table,
    ManagedPropertyDescription super.property,
    dynamic value,
  ) {
    this.value = TypedValue(ColumnBuilder.typeMap[property!.type!.kind]!,
        convertValueForStorage(value));
  }

  late TypedValue value;
}
