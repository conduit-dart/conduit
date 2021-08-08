import 'package:conduit/src/db/managed/managed.dart';
import 'package:conduit/src/db/managed/validation/metadata.dart';
import 'package:conduit/src/utilities/mirror_helpers.dart';
import 'package:conduit_runtime/runtime.dart' show runtimeReflector;
import 'package:reflectable/reflectable.dart';

ManagedType getManagedTypeFromType(TypeMirror type) {
  ManagedPropertyType kind;
  ManagedType? elements;
  Map<String, dynamic> enumerationMap = {};

  if (type.isAssignableTo(runtimeReflector.reflectType(int))) {
    kind = ManagedPropertyType.integer;
  } else if (type.isAssignableTo(runtimeReflector.reflectType(String))) {
    kind = ManagedPropertyType.string;
  } else if (type.isAssignableTo(runtimeReflector.reflectType(DateTime))) {
    kind = ManagedPropertyType.datetime;
  } else if (type.isAssignableTo(runtimeReflector.reflectType(bool))) {
    kind = ManagedPropertyType.boolean;
  } else if (type.isAssignableTo(runtimeReflector.reflectType(double))) {
    kind = ManagedPropertyType.doublePrecision;
  } else if (type.isSubtypeOf(runtimeReflector.reflectType(Map))) {
    if (!type.typeArguments.first
        .isAssignableTo(runtimeReflector.reflectType(String))) {
      throw UnsupportedError(
          "Invalid type '${type.reflectedType}' for 'ManagedType'. Key is invalid; must be 'String'.");
    }
    kind = ManagedPropertyType.map;
    elements = getManagedTypeFromType(type.typeArguments.last);
  } else if (type.isSubtypeOf(runtimeReflector.reflectType(List))) {
    kind = ManagedPropertyType.list;
    elements = getManagedTypeFromType(type.typeArguments.first);
  } else if (type.isAssignableTo(runtimeReflector.reflectType(Document))) {
    kind = ManagedPropertyType.document;
  } else if (type is ClassMirror && type.isEnum) {
    kind = ManagedPropertyType.string;
    final enumeratedCases = type.invokeGetter('values') as List<dynamic>;
    for (final v in enumeratedCases) {
      enumerationMap[v.toString().split(".").last] = v;
    }
  } else {
    throw UnsupportedError(
        "Invalid type '${type.reflectedType}' for 'ManagedType'.");
  }

  return ManagedType(type.reflectedType, kind, elements, enumerationMap);
}

// Expanding the list of ivars for each class yields duplicates of
// any ivar is overridden. Since the order in which ivars are returned
// is known (a subclass' ivars always come before its superclass'),
// we can simply fold this list so that the first ivar 'wins'.
List<VariableMirror> instanceVariablesFromClass(ClassMirror classMirror) {
  return classHierarchyForClass(classMirror)
      .expand((cm) => cm.declarations.values
          .where(isInstanceVariableMirror)
          .map((decl) => decl as VariableMirror))
      .fold(<VariableMirror>[], (List<VariableMirror> acc, decl) {
    if (!acc.any((vm) => vm.simpleName == decl.simpleName)) {
      acc.add(decl);
    }

    return acc;
  }).toList();
}

bool classHasDefaultConstructor(ClassMirror type) {
  return type.declarations.values.any((dm) {
    return dm is MethodMirror &&
        dm.isConstructor &&
        dm.constructorName == '' &&
        dm.parameters.every((p) => p.isOptional == true);
  });
}

bool isInstanceVariableMirror(DeclarationMirror mirror) =>
    mirror is VariableMirror && !mirror.isStatic;

bool hasTransientMetadata(DeclarationMirror mirror) =>
    transientMetadataFromDeclaration(mirror) != null;

bool isTransientProperty(DeclarationMirror declaration) {
  return isInstanceVariableMirror(declaration) &&
      hasTransientMetadata(declaration);
}

bool isTransientAccessorMethod(DeclarationMirror declMir) {
  if (declMir is! MethodMirror) {
    return false;
  }

  var methodMirror = declMir;
  if (methodMirror.isStatic) {
    return false;
  }

  if (!(methodMirror.isSetter || methodMirror.isGetter) ||
      methodMirror.isSynthetic) {
    return false;
  }

  var mapMetadata = transientMetadataFromDeclaration(declMir);
  if (mapMetadata == null) {
    return false;
  }

  // A setter must be available as an input ONLY, a getter must be available as an output. This is confusing.
  return (methodMirror.isSetter && mapMetadata.isAvailableAsInput) ||
      (methodMirror.isGetter && mapMetadata.isAvailableAsOutput);
}

bool isTransientPropertyOrAccessor(DeclarationMirror declaration) {
  return isTransientAccessorMethod(declaration) ||
      isTransientProperty(declaration);
}

List<Validate> validatorsFromDeclaration(DeclarationMirror dm) =>
    allMetadataOfType<Validate>(dm);

Serialize? transientMetadataFromDeclaration(DeclarationMirror dm) =>
    firstMetadataOfType(dm);
