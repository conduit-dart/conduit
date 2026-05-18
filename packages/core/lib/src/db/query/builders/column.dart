/// Dialect-agnostic column builders.
///
/// These types compose SQL fragments (column references, type-aware
/// value coercion, predicate operator spellings) without baking in
/// any particular driver's value-wrapping convention. The Postgres
/// backend used to wrap every value with a `TypedValue` from
/// `package:postgres`; that wrapping now lives behind
/// `SqlDialect.encodeValue` so the builders themselves are reusable
/// across SQLite, MySQL, and Cockroach.
library;

import 'package:conduit_core/src/db/managed/document.dart';
import 'package:conduit_core/src/db/managed/entity.dart';
import 'package:conduit_core/src/db/managed/exception.dart';
import 'package:conduit_core/src/db/managed/key_path.dart';
import 'package:conduit_core/src/db/managed/property_description.dart';
import 'package:conduit_core/src/db/managed/relationship_type.dart';
import 'package:conduit_core/src/db/managed/type.dart';
import 'package:conduit_core/src/db/query/builders/table.dart';
import 'package:conduit_core/src/db/query/predicate.dart';

/// Common interface for values that can be mapped to/from a database.
abstract class Returnable {}

class ColumnBuilder extends Returnable {
  ColumnBuilder(this.table, this.property, {this.documentKeyPath});

  static List<Returnable> fromKeys(TableBuilder table, List<KeyPath> keys) {
    final entity = table.entity;

    // Ensure the primary key is always available and at 0th index.
    int primaryKeyIndex = -1;
    for (var i = 0; i < keys.length; i++) {
      final firstElement = keys[i].path.first;
      if (firstElement is ManagedAttributeDescription &&
          firstElement.isPrimaryKey) {
        primaryKeyIndex = i;
        break;
      }
    }

    if (primaryKeyIndex == -1) {
      keys.insert(0, KeyPath(entity.primaryKeyAttribute));
    } else if (primaryKeyIndex > 0) {
      keys.removeAt(primaryKeyIndex);
      keys.insert(0, KeyPath(entity.primaryKeyAttribute));
    }

    return List.from(
      keys.map((key) {
        return ColumnBuilder(
          table,
          propertyForName(entity, key.path.first!.name),
          documentKeyPath: key.dynamicElements,
        );
      }),
    );
  }

  static ManagedPropertyDescription propertyForName(
    ManagedEntity entity,
    String? propertyName,
  ) {
    final property = entity.properties[propertyName];

    if (property == null) {
      throw ArgumentError(
        "Could not construct query. Column '$propertyName' does not exist for table '${entity.tableName}'.",
      );
    }

    if (property is ManagedRelationshipDescription &&
        property.relationshipType != ManagedRelationshipType.belongsTo) {
      throw ArgumentError(
          "Could not construct query. Column '$propertyName' does not exist for table '${entity.tableName}'. "
          "'$propertyName' recognized as ORM relationship, use 'Query.join' instead.");
    }

    return property;
  }

  /// Comparison-operator spelling. The LIKE / ILIKE operators are
  /// dialect-driven (see `SqlDialect.caseSensitiveLikeOperator` /
  /// `caseInsensitiveLikeOperator`); the comparison operators here
  /// are universal across dialects we currently target.
  static Map<PredicateOperator, String> symbolTable = {
    PredicateOperator.lessThan: "<",
    PredicateOperator.greaterThan: ">",
    PredicateOperator.notEqual: "!=",
    PredicateOperator.lessThanEqualTo: "<=",
    PredicateOperator.greaterThanEqualTo: ">=",
    PredicateOperator.equalTo: "="
  };

  final TableBuilder? table;
  final ManagedPropertyDescription? property;
  final List<dynamic>? documentKeyPath;

  dynamic convertValueForStorage(dynamic value) {
    if (value == null) {
      return null;
    }

    if (property is ManagedAttributeDescription) {
      final p = property as ManagedAttributeDescription;
      if (p.isEnumeratedValue) {
        return value.toString().split(".").last;
      } else if (p.type!.kind == ManagedPropertyType.document) {
        if (value is Document) {
          return value.data;
        } else if (value is Map || value is List) {
          return value;
        }

        throw ArgumentError(
          "Invalid data type for 'Document'. Must be 'Document', 'Map', or 'List'.",
        );
      }
    }

    return value;
  }

  dynamic convertValueFromStorage(dynamic value) {
    if (value == null) {
      return null;
    }

    if (property is ManagedAttributeDescription) {
      final p = property as ManagedAttributeDescription;
      if (p.isEnumeratedValue) {
        if (!p.enumerationValueMap.containsKey(value)) {
          throw ValidationException(["invalid option for key '${p.name}'"]);
        }
        return p.enumerationValueMap[value];
      } else if (p.type!.kind == ManagedPropertyType.document) {
        return Document(value);
      }
    }

    return value;
  }

  String sqlColumnName({
    bool withTableNamespace = false,
    String? withPrefix,
  }) {
    var name = property!.name;

    if (property is ManagedRelationshipDescription) {
      final relatedPrimaryKey = (property as ManagedRelationshipDescription)
          .destinationEntity
          .primaryKey;
      name = "${name}_$relatedPrimaryKey";
    } else if (documentKeyPath != null) {
      final keys =
          documentKeyPath!.map((k) => k is String ? "'$k'" : k).join("->");
      name = "$name->$keys";
    }

    if (withTableNamespace) {
      return "${table!.sqlTableReference}.$name";
    } else if (withPrefix != null) {
      return "$withPrefix$name";
    }

    return name;
  }
}
