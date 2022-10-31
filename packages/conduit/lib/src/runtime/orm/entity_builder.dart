import 'dart:mirrors';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:conduit/src/db/managed/managed.dart';
import 'package:conduit/src/db/managed/relationship_type.dart';
import 'package:conduit/src/runtime/orm/data_model_compiler.dart';
import 'package:conduit/src/runtime/orm/entity_mirrors.dart';
import 'package:conduit/src/runtime/orm/property_builder.dart';
import 'package:conduit/src/runtime/orm_impl.dart';
import 'package:conduit/src/utilities/mirror_helpers.dart';
import 'package:logging/logging.dart';

class EntityBuilder {
  EntityBuilder(Type type)
      : instanceType = reflectClass(type),
        tableDefinitionType = getTableDefinitionForType(type),
        metadata = firstMetadataOfType(getTableDefinitionForType(type)) {
    name = _getName();

    entity = ManagedEntity(
      name,
      type,
      MirrorSystem.getName(tableDefinitionType.simpleName),
    )..validators = [];

    runtime = ManagedEntityRuntimeImpl(instanceType, entity);

    properties = _getProperties();
    final primaryKeyProperty1 =
        properties.firstWhereOrNull((p) => p.column?.isPrimaryKey ?? false);
    if (primaryKeyProperty1 == null) {
      throw ManagedDataModelErrorImpl.noPrimaryKey(entity);
    }

    primaryKeyProperty = primaryKeyProperty1;
  }

  final ClassMirror instanceType;
  final ClassMirror tableDefinitionType;
  final Table? metadata;

  ManagedEntityRuntime? runtime;

  String? name;
  late ManagedEntity entity;
  List<String>? uniquePropertySet;
  late PropertyBuilder primaryKeyProperty;
  List<PropertyBuilder> properties = [];
  Map<String?, ManagedAttributeDescription?> attributes = {};
  Map<String?, ManagedRelationshipDescription?> relationships = {};

  String get instanceTypeName => MirrorSystem.getName(instanceType.simpleName);

  String get tableDefinitionTypeName =>
      MirrorSystem.getName(tableDefinitionType.simpleName);

  void compile(List<EntityBuilder>? entityBuilders) {
    for (final p in properties) {
      p.compile(entityBuilders);
    }

    uniquePropertySet =
        metadata?.uniquePropertySet?.map(MirrorSystem.getName).toList();
  }

  void validate(List<EntityBuilder>? entityBuilders) {
    // Check that we have a default constructor
    if (!classHasDefaultConstructor(instanceType)) {
      throw ManagedDataModelErrorImpl.noConstructor(instanceType);
    }

    // Check that we only have one primary key
    if (properties.where((pb) => pb.primaryKey).length != 1) {
      throw ManagedDataModelErrorImpl.noPrimaryKey(entity);
    }

    // Check that our unique property set is valid
    if (uniquePropertySet != null) {
      if (uniquePropertySet!.isEmpty) {
        throw ManagedDataModelErrorImpl.emptyEntityUniqueProperties(
          tableDefinitionTypeName,
        );
      } else if (uniquePropertySet!.length == 1) {
        throw ManagedDataModelErrorImpl.singleEntityUniqueProperty(
          tableDefinitionTypeName,
          metadata!.uniquePropertySet!.first,
        );
      }

      for (final key in uniquePropertySet!) {
        final prop = properties.firstWhere(
          (p) => p.name == key,
          orElse: () {
            throw ManagedDataModelErrorImpl.invalidEntityUniqueProperty(
              tableDefinitionTypeName,
              Symbol(key),
            );
          },
        );

        if (prop.isRelationship &&
            prop.relationshipType != ManagedRelationshipType.belongsTo) {
          throw ManagedDataModelErrorImpl.relationshipEntityUniqueProperty(
            tableDefinitionTypeName,
            Symbol(key),
          );
        }
      }
    }

    // Check that relationships are unique, i.e. two Relates point to the same property
    properties.where((p) => p.isRelationship).forEach((p) {
      final relationshipsWithThisInverse = properties
          .where(
            (check) =>
                check.isRelationship &&
                check.relatedProperty == p.relatedProperty,
          )
          .toList();
      if (relationshipsWithThisInverse.length > 1) {
        throw ManagedDataModelErrorImpl.duplicateInverse(
          tableDefinitionTypeName,
          p.relatedProperty!.name,
          relationshipsWithThisInverse.map((r) => r.name).toList(),
        );
      }
    });

    // Check each property
    for (final p in properties) {
      p.validate(entityBuilders);
    }
  }

  void link(List<ManagedEntity> entities) {
    entity.symbolMap = {};
    for (final p in properties) {
      p.link(entities);

      entity.symbolMap[Symbol(p.name)] = p.name;
      entity.symbolMap[Symbol("${p.name}=")] = p.name;

      if (p.isRelationship) {
        relationships[p.name] = p.relationship;
      } else {
        attributes[p.name] = p.attribute;
        if (p.primaryKey) {
          entity.primaryKey = p.name;
        }
      }
    }

    entity.attributes = attributes;
    entity.relationships = relationships;
    entity.validators = [];
    entity.validators.addAll(attributes.values.expand((a) => a!.validators));
    entity.validators.addAll(relationships.values.expand((a) => a!.validators));
    entity.uniquePropertySet =
        uniquePropertySet?.map((key) => entity.properties[key]).toList();
  }

  PropertyBuilder getInverseOf(PropertyBuilder foreignKey) {
    final expectedSymbol = foreignKey.relate!.inversePropertyName;
    var finder =
        (PropertyBuilder p) => p.declaration.simpleName == expectedSymbol;
    if (foreignKey.relate!.isDeferred) {
      finder = (p) {
        final propertyType = p.getDeclarationType();
        if (propertyType.isSubtypeOf(reflectType(ManagedSet))) {
          return propertyType.typeArguments.first
              .isSubtypeOf(foreignKey.parent.tableDefinitionType);
        }
        return propertyType.isSubtypeOf(foreignKey.parent.tableDefinitionType);
      };
    }

    final candidates = properties.where(finder).toList();
    if (candidates.length == 1) {
      return candidates.first;
    } else if (candidates.isEmpty) {
      throw ManagedDataModelErrorImpl.missingInverse(
        foreignKey.parent.tableDefinitionTypeName,
        foreignKey.parent.instanceTypeName,
        foreignKey.declaration.simpleName,
        tableDefinitionTypeName,
        null,
      );
    }

    throw ManagedDataModelError(
        "The relationship '${foreignKey.name}' on '${foreignKey.parent.tableDefinitionTypeName}' "
        "has multiple inverse candidates. There must be exactly one property that is a subclass of the expected type "
        "('${MirrorSystem.getName(foreignKey.getDeclarationType().simpleName)}'), but the following are all possible:"
        " ${candidates.map((p) => p.name).join(", ")}");
  }

  String? _getName() {
    if (metadata?.name != null) {
      return metadata!.name;
    }

    final declaredTableNameClass = classHierarchyForClass(tableDefinitionType)
        .firstWhereOrNull((cm) => cm.staticMembers[#tableName] != null);

    if (declaredTableNameClass == null) {
      return tableDefinitionTypeName;
    }

    Logger("conduit").warning(
      "Overriding ManagedObject.tableName is deprecated. Use '@Table(name: ...)' instead.",
    );
    return declaredTableNameClass.invoke(#tableName, []).reflectee as String?;
  }

  List<PropertyBuilder> _getProperties() {
    final transientProperties = _getTransientAttributes();
    final persistentProperties = instanceVariablesFromClass(tableDefinitionType)
        .map((p) => PropertyBuilder(this, p))
        .toList();

    return [transientProperties, persistentProperties]
        .expand((l) => l)
        .toList();
  }

  Iterable<PropertyBuilder> _getTransientAttributes() {
    final attributes = instanceType.declarations.values
        .where(isTransientPropertyOrAccessor)
        .map((declaration) => PropertyBuilder(this, declaration))
        .toList();

    if (instanceType.superclass!.mixin != instanceType.superclass) {
      final mixin = instanceType.superclass!.mixin.declarations.values
          .where(isTransientPropertyOrAccessor)
          .map((declaration) => PropertyBuilder(this, declaration))
          .toList();
      attributes.addAll(mixin);
    }

    final out = <PropertyBuilder>[];
    for (final prop in attributes) {
      final complement = out.firstWhereOrNull((pb) => pb.name == prop.name);
      if (complement != null) {
        complement.serialize = const Serialize();
      } else {
        out.add(prop);
      }
    }

    return out;
  }

  static ClassMirror getTableDefinitionForType(Type instanceType) {
    final ifNotFoundException = ManagedDataModelError(
      "Invalid instance type '$instanceType' '${reflectClass(instanceType).simpleName}' is not subclass of 'ManagedObject'.",
    );

    return classHierarchyForClass(reflectClass(instanceType))
        .firstWhere(
          (cm) => !cm.superclass!.isSubtypeOf(reflectType(ManagedObject)),
          orElse: () => throw ifNotFoundException,
        )
        .typeArguments
        .first as ClassMirror;
  }
}
