import 'dart:mirrors';

import 'package:conduit_core/src/db/managed/managed.dart';
import 'package:conduit_runtime/dev.dart';

class ManagedEntityRuntimeImpl extends ManagedEntityRuntime {
  ManagedEntityRuntimeImpl(this.instanceType, this.entity);

  final ClassMirror instanceType;

  @override
  final ManagedEntity entity;

  @override
  ManagedObject instanceOfImplementation({ManagedBacking? backing}) {
    try {
      final object = instanceType.newInstance(Symbol.empty, []).reflectee
          as ManagedObject;

      if (backing != null) {
        object.backing = backing;
      }
      return object;
    } on TypeError {
      throw StateError('No implementation found for $instanceType');
    }
  }

  @override
  void setTransientValueForKey(
    ManagedObject object,
    String key,
    dynamic value,
  ) {
    reflect(object).setField(Symbol(key), value);
  }

  @override
  ManagedSet setOfImplementation(Iterable<dynamic> objects) {
    final type =
        reflectType(ManagedSet, [instanceType.reflectedType]) as ClassMirror;
    final set = type
        .newInstance(const Symbol("fromDynamic"), [objects]).reflectee
        as ManagedSet?;

    if (set == null) {
      throw StateError('No set implementation found for $instanceType');
    }

    return set;
  }

  @override
  dynamic getTransientValueForKey(ManagedObject object, String? key) {
    return reflect(object).getField(Symbol(key!)).reflectee;
  }

  @override
  bool isValueInstanceOf(dynamic value) {
    return reflect(value).type.isAssignableTo(instanceType);
  }

  @override
  bool isValueListOf(dynamic value) {
    final type = reflect(value).type;

    if (!type.isSubtypeOf(reflectType(List))) {
      return false;
    }

    return type.typeArguments.first.isAssignableTo(instanceType);
  }

  @override
  String? getPropertyName(Invocation invocation, ManagedEntity entity) {
    // If memberName is not in symbolMap, it may be because that property
    // doesn't exist for this object's entity. It may also occur for
    // private ivars, in which case we reconstruct the symbol and retry.
    return entity.symbolMap[invocation.memberName] ??
        entity.symbolMap[Symbol(MirrorSystem.getName(invocation.memberName))];
  }

  @override
  dynamic dynamicConvertFromPrimitiveValue(
    ManagedPropertyDescription property,
    dynamic value,
  ) {
    return runtimeCast(value, reflectType(property.type!.type));
  }
}
