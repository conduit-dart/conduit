import 'dart:io';

import 'package:conduit_config/src/intermediate_exception.dart';
import 'package:conduit_runtime/runtime.dart';
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

/// Subclasses of [Configuration] read YAML strings and files, assigning values from the YAML document to properties
/// of an instance of this type.
abstract class Configuration {
  /// Default constructor.
  Configuration();

  Configuration.fromMap(Map<dynamic, dynamic> map) {
    decode(map.map<String, dynamic>((k, v) => MapEntry(k.toString(), v)));
  }

  /// [contents] must be YAML.
  Configuration.fromString(String contents) {
    final yamlMap = loadYaml(contents) as Map<dynamic, dynamic>?;
    final map =
        yamlMap?.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
    decode(map);
  }

  /// Opens a file and reads its string contents into this instance's properties.
  ///
  /// [file] must contain valid YAML data.
  Configuration.fromFile(File file) : this.fromString(file.readAsStringSync());

  ConfigurationRuntime get _runtime =>
      RuntimeContext.current[runtimeType] as ConfigurationRuntime;

  /// Ingests [value] into the properties of this type.
  ///
  /// Override this method to provide decoding behavior other than the default behavior.
  void decode(dynamic value) {
    if (value is! Map) {
      throw ConfigurationException(
        this,
        "input is not an object (is a '${value.runtimeType}')",
      );
    }

    _runtime.decode(this, value);

    validate();
  }

  /// Validates this configuration.
  ///
  /// By default, ensures all required keys are non-null.
  ///
  /// Override this method to perform validations on input data. Throw [ConfigurationException]
  /// for invalid data.
  @mustCallSuper
  void validate() {
    _runtime.validate(this);
  }

  static dynamic getEnvironmentOrValue(dynamic value) {
    if (value is String && value.startsWith(r"$")) {
      final envKey = value.substring(1);
      if (!Platform.environment.containsKey(envKey)) {
        return null;
      }

      return Platform.environment[envKey];
    }
    return value;
  }
}

abstract class ConfigurationRuntime {
  void decode(Configuration configuration, Map input);
  void validate(Configuration configuration);

  dynamic tryDecode(
    Configuration configuration,
    String name,
    dynamic Function() decode,
  ) {
    try {
      return decode();
    } on ConfigurationException catch (e) {
      throw ConfigurationException(
        configuration,
        e.message,
        keyPath: [name, ...e.keyPath],
      );
    } on IntermediateException catch (e) {
      final underlying = e.underlying;
      if (underlying is ConfigurationException) {
        final keyPaths = [
          [name],
          e.keyPath,
          underlying.keyPath,
        ].expand((i) => i).toList();

        throw ConfigurationException(
          configuration,
          underlying.message,
          keyPath: keyPaths,
        );
      } else if (underlying is TypeError) {
        throw ConfigurationException(
          configuration,
          "input is wrong type",
          keyPath: [name, ...e.keyPath],
        );
      }

      throw ConfigurationException(
        configuration,
        underlying.toString(),
        keyPath: [name, ...e.keyPath],
      );
    } catch (e) {
      throw ConfigurationException(
        configuration,
        e.toString(),
        keyPath: [name],
      );
    }
  }
}

/// Possible options for a configuration item property's optionality.
enum ConfigurationItemAttributeType {
  /// [Configuration] properties marked as [required] will throw an exception
  /// if their source YAML doesn't contain a matching key.
  required,

  /// [Configuration] properties marked as [optional] will be silently ignored
  /// if their source YAML doesn't contain a matching key.
  optional
}

/// [Configuration] properties may be attributed with these.
///
/// **NOTICE**: This will be removed in version 2.0.0.
/// To signify required or optional config you could do:
/// Example:
/// ```dart
/// class MyConfig extends Config {
///    late String required;
///    String? optional;
///    String optionalWithDefult = 'default';
///    late String optionalWithComputedDefault = _default();
///
///    String _default() => 'computed';
/// }
/// ```
class ConfigurationItemAttribute {
  const ConfigurationItemAttribute._(this.type);

  final ConfigurationItemAttributeType type;
}

/// A [ConfigurationItemAttribute] for required properties.
///
/// **NOTICE**: This will be removed in version 2.0.0.
/// To signify required or optional config you could do:
/// Example:
/// ```dart
/// class MyConfig extends Config {
///    late String required;
///    String? optional;
///    String optionalWithDefult = 'default';
///    late String optionalWithComputedDefault = _default();
///
///    String _default() => 'computed';
/// }
/// ```
@Deprecated("Use `late` property")
const ConfigurationItemAttribute requiredConfiguration =
    ConfigurationItemAttribute._(ConfigurationItemAttributeType.required);

/// A [ConfigurationItemAttribute] for optional properties.
///
/// **NOTICE**: This will be removed in version 2.0.0.
/// To signify required or optional config you could do:
/// Example:
/// ```dart
/// class MyConfig extends Config {
///    late String required;
///    String? optional;
///    String optionalWithDefult = 'default';
///    late String optionalWithComputedDefault = _default();
///
///    String _default() => 'computed';
/// }
/// ```
@Deprecated("Use `nullable` property")
const ConfigurationItemAttribute optionalConfiguration =
    ConfigurationItemAttribute._(ConfigurationItemAttributeType.optional);

/// Thrown when reading data into a [Configuration] fails.
class ConfigurationException {
  ConfigurationException(
    this.configuration,
    this.message, {
    this.keyPath = const [],
  });

  ConfigurationException.missingKeys(
    this.configuration,
    List<String> missingKeys, {
    this.keyPath = const [],
  }) : message =
            "missing required key(s): ${missingKeys.map((s) => "'$s'").join(", ")}";

  /// The [Configuration] in which this exception occurred.
  final Configuration configuration;

  /// The reason for the exception.
  final String message;

  /// The key of the object being evaluated.
  ///
  /// Either a string (adds '.name') or an int (adds '\[value\]').
  final List<dynamic> keyPath;

  @override
  String toString() {
    if (keyPath.isEmpty) {
      return "Failed to read '${configuration.runtimeType}'\n\t-> $message";
    }

    final joinedKeyPath = StringBuffer();
    for (var i = 0; i < keyPath.length; i++) {
      final thisKey = keyPath[i];

      if (thisKey is String) {
        if (i != 0) {
          joinedKeyPath.write(".");
        }
        joinedKeyPath.write(thisKey);
      } else if (thisKey is int) {
        joinedKeyPath.write("[$thisKey]");
      } else {
        throw StateError("not an int or String");
      }
    }

    return "Failed to read key '$joinedKeyPath' for '${configuration.runtimeType}'\n\t-> $message";
  }
}

/// Thrown when [Configuration] subclass is invalid and requires a change in code.
class ConfigurationError {
  ConfigurationError(this.type, this.message);

  /// The type of [Configuration] in which this error appears in.
  final Type type;

  /// The reason for the error.
  String message;

  @override
  String toString() {
    return "Invalid configuration type '$type'. $message";
  }
}
