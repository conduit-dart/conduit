import 'package:collection/collection.dart' show IterableExtension;
import 'package:conduit_runtime/runtime.dart';
import 'package:reflectable/reflectable.dart';

Iterable<ClassMirror> classHierarchyForClass(ClassMirror t) sync* {
  var tableDefinitionPtr = t;
  while (tableDefinitionPtr.superclass != null) {
    yield tableDefinitionPtr;
    tableDefinitionPtr = tableDefinitionPtr.superclass!;
  }
}

T? firstMetadataOfType<T>(DeclarationMirror dm, {TypeMirror? dynamicType}) {
  final tMirror = dynamicType ?? runtimeReflector.reflectType(T);
  return dm.metadata.firstWhereOrNull(
      (im) => runtimeReflector.reflect(im).type.isSubtypeOf(tMirror)) as T?;
}

List<T> allMetadataOfType<T>(DeclarationMirror dm) {
  var tMirror = runtimeReflector.reflectType(T);
  return dm.metadata
      .where((im) => runtimeReflector.reflect(im).type.isSubtypeOf(tMirror))
      .map((im) => im)
      .toList()
      .cast<T>();
}

String getMethodAndClassName(VariableMirror mirror) {
  return "${mirror.owner.owner!.simpleName}.${mirror.owner.simpleName}";
}
