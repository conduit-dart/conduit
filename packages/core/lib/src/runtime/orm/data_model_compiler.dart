import 'dart:mirrors';

import 'package:conduit_core/src/db/managed/managed.dart';
import 'package:conduit_core/src/runtime/orm/entity_builder.dart';
import 'package:conduit_runtime/dev.dart';

class DataModelCompiler {
  /// When true, silently drop ManagedObject builders that fail to
  /// compile/validate/link instead of aborting the whole registry. The
  /// caller's [ManagedDataModel] still raises a clear "type not found"
  /// error if they later request a dropped type — but unrelated entities
  /// (e.g. `_ManagedAuthToken` whose `ResourceOwnerTableDefinition`
  /// concrete subclass isn't in this isolate) no longer prevent the
  /// rest of the workspace's tests from compiling their own data
  /// models.
  ///
  /// This restores the per-test-isolate semantics that pre-PR-#251
  /// `conduit build` provided. Set to `false` to get the old fail-fast
  /// behavior — useful for debugging "why is my data model not
  /// resolving?" issues.
  ///
  /// Override at runtime via the `CONDUIT_DATA_MODEL_TOLERATE_PARTIAL`
  /// env var (`0` / `false` to disable).
  static bool tolerateIncompleteBuilders =
      const String.fromEnvironment(
        'CONDUIT_DATA_MODEL_TOLERATE_PARTIAL',
        defaultValue: 'true',
      ).toLowerCase() != 'false' &&
      const String.fromEnvironment(
        'CONDUIT_DATA_MODEL_TOLERATE_PARTIAL',
        defaultValue: 'true',
      ) != '0';

  /// Errors collected per-type during the eager compile pass when
  /// [tolerateIncompleteBuilders] is on. [ManagedDataModel] reads from
  /// this map: if the user requests a type that was silently dropped,
  /// the constructor re-throws the original specific error rather than
  /// the generic "type not found" message — preserving the diagnostic
  /// quality the compilation_errors test suite asserts on.
  static final Map<Type, Object> compileErrors = {};

  Map<String, Object> compile(MirrorContext context) {
    final m = <String, Object>{};
    compileErrors.clear();

    final instanceTypes = context.types
        .where(_isTypeManagedObjectSubclass)
        .map((c) => c.reflectedType);

    _builders = instanceTypes.map((t) => EntityBuilder(t)).toList();

    // Phase 1: compile. With tolerance on, drop builders whose
    // relationships can't be resolved against the loaded mirror. The
    // caller's ManagedDataModel(types) will still raise cleanly if
    // they request a dropped type; unrelated entities are unaffected.
    final compiled = <EntityBuilder>[];
    for (final b in _builders) {
      try {
        b.compile(_builders);
        compiled.add(b);
      } catch (e) {
        if (!tolerateIncompleteBuilders) rethrow;
        compileErrors[b.instanceType.reflectedType] = e;
      }
    }
    _builders = compiled;

    // Phase 2: validate. Same tolerance — a builder may compile but
    // fail validation (e.g. duplicate-table conflict with another
    // dropped sibling). Skip individual validate() calls; keep the
    // duplicate-table check global since it operates on the surviving
    // set.
    _validate();

    // Phase 3: link + runtime extraction. A builder that compiled +
    // validated cleanly may still trip during link if a downstream
    // entity got dropped above. Drop it too.
    final entities = _builders.map((eb) => eb.entity).toList();
    final linked = <EntityBuilder>[];
    for (final b in _builders) {
      try {
        b.link(entities);
        m[b.entity.instanceType.toString()] = b.runtime;
        linked.add(b);
      } catch (e) {
        if (!tolerateIncompleteBuilders) rethrow;
        compileErrors[b.instanceType.reflectedType] = e;
      }
    }
    _builders = linked;

    return m;
  }

  late List<EntityBuilder> _builders;

  void _validate() {
    // Check for dupe tables. A duplicate-table conflict among
    // surviving builders is always fatal — that's a real workspace
    // bug, not a per-isolate import-graph artifact.
    for (final builder in _builders) {
      final withSameName = _builders
          .where((eb) => eb.name == builder.name)
          .map((eb) => eb.instanceTypeName)
          .toList();
      if (withSameName.length > 1) {
        throw ManagedDataModelErrorImpl.duplicateTables(
          builder.name,
          withSameName,
        );
      }
    }

    // Per-builder validation may trip on a property that depended on
    // a sibling that was dropped during compile. Drop the builder
    // here too rather than failing the whole registry.
    final validated = <EntityBuilder>[];
    for (final b in _builders) {
      try {
        b.validate(_builders);
        validated.add(b);
      } catch (e) {
        if (!tolerateIncompleteBuilders) rethrow;
        compileErrors[b.instanceType.reflectedType] = e;
      }
    }
    _builders = validated;
  }

  static bool _isTypeManagedObjectSubclass(ClassMirror mirror) {
    final managedObjectMirror = reflectClass(ManagedObject);

    if (!mirror.isSubclassOf(managedObjectMirror)) {
      return false;
    }

    if (!mirror.hasReflectedType) {
      return false;
    }

    if (mirror == managedObjectMirror) {
      return false;
    }

    // mirror.mixin: If this class is the result of a mixin application of the form S with M, returns a class mirror on M.
    // Otherwise returns a class mirror on the reflectee.
    if (mirror.mixin != mirror) {
      return false;
    }

    return true;
  }
}

class ManagedDataModelErrorImpl extends ManagedDataModelError {
  ManagedDataModelErrorImpl(super.message);

  factory ManagedDataModelErrorImpl.noPrimaryKey(ManagedEntity entity) {
    return ManagedDataModelErrorImpl(
        "Class '${_getPersistentClassName(entity)}'"
        " doesn't declare a primary key property or declares more than one primary key. All 'ManagedObject' subclasses "
        "must have a primary key. Usually, this means you want to add '@primaryKey int id;' "
        "to ${_getPersistentClassName(entity)}, but if you want more control over "
        "the type of primary key, declare the property as one of "
        "${ManagedType.supportedDartTypes.join(", ")} and "
        "add '@Column(primaryKey: true)' above it.");
  }

  factory ManagedDataModelErrorImpl.invalidType(
    Symbol tableSymbol,
    Symbol propertySymbol,
  ) {
    return ManagedDataModelErrorImpl(
        "Property '${_getName(propertySymbol)}' on "
        "'${_getName(tableSymbol)}'"
        " has an unsupported type. This can occur when the type cannot be stored in a database, or when"
        " a relationship does not have a valid inverse. If this property is supposed to be a relationship, "
        " ensure the inverse property annotation is 'Relate(#${_getName(propertySymbol)}, ...)'."
        " If this is not supposed to be a relationship property, its type must be one of: ${ManagedType.supportedDartTypes.join(", ")}.");
  }

  factory ManagedDataModelErrorImpl.invalidMetadata(
    String tableName,
    Symbol property,
  ) {
    return ManagedDataModelErrorImpl("Relationship '${_getName(property)}' on "
        "'$tableName' "
        "cannot both have 'Column' and 'Relate' metadata. "
        "To add flags for indexing or nullability to a relationship, see the constructor "
        "for 'Relate'.");
  }

  factory ManagedDataModelErrorImpl.missingInverse(
    String tableName,
    String instanceName,
    Symbol property,
    String destinationTableName,
    Symbol? expectedProperty,
  ) {
    var expectedString = "Some property";
    if (expectedProperty != null) {
      expectedString = "'${_getName(expectedProperty)}'";
    }
    return ManagedDataModelErrorImpl("Relationship '${_getName(property)}' on "
        "'$tableName' has "
        "no inverse property. Every relationship must have an inverse. "
        "$expectedString on "
        "'$destinationTableName'"
        "is supposed to exist, and it should be either a "
        "'$instanceName' or "
        "'ManagedSet<$instanceName>'.");
  }

  factory ManagedDataModelErrorImpl.incompatibleDeleteRule(
    String tableName,
    Symbol property,
  ) {
    return ManagedDataModelErrorImpl("Relationship '${_getName(property)}' on "
        "'$tableName' "
        "has both 'RelationshipDeleteRule.nullify' and 'isRequired' equal to true, which "
        "couldn't possibly be true at the same. 'isRequired' means the column "
        "can't be null and 'nullify' means the column has to be null.");
  }

  factory ManagedDataModelErrorImpl.dualMetadata(
    String tableName,
    Symbol property,
    String destinationTableName,
    String? inverseProperty,
  ) {
    return ManagedDataModelErrorImpl("Relationship '${_getName(property)}' "
        "on '$tableName' "
        "and '$inverseProperty' "
        "on '$destinationTableName' "
        "both have 'Relate' metadata, but only one can. "
        "The property with 'Relate' metadata is a foreign key column "
        "in the database.");
  }

  factory ManagedDataModelErrorImpl.duplicateInverse(
    String tableName,
    String? inverseName,
    List<String?> conflictingNames,
  ) {
    return ManagedDataModelErrorImpl(
        "Entity '$tableName' has multiple relationship "
        "properties that claim to be the inverse of '$inverseName'. A property may "
        "only have one inverse. The claiming properties are: ${conflictingNames.join(", ")}.");
  }

  factory ManagedDataModelErrorImpl.noDestinationEntity(
    String tableName,
    Symbol property,
    Symbol expectedType,
  ) {
    return ManagedDataModelErrorImpl("Relationship '${_getName(property)}' on "
        "'$tableName' expects that there is a subclass "
        "of 'ManagedObject' named '${_getName(expectedType)}', "
        "but there isn't one. If you have declared one - and you really checked "
        "hard for typos - make sure the file it is declared in is imported appropriately.");
  }

  factory ManagedDataModelErrorImpl.multipleDestinationEntities(
    String tableName,
    Symbol property,
    List<String> possibleEntities,
    Symbol expected,
  ) {
    return ManagedDataModelErrorImpl("Relationship '${_getName(property)}' on "
        "'$tableName' expects that just one "
        "'ManagedObject' subclass uses a table definition that extends "
        "'${_getName(expected)}. But the following implementations were found: "
        "${possibleEntities.join(",")}. That's just "
        "how it is for now.");
  }

  factory ManagedDataModelErrorImpl.invalidTransient(
    ManagedEntity entity,
    Symbol property,
  ) {
    return ManagedDataModelErrorImpl(
        "Transient property '${_getName(property)}' on "
        "'${_getInstanceClassName(entity)}' declares that "
        "it is transient, but it it has a mismatch. A transient "
        "getter method must have 'isAvailableAsOutput' and a transient "
        "setter method must have 'isAvailableAsInput'.");
  }

  factory ManagedDataModelErrorImpl.noConstructor(ClassMirror cm) {
    final name = _getName(cm.simpleName);
    return ManagedDataModelErrorImpl("Invalid 'ManagedObject' subclass "
        "'$name' does not implement default, unnamed constructor. "
        "Add '$name();' to the class declaration.");
  }

  factory ManagedDataModelErrorImpl.duplicateTables(
    String? tableName,
    List<String> instanceTypes,
  ) {
    return ManagedDataModelErrorImpl(
        "Entities ${instanceTypes.map((i) => "'$i'").join(",")} "
        "have the same table name: '$tableName'. Rename these "
        "the table definitions, or add a '@Table(name: ...)' annotation to the table definition.");
  }

  factory ManagedDataModelErrorImpl.conflictingTypes(
    ManagedEntity entity,
    String propertyName,
  ) {
    return ManagedDataModelErrorImpl(
        "The entity '${_getInstanceClassName(entity)}' declares two accessors named "
        "'$propertyName', but they have conflicting types.");
  }

  factory ManagedDataModelErrorImpl.invalidValidator(
    ManagedEntity entity,
    String property,
    String reason,
  ) {
    return ManagedDataModelErrorImpl(
        "Type '${_getPersistentClassName(entity)}' "
        "has invalid validator for property '$property'. Reason: $reason");
  }

  factory ManagedDataModelErrorImpl.emptyEntityUniqueProperties(
    String tableName,
  ) {
    return ManagedDataModelErrorImpl("Type '$tableName' "
        "has empty set for unique 'Table'. Must contain two or "
        "more attributes (or belongs-to relationship properties).");
  }

  factory ManagedDataModelErrorImpl.singleEntityUniqueProperty(
    String tableName,
    Symbol property,
  ) {
    return ManagedDataModelErrorImpl("Type '$tableName' "
        "has only one attribute for unique 'Table'. Must contain two or "
        "more attributes (or belongs-to relationship properties). To make this property unique, "
        "add 'Column(unique: true)' to declaration of '${_getName(property)}'.");
  }

  factory ManagedDataModelErrorImpl.invalidEntityUniqueProperty(
    String tableName,
    Symbol property,
  ) {
    return ManagedDataModelErrorImpl("Type '$tableName' "
        "declares '${MirrorSystem.getName(property)}' as unique in 'Table', "
        "but '${MirrorSystem.getName(property)}' is not a property of this type.");
  }

  factory ManagedDataModelErrorImpl.relationshipEntityUniqueProperty(
    String tableName,
    Symbol property,
  ) {
    return ManagedDataModelErrorImpl("Type '$tableName' "
        "declares '${_getName(property)}' as unique in 'Table'. This property cannot "
        "be used to make an instance unique; only attributes or belongs-to relationships may used "
        "in this way.");
  }

  static String? _getPersistentClassName(ManagedEntity entity) {
    // if (entity == null) {
    //   return null;
    // }

    // if (entity.tableDefinition == null) {
    //   return null;
    // }

    return entity.tableDefinition;
  }

  static String _getInstanceClassName(ManagedEntity entity) {
    // if (entity.instanceType == null) {
    //   return null;
    // }

    return _getName(reflectType(entity.instanceType).simpleName);
  }

  static String _getName(Symbol s) => MirrorSystem.getName(s);
}
