/// Dialect-agnostic column-value builder.
///
/// Lifted from `packages/postgresql/lib/src/builders/value.dart` —
/// the Postgres-specific `TypedValue` wrapping is now applied via
/// `SqlDialect.encodeValue`, which Postgres overrides to return a
/// `TypedValue` and other dialects leave as a pass-through.
library;

import 'package:conduit_core/src/db/managed/property_description.dart';
import 'package:conduit_core/src/db/query/builders/column.dart';
import 'package:conduit_core/src/db/query/builders/table.dart';

class ColumnValueBuilder extends ColumnBuilder {
  ColumnValueBuilder(
    TableBuilder super.table,
    ManagedPropertyDescription super.property,
    dynamic value,
  ) {
    this.value = table!.dialect.encodeValue(
      convertValueForStorage(value),
      property!.type!.kind,
    );
  }

  late Object? value;
}
