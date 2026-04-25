import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'package:conduit_build_runner/src/type_to_schema.dart';

/// Generates a `SerializableRuntime` subclass per `Serializable` class in
/// the input library, emitting `<input>.serializable.conduit.dart`
/// alongside each source file.
///
/// Phase 1 of the AOT-without-conduit-build migration. This builder is a
/// parallel implementation; the mirror-based
/// `SerializableRuntimeImpl` in `packages/core/lib/src/runtime/impl.dart`
/// stays in place. The aggregator that wires generated runtimes into
/// `RuntimeContext` lands in a later phase, so for now the output is
/// inert source you can read but not yet load.
class SerializableGenerator extends Generator {
  static const _serializableTypeName = 'Serializable';
  static const _serializablePackagePrefix = 'package:conduit_core/';

  @override
  String? generate(LibraryReader library, BuildStep buildStep) {
    final classes = library.classes
        .where((c) => !c.isAbstract && _implementsSerializable(c))
        .toList();
    if (classes.isEmpty) return null;

    final buffer = StringBuffer()
      ..writeln(
        "// GENERATED CODE - DO NOT MODIFY BY HAND. "
        "conduit_build_runner phase 1 (Serializable).",
      )
      ..writeln(
        "// ignore_for_file: type=lint, "
        "directives_ordering, no_leading_underscores_for_local_identifiers",
      )
      ..writeln()
      ..writeln("import 'package:conduit_core/conduit_core.dart';")
      ..writeln("import 'package:conduit_open_api/v3.dart';")
      ..writeln();

    for (final klass in classes) {
      buffer.writeln(_generateRuntimeFor(klass));
    }
    return buffer.toString();
  }

  bool _implementsSerializable(ClassElement element) {
    bool isSerializable(InterfaceType t) {
      final el = t.element;
      if (el.name != _serializableTypeName) return false;
      final libUri = el.library.identifier;
      return libUri.startsWith(_serializablePackagePrefix);
    }

    return element.allSupertypes.any(isSerializable);
  }

  String _generateRuntimeFor(ClassElement klass) {
    final className = klass.name;
    final propertyEntries = StringBuffer();

    for (final field in klass.fields) {
      if (field.isStatic) continue;
      final expression = schemaExpressionFor(field.type);
      propertyEntries
          .writeln("      '${field.name}': $expression,");
    }

    return '''
class \$${className}SerializableRuntime extends SerializableRuntime {
  const \$${className}SerializableRuntime();

  @override
  APISchemaObject documentSchema(APIDocumentContext context) {
    return APISchemaObject.object(<String, APISchemaObject>{
$propertyEntries    })
      ..title = '$className';
  }
}
''';
  }
}

Builder serializableBuilder(BuilderOptions options) =>
    LibraryBuilder(SerializableGenerator(),
        generatedExtension: '.serializable.conduit.dart');
