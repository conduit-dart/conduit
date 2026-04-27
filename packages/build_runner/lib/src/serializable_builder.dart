import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';

import 'package:conduit_build_runner/src/type_to_schema.dart';

/// Generates a `SerializableRuntime` subclass per `Serializable` class in
/// the input library.
///
/// Emits two siblings per source library:
///  - `<src>.serializable.conduit.dart` — runtime code with one
///    `$<Class>SerializableRuntime` per discovered class.
///  - `<src>.serializable.conduit.json` — manifest the registry builder
///    reads to discover runtime classes. Schema:
///    `{"serializables": ["UserPayload", ...]}`.
class SerializableBuilder implements Builder {
  static const _serializableTypeName = 'Serializable';
  static const _serializablePackagePrefix = 'package:conduit_core/';

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': [
          '.serializable.conduit.dart',
          '.serializable.conduit.json',
        ],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    if (!await buildStep.resolver.isLibrary(input)) return;
    final lib = await buildStep.inputLibrary;

    final classes = lib.classes
        .where((c) => !c.isAbstract && _implementsSerializable(c))
        .toList();

    if (classes.isEmpty) return;

    final manifest = {
      'serializables': classes.map((c) => c.name).toList(),
    };
    await buildStep.writeAsString(
      input.changeExtension('.serializable.conduit.json'),
      json.encode(manifest),
    );

    final buffer = StringBuffer()
      ..writeln(
        '// GENERATED CODE - DO NOT MODIFY BY HAND. '
        'conduit_build_runner SerializableBuilder.',
      )
      ..writeln(
        '// ignore_for_file: type=lint, directives_ordering, '
        'no_leading_underscores_for_local_identifiers',
      )
      ..writeln()
      ..writeln("import 'package:conduit_core/aot.dart';")
      ..writeln("import 'package:conduit_open_api/v3.dart';")
      ..writeln();

    for (final klass in classes) {
      buffer.writeln(_generateRuntimeFor(klass));
    }

    await buildStep.writeAsString(
      input.changeExtension('.serializable.conduit.dart'),
      buffer.toString(),
    );
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
      propertyEntries.writeln("      '${field.name}': $expression,");
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

Builder serializableBuilder(BuilderOptions options) => SerializableBuilder();
