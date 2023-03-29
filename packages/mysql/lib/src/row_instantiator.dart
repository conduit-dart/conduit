import 'package:conduit_core/conduit_core.dart';
import 'builders/column.dart';
import 'builders/table.dart';

class RowInstantiator {
  RowInstantiator(this.rootTableBuilder, this.returningValues);

  final TableBuilder rootTableBuilder;
  final List<Returnable>? returningValues;

  Map<TableBuilder, Map<dynamic, ManagedObject>> distinctObjects = {};

  List<U> instancesForRows<U extends ManagedObject>(
      String? primaryKey, List<Map<String, dynamic>> rows) {
    try {
      return rows
          .map(
            (row) =>
                instanceFromRow(primaryKey, row, returningValues!.iterator),
          )
          .where((wrapper) => wrapper?.isNew ?? false)
          .map((wrapper) => wrapper!.instance as U)
          .toList();
    } on ValidationException catch (e) {
      throw StateError("Database error when retrieving value. $e");
    }
  }

  InstanceWrapper? instanceFromRow(
    String? primaryKey,
    Map<String, dynamic> row,
    Iterator<Returnable> returningIterator, {
    TableBuilder? table,
  }) {
    table ??= rootTableBuilder;
    final primaryKeyValue = row[primaryKey];
    var alreadyExists = true;
    var instance = getExistingInstance(table, primaryKeyValue);
    if (instance == null) {
      alreadyExists = false;
      instance = createInstanceWithPrimaryKeyValue(table, primaryKeyValue);
    }

    while (returningIterator.moveNext()) {
      final ret = returningIterator.current;
      if (ret is ColumnBuilder) {
        applyColumnValueToProperty(instance, ret, row[ret.sqlColumnName()]);
      } else if (ret is TableBuilder) {
        applyRowValuesToInstance(primaryKey, instance, ret, row);
      }
    }

    return InstanceWrapper(instance, !alreadyExists);
  }

  ManagedObject createInstanceWithPrimaryKeyValue(
    TableBuilder table,
    dynamic primaryKeyValue,
  ) {
    final instance = table.entity.instanceOf();
    instance[table.entity.primaryKey] = primaryKeyValue;
    var typeMap = distinctObjects[table];
    if (typeMap == null) {
      typeMap = {};
      distinctObjects[table] = typeMap;
    }

    typeMap[instance[instance.entity.primaryKey]] = instance;

    return instance;
  }

  ManagedObject? getExistingInstance(
    TableBuilder table,
    dynamic primaryKeyValue,
  ) {
    final byType = distinctObjects[table];
    if (byType == null) {
      return null;
    }

    return byType[primaryKeyValue];
  }

  void applyRowValuesToInstance(
    String? primaryKey,
    ManagedObject instance,
    TableBuilder table,
    Map<String, dynamic> row,
  ) {
    if (table.flattenedColumnsToReturn.isEmpty) {
      return;
    }

    final innerInstanceWrapper = instanceFromRow(
        primaryKey, row, table.returning.iterator,
        table: table);

    if (table.joinedBy!.relationshipType == ManagedRelationshipType.hasMany) {
      // If to many, put in a managed set.
      final list = (instance[table.joinedBy!.name] ??
          table.joinedBy!.destinationEntity.setOf([])) as ManagedSet?;

      if (innerInstanceWrapper?.isNew ?? false) {
        list!.add(innerInstanceWrapper!.instance);
      }
      instance[table.joinedBy!.name] = list;
    } else {
      final existingInnerInstance = instance[table.joinedBy!.name];

      // If not assigned yet, assign this value (which may be null). If assigned,
      // don't overwrite with a null row that may come after. Once we have it, we have it.

      // Now if it is belongsTo, we may have already populated it with the foreign key object.
      // In this case, we do need to override it
      if (existingInnerInstance == null) {
        instance[table.joinedBy!.name] = innerInstanceWrapper?.instance;
      }
    }
  }

  void applyColumnValueToProperty(
    ManagedObject instance,
    ColumnBuilder column,
    dynamic value,
  ) {
    final desc = column.property;

    if (desc is ManagedRelationshipDescription) {
      // This is a belongsTo relationship (otherwise it wouldn't be a column), keep the foreign key.
      if (value != null) {
        final innerInstance = desc.destinationEntity.instanceOf();
        innerInstance[desc.destinationEntity.primaryKey] = value;
        instance[desc.name] = innerInstance;
      } else {
        // If null, explicitly add null to map so the value is populated.
        instance[desc.name] = null;
      }
    } else if (desc is ManagedAttributeDescription) {
      instance[desc.name] = column.convertValueFromStorage(value);
    }
  }
}

class InstanceWrapper {
  InstanceWrapper(this.instance, this.isNew);

  bool isNew;
  ManagedObject instance;
}
