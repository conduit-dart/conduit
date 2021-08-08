import 'package:conduit_config/src/configuration.dart';
import 'package:conduit_config/src/intermediate_exception.dart';
import 'package:conduit_runtime/runtime.dart';
import 'package:reflectable/reflectable.dart';

class MirrorTypeCodec {
  MirrorTypeCodec(this.type) {
    if (type.isSubtypeOf(runtimeReflector.reflectType(Configuration))) {
      final klass = type as ClassMirror;
      final classHasDefaultConstructor = klass.declarations.values.any((dm) {
        return dm is MethodMirror &&
            dm.isConstructor &&
            dm.constructorName == '' &&
            dm.parameters.every((p) => p.isOptional == true);
      });

      if (!classHasDefaultConstructor) {
        throw StateError(
          "Failed to compile '${type.reflectedType}'\n\t-> "
          "'Configuration' subclasses MUST declare an unnammed constructor "
          "(i.e. '${type.reflectedType}();') if they are nested.",
        );
      }
    }
  }

  final TypeMirror type;

  dynamic _decodeValue(dynamic value) {
    if (type.isSubtypeOf(runtimeReflector.reflectType(int))) {
      return _decodeInt(value);
    } else if (type.isSubtypeOf(runtimeReflector.reflectType(bool))) {
      return _decodeBool(value);
    } else if (type.isSubtypeOf(runtimeReflector.reflectType(Configuration))) {
      return _decodeConfig(value);
    } else if (type.isSubtypeOf(runtimeReflector.reflectType(List))) {
      return _decodeList(value as List);
    } else if (type.isSubtypeOf(runtimeReflector.reflectType(Map))) {
      return _decodeMap(value as Map);
    }

    return value;
  }

  dynamic _decodeBool(dynamic value) {
    if (value is String) {
      return value == "true";
    }

    return value as bool;
  }

  dynamic _decodeInt(dynamic value) {
    if (value is String) {
      return int.parse(value);
    }

    return value as int;
  }

  Configuration _decodeConfig(dynamic object) {
    final item = (type as ClassMirror).newInstance("", []) as Configuration;

    item.decode(object);

    return item;
  }

  List<dynamic> _decodeList(List value) {
    final out = (type as ClassMirror).newInstance('', []) as List;
    final innerDecoder = MirrorTypeCodec(type.typeArguments.first);
    for (var i = 0; i < value.length; i++) {
      try {
        final v = innerDecoder._decodeValue(value[i]);
        out.add(v);
      } on IntermediateException catch (e) {
        e.keyPath.add(i);
        rethrow;
      } catch (e) {
        throw IntermediateException(e, [i]);
      }
    }
    return out;
  }

  Map<dynamic, dynamic> _decodeMap(Map value) {
    final map = (type as ClassMirror).newInstance("", []) as Map;

    final innerDecoder = MirrorTypeCodec(type.typeArguments.last);
    value.forEach((key, val) {
      if (key is! String) {
        throw StateError('cannot have non-String key');
      }

      try {
        map[key] = innerDecoder._decodeValue(val);
      } on IntermediateException catch (e) {
        e.keyPath.add(key);
        rethrow;
      } catch (e) {
        throw IntermediateException(e, [key]);
      }
    });

    return map;
  }

  String get expectedType {
    return type.reflectedType.toString();
  }

  String get source {
    if (type.isSubtypeOf(runtimeReflector.reflectType(int))) {
      return _decodeIntSource;
    } else if (type.isSubtypeOf(runtimeReflector.reflectType(bool))) {
      return _decodeBoolSource;
    } else if (type.isSubtypeOf(runtimeReflector.reflectType(Configuration))) {
      return _decodeConfigSource;
    } else if (type.isSubtypeOf(runtimeReflector.reflectType(List))) {
      return _decodeListSource;
    } else if (type.isSubtypeOf(runtimeReflector.reflectType(Map))) {
      return _decodeMapSource;
    }

    return "return v;";
  }

  String get _decodeListSource {
    final typeParam = MirrorTypeCodec(type.typeArguments.first);
    return """
final out = <${typeParam.expectedType}>[];
final decoder = (v) {
  ${typeParam.source}
};
for (var i = 0; i < (v as List).length; i++) {
  try {
    final innerValue = decoder(v[i]);
    out.add(innerValue);
  } on IntermediateException catch (e) {
    e.keyPath.add(i);
    rethrow;
  } catch (e) {
    throw IntermediateException(e, [i]);
  }
}
return out;
    """;
  }

  String get _decodeMapSource {
    final typeParam = MirrorTypeCodec(type.typeArguments.last);
    return """
final map = <String, ${typeParam.expectedType}>{};
final decoder = (v) {
  ${typeParam.source}
};
v.forEach((key, val) {
  if (key is! String) {
    throw StateError('cannot have non-String key');
  }

  try {
    map[key] = decoder(val);
  } on IntermediateException catch (e) {
    e.keyPath.add(key);
    rethrow;
  } catch (e) {
    throw IntermediateException(e, [key]);
  }
});

return map;
    """;
  }

  String get _decodeConfigSource {
    return """
    final item = $expectedType();

    item.decode(v);

    return item;
    """;
  }

  String get _decodeIntSource {
    return """
    if (v is String) {
      return int.parse(v);
    }

    return v as int;
""";
  }

  String get _decodeBoolSource {
    return """
    if (v is String) {
      return v == "true";
    }

    return v as bool;
    """;
  }
}

class MirrorConfigurationProperty {
  MirrorConfigurationProperty(this.property)
      : codec = MirrorTypeCodec(property.type);

  final VariableMirror property;
  final MirrorTypeCodec codec;

  String get key => property.simpleName;
  bool get isRequired => _isVariableRequired(property);

  String get source => codec.source;

  static bool _isVariableRequired(VariableMirror m) {
    try {
      final attribute = m.metadata.firstWhere((im) => runtimeReflector
              .reflect(im)
              .type
              .isSubtypeOf(
                  runtimeReflector.reflectType(ConfigurationItemAttribute)))
          as ConfigurationItemAttribute;

      return attribute.type == ConfigurationItemAttributeType.required;
    } catch (_) {
      return false;
    }
  }

  dynamic decode(dynamic input) {
    return codec._decodeValue(Configuration.getEnvironmentOrValue(input));
  }
}
