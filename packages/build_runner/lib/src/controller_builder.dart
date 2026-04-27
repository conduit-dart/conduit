import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';

/// Generates a `ControllerRuntime` subclass per `Controller` class in the
/// input library, plus a `ResourceControllerRuntime` for any subclass that
/// extends `ResourceController` and exposes `@Operation`-annotated methods.
///
/// Emits two siblings per source library:
///  - `<src>.controller.conduit.dart` — runtime code with one
///    `$<Class>ControllerRuntime` (and, for resource controllers, one
///    `$<Class>ResourceControllerRuntime`) per controller.
///  - `<src>.controller.conduit.json` — manifest the registry builder reads
///    to discover runtime classes. Schema:
///    `{"controllers": ["HealthController", ...]}`.
///
/// Replaces the mirror-based `ControllerRuntimeImpl` /
/// `ResourceControllerRuntimeImpl` in
/// `packages/core/lib/src/runtime/impl.dart` and
/// `resource_controller_impl.dart`.
///
/// Scope of v1:
///  - Plain `Controller` subclasses → emits a minimal runtime with
///    `isMutable` computed from instance-field finality and
///    `resourceController` null.
///  - `ResourceController` subclasses with `@Operation*`-annotated methods
///    and `@Bind.path/query/header/body` parameters.
///  - `@Bind.body()` requires a `Serializable` subclass on the parameter
///    type. Filters (accept/ignore/reject/require) and `List<Serializable>`
///    are not yet supported — fall back to the legacy `conduit build` path
///    if you need either.
///  - `@Scope` annotations are not yet honored; scopes emit as `null`.
class ControllerBuilder implements Builder {
  static const _controllerTypeName = 'Controller';
  static const _resourceControllerTypeName = 'ResourceController';
  static const _conduitCorePackagePrefix = 'package:conduit_core/';
  static const _serializableTypeName = 'Serializable';

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.controller.conduit.dart', '.controller.conduit.json'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    if (!await buildStep.resolver.isLibrary(input)) return;
    final lib = await buildStep.inputLibrary;

    final controllers = lib.classes
        .where((c) => !c.isAbstract && _extendsController(c))
        .toList();

    if (controllers.isEmpty) return;

    final manifest = {
      'controllers': controllers.map((c) => c.name).toList(),
    };
    await buildStep.writeAsString(
      input.changeExtension('.controller.conduit.json'),
      json.encode(manifest),
    );

    final inputUri = input.uri.toString();
    final buf = StringBuffer()
      ..writeln(
        '// GENERATED CODE - DO NOT MODIFY BY HAND. '
        'conduit_build_runner ControllerBuilder.',
      )
      ..writeln(
        '// ignore_for_file: type=lint, directives_ordering, '
        'no_leading_underscores_for_local_identifiers, '
        'unused_local_variable, unnecessary_cast',
      )
      ..writeln()
      ..writeln("import 'dart:async';")
      ..writeln("import 'package:conduit_core/aot.dart';")
      ..writeln("import '$inputUri';")
      ..writeln();

    for (final klass in controllers) {
      buf.writeln(_emitController(klass));
    }

    await buildStep.writeAsString(
      input.changeExtension('.controller.conduit.dart'),
      buf.toString(),
    );
  }

  bool _extendsController(ClassElement element) {
    return element.allSupertypes.any(_isController);
  }

  static bool _isController(InterfaceType t) {
    final el = t.element;
    if (el.name != _controllerTypeName) return false;
    return el.library.identifier.startsWith(_conduitCorePackagePrefix);
  }

  static bool _isResourceController(InterfaceType t) {
    final el = t.element;
    if (el.name != _resourceControllerTypeName) return false;
    return el.library.identifier.startsWith(_conduitCorePackagePrefix);
  }

  static bool _isSerializable(DartType type) {
    if (type is! InterfaceType) return false;
    if (type.element.name == _serializableTypeName &&
        type.element.library.identifier
            .startsWith(_conduitCorePackagePrefix)) {
      return true;
    }
    return type.element.allSupertypes.any(
      (t) =>
          t.element.name == _serializableTypeName &&
          t.element.library.identifier
              .startsWith(_conduitCorePackagePrefix),
    );
  }

  String _emitController(ClassElement klass) {
    final isResource =
        klass.allSupertypes.any(_isResourceController);
    final isMutable = _classIsMutable(klass);

    final buf = StringBuffer();

    if (isResource) {
      buf.writeln(_emitResourceControllerRuntime(klass));
    }

    final resourceField = isResource
        ? '\$${klass.name}ResourceControllerRuntime _rc = '
            '\$${klass.name}ResourceControllerRuntime();'
        : '';
    final resourceGetter = isResource
        ? 'ResourceControllerRuntime? get resourceController => _rc;'
        : 'ResourceControllerRuntime? get resourceController => null;';

    buf.writeln('''
class \$${klass.name}ControllerRuntime extends ControllerRuntime {
  $resourceField

  @override
  bool get isMutable => $isMutable;

  @override
  $resourceGetter
}
''');

    return buf.toString();
  }

  // A controller is "mutable" iff any non-whitelisted instance field is
  // non-final OR has a setter declared (matching the mirror impl's check).
  bool _classIsMutable(ClassElement klass) {
    const whitelist = {'policy', '_nextController'};
    for (final field in klass.fields) {
      if (field.isStatic) continue;
      if (whitelist.contains(field.name)) continue;
      if (!field.isFinal && !field.isConst) return true;
    }
    return false;
  }

  String _emitResourceControllerRuntime(ClassElement klass) {
    final ivars = _ivarBindings(klass).toList();
    final operations = _operationMethods(klass).toList();

    final ivarSrc = ivars
        .map((b) => _emitParameterLiteral(b))
        .join(',\n      ');
    final opsSrc = operations.map((op) => _emitOperationLiteral(klass, op)).join(',\n      ');

    final applySrc = StringBuffer();
    for (final b in ivars) {
      applySrc.writeln(
        "    (untypedController as ${klass.name}).${b.symbolName} = "
        "args.instanceVariables['${b.symbolName}'] as ${_typeSource(b.type)}?;",
      );
    }

    return '''
class \$${klass.name}ResourceControllerRuntime extends ResourceControllerRuntime {
  \$${klass.name}ResourceControllerRuntime() {
    ivarParameters = [
      $ivarSrc
    ];
    operations = [
      $opsSrc
    ];
  }

  @override
  void applyRequestProperties(
    ResourceController untypedController,
    ResourceControllerOperationInvocationArgs args,
  ) {
${applySrc.toString().trimRight()}
  }
}
''';
  }

  Iterable<_Binding> _ivarBindings(ClassElement klass) sync* {
    for (final field in klass.fields) {
      if (field.isStatic) continue;
      final fieldName = field.name;
      if (fieldName == null) continue;
      final annotations = field.metadata.annotations;
      final bind = _bindAnnotation(annotations);
      if (bind == null) continue;
      final required = annotations.any((a) {
        final v = a.computeConstantValue();
        final t = v?.type;
        return t is InterfaceType && t.element.name == 'RequiredBinding';
      });
      yield _Binding(
        symbolName: fieldName,
        bind: bind,
        type: field.type,
        isRequired: required,
        defaultValueSource: 'null',
      );
    }
  }

  Iterable<_OperationMethod> _operationMethods(ClassElement klass) sync* {
    for (final method in klass.methods) {
      final methodName = method.name;
      if (methodName == null) continue;
      final op = _operationAnnotation(method.metadata.annotations);
      if (op == null) continue;
      final positional = <_Binding>[];
      final named = <_Binding>[];
      for (final p in method.formalParameters) {
        final paramName = p.name;
        if (paramName == null) continue;
        final bind = _bindAnnotation(p.metadata.annotations);
        if (bind == null) {
          throw StateError(
            "Parameter '$paramName' on '${klass.name}.$methodName' has "
            "no @Bind annotation. AOT controller generation requires every "
            "operation parameter to be bound.",
          );
        }
        final binding = _Binding(
          symbolName: paramName,
          bind: bind,
          type: p.type,
          isRequired: !p.isOptional,
          defaultValueSource: p.defaultValueCode ?? 'null',
        );
        if (p.isOptional) {
          named.add(binding);
        } else {
          positional.add(binding);
        }
      }
      yield _OperationMethod(
        dartMethodName: methodName,
        operation: op,
        positional: positional,
        named: named,
      );
    }
  }

  _BindMeta? _bindAnnotation(List<ElementAnnotation> metadata) {
    for (final a in metadata) {
      final value = a.computeConstantValue();
      if (value == null) continue;
      final t = value.type;
      if (t is! InterfaceType) continue;
      if (t.element.name != 'Bind') continue;
      if (!t.element.library.identifier
          .startsWith(_conduitCorePackagePrefix)) continue;

      final bindingType = value.getField('bindingType')?.getField('_name')?.toStringValue() ??
          // Older analyzer revs expose enum index instead of _name.
          _bindingTypeFromIndex(value.getField('bindingType')?.getField('index')?.toIntValue());
      final name = value.getField('name')?.toStringValue();
      return _BindMeta(bindingType: bindingType ?? 'query', name: name);
    }
    return null;
  }

  String? _bindingTypeFromIndex(int? index) {
    if (index == null) return null;
    const order = ['query', 'header', 'body', 'path'];
    if (index < 0 || index >= order.length) return null;
    return order[index];
  }

  _OperationMeta? _operationAnnotation(List<ElementAnnotation> metadata) {
    for (final a in metadata) {
      final value = a.computeConstantValue();
      if (value == null) continue;
      final t = value.type;
      if (t is! InterfaceType) continue;
      if (t.element.name != 'Operation') continue;
      if (!t.element.library.identifier
          .startsWith(_conduitCorePackagePrefix)) continue;

      final method = value.getField('method')?.toStringValue() ?? 'GET';
      final pathVars = <String>[];
      for (final f in const [
        '_pathVariable1',
        '_pathVariable2',
        '_pathVariable3',
        '_pathVariable4',
      ]) {
        final pv = value.getField(f)?.toStringValue();
        if (pv != null) pathVars.add(pv);
      }
      return _OperationMeta(httpMethod: method.toUpperCase(), pathVariables: pathVars);
    }
    return null;
  }

  String _emitParameterLiteral(_Binding b) {
    final loc = 'BindingType.${b.bind.bindingType}';
    final name = b.bind.name == null ? 'null' : "'${b.bind.name}'";
    final decoder = _emitDecoder(b);
    return '''ResourceControllerParameter.make<${_typeSource(b.type)}>(
        symbolName: '${b.symbolName}',
        name: $name,
        location: $loc,
        isRequired: ${b.isRequired},
        defaultValue: ${b.defaultValueSource},
        acceptFilter: null,
        ignoreFilter: null,
        rejectFilter: null,
        requireFilter: null,
        decoder: $decoder)''';
  }

  String _emitOperationLiteral(ClassElement klass, _OperationMethod op) {
    final pathVars =
        op.operation.pathVariables.map((v) => "'$v'").join(', ');
    final positionals = op.positional
        .map(_emitParameterLiteral)
        .join(',\n          ');
    final named = op.named.map(_emitParameterLiteral).join(',\n          ');
    final invokerBody = StringBuffer()
      ..writeln("(rc, args) {")
      ..writeln("  return (rc as ${klass.name}).${op.dartMethodName}(");
    for (var i = 0; i < op.positional.length; i++) {
      final p = op.positional[i];
      invokerBody.writeln(
        "    args.positionalArguments[$i] as ${_typeSource(p.type)},",
      );
    }
    for (final n in op.named) {
      invokerBody.writeln(
        "    ${n.symbolName}: args.namedArguments['${n.symbolName}'] as ${_typeSource(n.type)}? ?? ${n.defaultValueSource},",
      );
    }
    invokerBody.writeln("  );");
    invokerBody.writeln("}");

    return '''ResourceControllerOperation(
        positionalParameters: [
          $positionals
        ],
        namedParameters: [
          $named
        ],
        scopes: null,
        dartMethodName: '${op.dartMethodName}',
        httpMethod: '${op.operation.httpMethod}',
        pathVariables: [$pathVars],
        invoker: ${invokerBody.toString().trimRight()})''';
  }

  String _emitDecoder(_Binding b) {
    final typeSrc = _typeSource(b.type);
    switch (b.bind.bindingType) {
      case 'path':
        return _emitElementDecoder(b.type);
      case 'header':
      case 'query':
        return _emitListDecoder(b);
      case 'body':
        if (_isSerializable(b.type)) {
          return '''(v) {
            return $typeSrc()..read((v as RequestBody).as());
          }''';
        }
        return '(v) { return (v as RequestBody).as<$typeSrc>(); }';
      default:
        return '(v) { return v; }';
    }
  }

  String _emitElementDecoder(DartType t) {
    final typeSrc = _typeSource(t);
    final raw = t.getDisplayString();
    if (raw == 'bool' || raw == 'bool?') return '(v) { return true; }';
    if (raw == 'String' || raw == 'String?') {
      return '(v) { return v as String; }';
    }
    return '''(v) {
      try {
        return $typeSrc.parse(v as String);
      } catch (_) {
        throw ArgumentError("invalid value");
      }
    }''';
  }

  String _emitListDecoder(_Binding b) {
    final raw = _typeSource(b.type);
    if (raw.startsWith('List<')) {
      final inner = raw.substring(5, raw.length - 1);
      final mapper = _emitElementDecoderForName(inner);
      return '(v) { return $raw.from((v as List).map($mapper)); }';
    }
    final element = _emitElementDecoder(b.type);
    return '''(v) {
      final listOfValues = v as List;
      if (listOfValues.length > 1) {
        throw ArgumentError("multiple values not expected");
      }
      return $element(listOfValues.first);
    }''';
  }

  String _emitElementDecoderForName(String typeName) {
    if (typeName == 'bool' || typeName == 'bool?') {
      return '(v) { return true; }';
    }
    if (typeName == 'String' || typeName == 'String?') {
      return '(v) { return v as String; }';
    }
    return '''(v) {
      try {
        return $typeName.parse(v as String);
      } catch (_) {
        throw ArgumentError("invalid value");
      }
    }''';
  }

  String _typeSource(DartType t) {
    final s = t.getDisplayString();
    return s.endsWith('?') ? s.substring(0, s.length - 1) : s;
  }
}

class _BindMeta {
  _BindMeta({required this.bindingType, required this.name});
  final String bindingType;
  final String? name;
}

class _OperationMeta {
  _OperationMeta({required this.httpMethod, required this.pathVariables});
  final String httpMethod;
  final List<String> pathVariables;
}

class _Binding {
  _Binding({
    required this.symbolName,
    required this.bind,
    required this.type,
    required this.isRequired,
    required this.defaultValueSource,
  });
  final String symbolName;
  final _BindMeta bind;
  final DartType type;
  final bool isRequired;
  final String defaultValueSource;
}

class _OperationMethod {
  _OperationMethod({
    required this.dartMethodName,
    required this.operation,
    required this.positional,
    required this.named,
  });
  final String dartMethodName;
  final _OperationMeta operation;
  final List<_Binding> positional;
  final List<_Binding> named;
}

Builder controllerBuilder(BuilderOptions options) => ControllerBuilder();
