import 'package:reflectable/reflectable.dart';
import 'exceptions.dart';
import 'reflector.dart';

dynamic runtimeCast(dynamic object, Type type) {
  if (type == dynamic || object == null) {
    return object;
  }

  final intoType = runtimeReflector.reflectType(type);
  final exceptionToThrow =
      TypeCoercionException(intoType.reflectedType, object.runtimeType);

  try {
    final objectType = runtimeReflector.reflect(object).type;
    if (objectType.isAssignableTo(intoType)) {
      return object;
    }

    if (intoType.isSubtypeOf(runtimeReflector.reflectType(List))) {
      if (object is! List) {
        throw exceptionToThrow;
      }

      final elementType = intoType.typeArguments.first;
      final elements =
          object.map((e) => runtimeCast(e, elementType.reflectedType));
      return (intoType as ClassMirror).newInstance("from", [elements]);
    } else if (intoType.isSubtypeOf(runtimeReflector.reflectType(Map))) {
      if (object is! Map<String, dynamic>) {
        throw exceptionToThrow;
      }

      final output =
          (intoType as ClassMirror).newInstance("", []) as Map<String, dynamic>;
      final valueType = intoType.typeArguments.last;
      object.forEach((key, val) {
        output[key] = runtimeCast(val, valueType.reflectedType);
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
  if (type == dynamic) {
    return true;
  }

  if (type.isSubtypeOf(runtimeReflector.reflectType(List))) {
    return isTypeFullyPrimitive(type.typeArguments.first);
  } else if (type.isSubtypeOf(runtimeReflector.reflectType(Map))) {
    return isTypeFullyPrimitive(type.typeArguments.first) &&
        isTypeFullyPrimitive(type.typeArguments.last);
  }

  if (type.isSubtypeOf(runtimeReflector.reflectType(num))) {
    return true;
  }

  if (type.isSubtypeOf(runtimeReflector.reflectType(String))) {
    return true;
  }

  if (type.isSubtypeOf(runtimeReflector.reflectType(bool))) {
    return true;
  }

  return false;
}
