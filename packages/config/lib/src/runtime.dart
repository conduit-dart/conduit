import 'dart:mirrors';

import 'package:conduit_config/src/configuration.dart';
import 'package:conduit_config/src/mirror_property.dart';

class ConfigurationRuntimeImpl extends ConfigurationRuntime {
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

}
