import 'dart:mirrors';

import 'package:conduit_config/src/configuration.dart';
import 'package:conduit_config/src/mirror_property.dart';
import 'package:conduit_runtime/runtime.dart';

class ConfigurationRuntimeImpl extends ConfigurationRuntime
    implements SourceCompiler {
  ConfigurationRuntimeImpl(this.type) {
    // Should be done in the constructor so a type check could be run.
    properties = _collectProperties();
  }

  final ClassMirror type;

  late final Map<String, MirrorConfigurationProperty> properties;

  @override
  void decode(Configuration configuration, Map input) {
    final values = Map.from(input);
    properties.forEach((name, property) {
      final takingValue = values.remove(name);
      if (takingValue == null) {
        return;
      }

      final decodedValue = tryDecode(
        configuration,
        name,
        () => property.decode(takingValue),
      );
      if (decodedValue == null) {
        return;
      }

      if (!reflect(decodedValue).type.isAssignableTo(property.property.type)) {
        throw ConfigurationException(
          configuration,
          "input is wrong type",
          keyPath: [name],
        );
      }

      final mirror = reflect(configuration);
      mirror.setField(property.property.simpleName, decodedValue);
    });

    if (values.isNotEmpty) {
      throw ConfigurationException(
        configuration,
        "unexpected keys found: ${values.keys.map((s) => "'$s'").join(", ")}.",
      );
    }
  }

  String get decodeImpl {
    final buf = StringBuffer();

    buf.writeln("final valuesCopy = Map.from(input);");
    properties.forEach((k, v) {
      buf.writeln("{");
      buf.writeln(
        "final v = Configuration.getEnvironmentOrValue(valuesCopy.remove('$k'));",
      );
      buf.writeln("if (v != null) {");
      buf.writeln(
        "  final decodedValue = tryDecode(configuration, '$k', () { ${v.source} });",
      );
      buf.writeln("  if (decodedValue is! ${v.codec.expectedType}) {");
      buf.writeln(
        "    throw ConfigurationException(configuration, 'input is wrong type', keyPath: ['$k']);",
      );
      buf.writeln("  }");
      buf.writeln(
        "  (configuration as ${type.reflectedType}).$k = decodedValue as ${v.codec.expectedType};",
      );
      buf.writeln("}");
      buf.writeln("}");
    });

    buf.writeln(
      """
    if (valuesCopy.isNotEmpty) {
      throw ConfigurationException(configuration,
          "unexpected keys found: \${valuesCopy.keys.map((s) => "'\$s'").join(", ")}.");
    }
    """,
    );

    return buf.toString();
  }

  @override
  void validate(Configuration configuration) {
    final configMirror = reflect(configuration);
    final requiredValuesThatAreMissing = properties.values
        .where((v) {
          try {
            final value = configMirror.getField(Symbol(v.key)).reflectee;
            return v.isRequired && value == null;
          } catch (e) {
            return true;
          }
        })
        .map((v) => v.key)
        .toList();

    if (requiredValuesThatAreMissing.isNotEmpty) {
      throw ConfigurationException.missingKeys(
        configuration,
        requiredValuesThatAreMissing,
      );
    }
  }

  Map<String, MirrorConfigurationProperty> _collectProperties() {
    final declarations = <VariableMirror>[];

    var ptr = type;
    while (ptr.isSubclassOf(reflectClass(Configuration))) {
      declarations.addAll(
        ptr.declarations.values
            .whereType<VariableMirror>()
            .where((vm) => !vm.isStatic && !vm.isPrivate),
      );
      ptr = ptr.superclass!;
    }

    final m = <String, MirrorConfigurationProperty>{};
    for (final vm in declarations) {
      final name = MirrorSystem.getName(vm.simpleName);
      m[name] = MirrorConfigurationProperty(vm);
    }
    return m;
  }

  String get validateImpl {
    final buf = StringBuffer();

    const startValidation = """
    final missingKeys = <String>[];
""";
    buf.writeln(startValidation);
    properties.forEach((name, property) {
      final propCheck = """
    try {
      final $name = (configuration as ${type.reflectedType}).$name;
      if (${property.isRequired} && $name == null) {
        missingKeys.add('$name');
      }
    } on Error catch (e) {
      missingKeys.add('$name');
    }""";
      buf.writeln(propCheck);
    });
    const throwIfErrors = """
    if (missingKeys.isNotEmpty) {
      throw ConfigurationException.missingKeys(configuration, missingKeys);
    }""";
    buf.writeln(throwIfErrors);

    return buf.toString();
  }

  @override
  Future<String> compile(BuildContext ctx) async {
    final directives = await ctx.getImportDirectives(
      uri: type.originalDeclaration.location!.sourceUri,
      alsoImportOriginalFile: true,
    )
      ..add("import 'package:conduit_config/src/intermediate_exception.dart';");
    return """
    ${directives.join("\n")}
    final instance = ConfigurationRuntimeImpl();
    class ConfigurationRuntimeImpl extends ConfigurationRuntime {
      @override
      void decode(Configuration configuration, Map input) {
        $decodeImpl
      }

      @override
      void validate(Configuration configuration) {
        $validateImpl
      }
    }
    """;
  }
}
