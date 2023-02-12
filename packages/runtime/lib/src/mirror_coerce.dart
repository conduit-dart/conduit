import 'dart:mirrors';

import 'package:conduit_runtime/src/exceptions.dart';

dynamic runtimeCast(dynamic object, TypeMirror intoType) {
  final exceptionToThrow =
      TypeCoercionException(intoType.reflectedType, object.runtimeType);

  try {
    final objectType = reflect(object).type;
    if (objectType.isAssignableTo(intoType)) {
      return object;
    }

    if (intoType.isSubtypeOf(reflectType(List))) {
      if (object is! List) {
        throw exceptionToThrow;
      }

      final elementType = intoType.typeArguments.first;
      final elements = object.map((e) => runtimeCast(e, elementType));
      return (intoType as ClassMirror).newInstance(#from, [elements]).reflectee;
    } else if (intoType.isSubtypeOf(reflectType(Map, [String, dynamic]))) {
      if (object is! Map<String, dynamic>) {
        throw exceptionToThrow;
      }

      final output = (intoType as ClassMirror)
          .newInstance(Symbol.empty, []).reflectee as Map<String, dynamic>;
      final valueType = intoType.typeArguments.last;
      object.forEach((key, val) {
        output[key] = runtimeCast(val, valueType);
      });
      return output;
    }
  } on TypeError catch (_) {
    throw exceptionToThrow;
  } on TypeCoercionException catch (_) {
    throw exceptionToThrow;
  }

  throw exceptionToThrow;
}

bool isTypeFullyPrimitive(TypeMirror type) {
  if (type == reflectType(dynamic)) {
    return true;
  }

  if (type.isSubtypeOf(reflectType(List))) {
    return isTypeFullyPrimitive(type.typeArguments.first);
  } else if (type.isSubtypeOf(reflectType(Map))) {
    return isTypeFullyPrimitive(type.typeArguments.first) &&
        isTypeFullyPrimitive(type.typeArguments.last);
  }

  if (type.isSubtypeOf(reflectType(num))) {
    return true;
  }

  if (type.isSubtypeOf(reflectType(String))) {
    return true;
  }

  if (type.isSubtypeOf(reflectType(bool))) {
    return true;
  }

  return false;
}
