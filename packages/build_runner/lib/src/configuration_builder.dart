import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';

/// Generates a `ConfigurationRuntime` per `Configuration` subclass in the
/// input library, replacing the mirror-based `ConfigurationRuntimeImpl` in
/// `packages/config/lib/src/runtime.dart` for the AOT path.
///
/// Emits two siblings per source library:
///  - `<src>.config.conduit.dart` — runtime code with one
///    `$<Class>ConfigurationRuntime` per concrete Configuration subclass.
///  - `<src>.config.conduit.json` — manifest the registry builder reads
///    so `bootstrap()` registers the runtimes. Schema:
///    `{"configurations": ["MyConfig", ...]}`.
///
/// Supported field types: `int`, `bool`, `String`, `double`, `num`,
/// `DateTime`, nested `Configuration` subclasses, `List<T>`, `Map<String, T>`
/// (with arbitrarily nested element types).
///
/// The mirror impl reads `@ConfigurationItemAttribute` (the legacy
/// `required` / `optional` const annotations) to determine whether a
/// field is required. We honor that annotation here, plus we treat any
/// non-nullable field declared with `late` as required because access
/// would throw if it were not set anyway.
class ConfigurationBuilder implements Builder {
  static const _configPackagePrefix = 'package:conduit_config/';
  static const _configurationTypeName = 'Configuration';

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.config.conduit.dart', '.config.conduit.json'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    if (!await buildStep.resolver.isLibrary(input)) return;
    final lib = await buildStep.inputLibrary;

    final configs = <_ConfigAnalysis>[];
    for (final klass in lib.classes) {
      if (klass.isAbstract) continue;
      final analysis = _analyze(klass);
      if (analysis != null) configs.add(analysis);
    }

    if (configs.isEmpty) return;

    final manifest = {
      'configurations': configs.map((c) => c.className).toList(),
    };
    await buildStep.writeAsString(
      input.changeExtension('.config.conduit.json'),
      json.encode(manifest),
    );

    final inputUri = input.uri.toString();
    final extraImports = <String>{};
    for (final c in configs) {
      extraImports.addAll(c.requiredImportUris);
    }
    extraImports.removeWhere((u) => u == inputUri);

    final buf = StringBuffer()
      ..writeln(
        '// GENERATED CODE - DO NOT MODIFY BY HAND. '
        'conduit_build_runner ConfigurationBuilder.',
      )
      ..writeln(
        '// ignore_for_file: type=lint, directives_ordering, '
        'no_leading_underscores_for_local_identifiers, '
        'unused_local_variable, unnecessary_cast, prefer_typing_uninitialized_variables',
      )
      ..writeln()
      ..writeln("import 'package:conduit_config/aot.dart';")
      ..writeln(
        "import 'package:conduit_config/src/intermediate_exception.dart';",
      )
      ..writeln("import '$inputUri';");
    for (final u in extraImports) {
      buf.writeln("import '$u';");
    }
    buf.writeln();

    for (final c in configs) {
      buf.writeln(_emitRuntime(c));
    }

    await buildStep.writeAsString(
      input.changeExtension('.config.conduit.dart'),
      buf.toString(),
    );
  }

  _ConfigAnalysis? _analyze(ClassElement klass) {
    if (!_extendsConfiguration(klass)) return null;
    final imports = <String>{};

    final properties = <_ConfigProperty>[];
    final visited = <String>{};
    InterfaceElement? ptr = klass;
    while (ptr != null) {
      if (ptr.name == _configurationTypeName &&
          ptr.library.identifier.startsWith(_configPackagePrefix)) {
        break;
      }
      for (final field in ptr.fields) {
        if (field.isStatic) continue;
        if (!field.isOriginDeclaration) continue;
        final name = field.name;
        if (name == null) continue;
        if (name.startsWith('_')) continue;
        if (!visited.add(name)) continue;
        final p = _analyzeField(field, imports);
        if (p == null) continue;
        properties.add(p);
      }
      ptr = ptr.supertype?.element;
    }

    return _ConfigAnalysis(
      className: klass.name ?? '',
      properties: properties,
      requiredImportUris: imports,
    );
  }

  bool _extendsConfiguration(ClassElement klass) {
    return klass.allSupertypes.any((t) {
      final el = t.element;
      if (el.name != _configurationTypeName) return false;
      return el.library.identifier.startsWith(_configPackagePrefix);
    });
  }

  _ConfigProperty? _analyzeField(
    FieldElement field,
    Set<String> imports,
  ) {
    final type = field.type;
    if (type is! InterfaceType) return null;

    final name = field.name;
    if (name == null) return null;

    final isRequired = _isFieldRequired(field);
    final codec = _codecFor(type, imports);

    return _ConfigProperty(
      name: name,
      isRequired: isRequired,
      typeSource: _typeSourceWithoutNullable(type),
      codec: codec,
    );
  }

  bool _isFieldRequired(FieldElement field) {
    for (final a in field.metadata.annotations) {
      final v = a.computeConstantValue();
      if (v == null) continue;
      final t = v.type;
      if (t is! InterfaceType) continue;
      final el = t.element;
      if (el.name != 'ConfigurationItemAttribute') continue;
      if (!el.library.identifier.startsWith(_configPackagePrefix)) continue;
      // The constant has a `type` enum field; we want
      // ConfigurationItemAttributeType.required.
      final typeField = v.getField('type');
      if (typeField == null) continue;
      final n = (typeField as dynamic).getField('_name')?.toStringValue();
      if (n == 'required') return true;
    }
    // Fallback: late + non-nullable → effectively required.
    if (field.isLate && field.type.nullabilitySuffix.toString().contains('none')) {
      return true;
    }
    return false;
  }

  _Codec _codecFor(InterfaceType type, Set<String> imports) {
    final el = type.element;
    final libUri = el.library.identifier;
    final name = el.name ?? '';
    final dartName = _typeSourceWithoutNullable(type);

    // Nested Configuration subclass
    final isConfigSubclass = el.allSupertypes.any((t) =>
        t.element.name == _configurationTypeName &&
        t.element.library.identifier.startsWith(_configPackagePrefix));
    if (isConfigSubclass) {
      imports.add(libUri);
      return _Codec.config(dartName);
    }

    if (name == 'int') return _Codec.simple('int', _intDecodeBody);
    if (name == 'bool') return _Codec.simple('bool', _boolDecodeBody);
    if (name == 'double') return _Codec.simple('double', _doubleDecodeBody);
    if (name == 'num') return _Codec.simple('num', _numDecodeBody);
    if (name == 'String') return _Codec.simple('String', 'return v as String;');
    if (name == 'DateTime') {
      return _Codec.simple('DateTime', _dateTimeDecodeBody);
    }
    if (name == 'List' && type.typeArguments.isNotEmpty) {
      final inner = type.typeArguments.first;
      if (inner is! InterfaceType) return _Codec.passthrough(dartName);
      final innerCodec = _codecFor(inner, imports);
      return _Codec.list(dartName, innerCodec);
    }
    if (name == 'Map' && type.typeArguments.length == 2) {
      final value = type.typeArguments[1];
      if (value is! InterfaceType) return _Codec.passthrough(dartName);
      final valueCodec = _codecFor(value, imports);
      return _Codec.map(dartName, valueCodec);
    }
    return _Codec.passthrough(dartName);
  }

  String _emitRuntime(_ConfigAnalysis c) {
    final decodeBody = StringBuffer()
      ..writeln('final valuesCopy = Map.from(input);');
    for (final p in c.properties) {
      decodeBody.writeln('{');
      decodeBody.writeln(
        "  final v = Configuration.getEnvironmentOrValue(valuesCopy.remove('${p.name}'));",
      );
      decodeBody.writeln('  if (v != null) {');
      decodeBody.writeln(
        "    final decodedValue = tryDecode(configuration, '${p.name}', () { ${p.codec.body} });",
      );
      decodeBody.writeln(
        '    if (decodedValue is! ${p.codec.expectedType}) {',
      );
      decodeBody.writeln(
        "      throw ConfigurationException(configuration, 'input is wrong type', keyPath: ['${p.name}']);",
      );
      decodeBody.writeln('    }');
      decodeBody.writeln(
        '    (configuration as ${c.className}).${p.name} = decodedValue as ${p.codec.expectedType};',
      );
      decodeBody.writeln('  }');
      decodeBody.writeln('}');
    }
    decodeBody.writeln('''
    if (valuesCopy.isNotEmpty) {
      throw ConfigurationException(configuration,
          "unexpected keys found: \${valuesCopy.keys.map((s) => "'\$s'").join(", ")}.");
    }''');

    final validateBody = StringBuffer()
      ..writeln('final missingKeys = <String>[];');
    for (final p in c.properties) {
      validateBody.writeln('try {');
      validateBody.writeln(
        '  final ${p.name} = (configuration as ${c.className}).${p.name};',
      );
      validateBody.writeln(
        '  if (${p.isRequired} && ${p.name} == null) {',
      );
      validateBody.writeln("    missingKeys.add('${p.name}');");
      validateBody.writeln('  }');
      validateBody.writeln('} on Error catch (_) {');
      validateBody.writeln("  missingKeys.add('${p.name}');");
      validateBody.writeln('}');
    }
    validateBody.writeln('''
    if (missingKeys.isNotEmpty) {
      throw ConfigurationException.missingKeys(configuration, missingKeys);
    }''');

    return '''
class \$${c.className}ConfigurationRuntime extends ConfigurationRuntime {
  \$${c.className}ConfigurationRuntime();

  @override
  void decode(Configuration configuration, Map input) {
${decodeBody.toString().trimRight()}
  }

  @override
  void validate(Configuration configuration) {
${validateBody.toString().trimRight()}
  }
}
''';
  }

  static String _typeSourceWithoutNullable(DartType t) {
    final s = t.getDisplayString();
    return s.endsWith('?') ? s.substring(0, s.length - 1) : s;
  }
}

class _ConfigAnalysis {
  _ConfigAnalysis({
    required this.className,
    required this.properties,
    required this.requiredImportUris,
  });
  final String className;
  final List<_ConfigProperty> properties;
  final Set<String> requiredImportUris;
}

class _ConfigProperty {
  _ConfigProperty({
    required this.name,
    required this.isRequired,
    required this.typeSource,
    required this.codec,
  });
  final String name;
  final bool isRequired;
  final String typeSource;
  final _Codec codec;
}

class _Codec {
  _Codec._(this.expectedType, this.body);
  factory _Codec.simple(String type, String body) => _Codec._(type, body);
  factory _Codec.passthrough(String type) =>
      _Codec._(type, 'return v as $type;');
  factory _Codec.config(String type) => _Codec._(
        type,
        '''
        final item = $type();
        item.decode(v);
        return item;
        ''',
      );
  factory _Codec.list(String dartName, _Codec inner) {
    final body = '''
final out = <${inner.expectedType}>[];
final decoder = (v) { ${inner.body} };
for (var i = 0; i < (v as List).length; i++) {
  try {
    out.add(decoder(v[i]) as ${inner.expectedType});
  } on IntermediateException catch (e) {
    e.keyPath.add(i);
    rethrow;
  } catch (e) {
    throw IntermediateException(e, [i]);
  }
}
return out;
    ''';
    return _Codec._(dartName, body);
  }
  factory _Codec.map(String dartName, _Codec inner) {
    final body = '''
final map = <String, ${inner.expectedType}>{};
final decoder = (v) { ${inner.body} };
(v as Map).forEach((key, val) {
  if (key is! String) {
    throw StateError('cannot have non-String key');
  }
  try {
    map[key] = decoder(val) as ${inner.expectedType};
  } on IntermediateException catch (e) {
    e.keyPath.add(key);
    rethrow;
  } catch (e) {
    throw IntermediateException(e, [key]);
  }
});
return map;
    ''';
    return _Codec._(dartName, body);
  }

  final String expectedType;
  final String body;
}

const String _intDecodeBody = '''
if (v is String) {
  return int.parse(v);
}
return v as int;
''';

const String _boolDecodeBody = '''
if (v is String) {
  return v == "true";
}
return v as bool;
''';

const String _doubleDecodeBody = '''
if (v is String) {
  return double.parse(v);
}
if (v is int) {
  return v.toDouble();
}
return v as double;
''';

const String _numDecodeBody = '''
if (v is String) {
  return num.parse(v);
}
return v as num;
''';

const String _dateTimeDecodeBody = '''
if (v is String) {
  return DateTime.parse(v);
}
return v as DateTime;
''';

Builder configurationBuilder(BuilderOptions options) =>
    ConfigurationBuilder();
