import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';

/// Returns a Dart expression that constructs an `APISchemaObject` describing
/// [type], suitable for emission into generated source.
///
/// Mirrors the type dispatch in
/// `packages/core/lib/src/runtime/impl.dart::SerializableRuntimeImpl.documentType`,
/// but operates on analyzer's [DartType] instead of `dart:mirrors`'
/// `TypeMirror`. Throws [InvalidGenerationSourceError] for types this
/// phase does not yet handle (custom `Serializable` subclasses are
/// deferred to phase 2 once the registry exists).
String schemaExpressionFor(DartType type) {
  if (type.isDartCoreInt) return 'APISchemaObject.integer()';
  if (type.isDartCoreDouble || type.isDartCoreNum) {
    return 'APISchemaObject.number()';
  }
  if (type.isDartCoreString) return 'APISchemaObject.string()';
  if (type.isDartCoreBool) return 'APISchemaObject.boolean()';

  final element = type.element;
  if (element != null && element.name == 'DateTime') {
    return "APISchemaObject.string(format: 'date-time')";
  }

  if (type is InterfaceType && type.isDartCoreList) {
    final inner = type.typeArguments.isEmpty
        ? null
        : type.typeArguments.first;
    if (inner == null) {
      throw InvalidGenerationSourceError(
        "List property is missing a type argument; "
        "Conduit requires a concrete element type.",
      );
    }
    return 'APISchemaObject.array(ofSchema: ${schemaExpressionFor(inner)})';
  }

  if (type is InterfaceType && type.isDartCoreMap) {
    if (type.typeArguments.length < 2 ||
        !type.typeArguments.first.isDartCoreString) {
      throw InvalidGenerationSourceError(
        "Map property must use String keys.",
      );
    }
    final value = type.typeArguments.last;
    return '(APISchemaObject()'
        '..type = APIType.object'
        '..additionalPropertySchema = ${schemaExpressionFor(value)})';
  }

  throw InvalidGenerationSourceError(
    "Unsupported property type '$type' in a Serializable. "
    "Phase 1 of conduit_build_runner handles primitives, DateTime, "
    "List<X>, and Map<String, X>. Other Serializable subclasses are "
    "deferred until the runtime registry lands.",
  );
}
