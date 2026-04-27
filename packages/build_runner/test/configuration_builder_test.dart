import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:conduit_build_runner/src/configuration_builder.dart';
import 'package:test/test.dart';

const _conduitConfigStub = '''
library conduit_config;

abstract class Configuration {
  Configuration();
  static dynamic getEnvironmentOrValue(dynamic v) => v;
  void decode(dynamic input) {}
}

abstract class ConfigurationRuntime {
  void decode(Configuration configuration, Map input);
  void validate(Configuration configuration);
  dynamic tryDecode(
    Configuration configuration,
    String name,
    dynamic Function() decode,
  ) => decode();
}

class ConfigurationException implements Exception {
  ConfigurationException(this.configuration, this.message,
      {this.keyPath = const []});
  ConfigurationException.missingKeys(this.configuration, this.keys)
      : message = 'missing keys',
        keyPath = const [];
  final Configuration configuration;
  final String message;
  final List<dynamic> keyPath;
  final List<String>? keys;
}

class ConfigurationItemAttribute {
  const ConfigurationItemAttribute._(this.type);
  final ConfigurationItemAttributeType type;
}

enum ConfigurationItemAttributeType { required, optional }

const ConfigurationItemAttribute requiredConfiguration =
    ConfigurationItemAttribute._(ConfigurationItemAttributeType.required);
const ConfigurationItemAttribute optionalConfiguration =
    ConfigurationItemAttribute._(ConfigurationItemAttributeType.optional);
''';

const _intermediateExceptionStub = '''
library conduit_config_intermediate_exception;

class IntermediateException implements Exception {
  IntermediateException(this.underlying, this.keyPath);
  final dynamic underlying;
  final List keyPath;
}
''';

Future<({String? dart, String? json})> _runBuilder(String source) async {
  final result = await testBuilder(
    configurationBuilder(BuilderOptions.empty),
    {
      'a|lib/configs.dart': source,
      'conduit_config|lib/conduit_config.dart': _conduitConfigStub,
      'conduit_config|lib/aot.dart': _conduitConfigStub,
      'conduit_config|lib/src/configuration.dart': _conduitConfigStub,
      'conduit_config|lib/src/intermediate_exception.dart':
          _intermediateExceptionStub,
    },
    flattenOutput: true,
  );
  final dartId = AssetId.parse('a|lib/configs.config.conduit.dart');
  final jsonId = AssetId.parse('a|lib/configs.config.conduit.json');
  return (
    dart: result.outputs.contains(dartId)
        ? result.readerWriter.testing.readString(dartId)
        : null,
    json: result.outputs.contains(jsonId)
        ? result.readerWriter.testing.readString(jsonId)
        : null,
  );
}

void main() {
  test('emits a runtime + manifest for a Configuration subclass', () async {
    final out = await _runBuilder('''
import 'package:conduit_config/conduit_config.dart';

class AppConfig extends Configuration {
  AppConfig();
  late int port;
  String? logLevel;
}
''');
    expect(out.dart, isNotNull);
    expect(out.dart, contains(r'class $AppConfigConfigurationRuntime'));
    expect(out.dart, contains('void decode('));
    expect(out.dart, contains('void validate('));
    expect(out.dart, contains("valuesCopy.remove('port')"));
    expect(out.dart, contains("valuesCopy.remove('logLevel')"));
    final manifest = json.decode(out.json!) as Map<String, dynamic>;
    expect(manifest['configurations'], equals(['AppConfig']));
  });

  test('marks late non-nullable fields as required in validate()', () async {
    final out = await _runBuilder('''
import 'package:conduit_config/conduit_config.dart';

class WithLate extends Configuration {
  WithLate();
  late int port;
  String? optional;
}
''');
    final flat = out.dart!.replaceAll(RegExp(r'\s+'), ' ');
    // port is late+non-null -> required
    expect(flat, contains("if (true && port == null)"));
    // optional is nullable -> not required
    expect(flat, contains("if (false && optional == null)"));
  });

  test('honors @requiredConfiguration annotation', () async {
    final out = await _runBuilder('''
import 'package:conduit_config/conduit_config.dart';

class WithAnnotation extends Configuration {
  WithAnnotation();
  @requiredConfiguration
  String? apiKey;
  String? other;
}
''');
    final flat = out.dart!.replaceAll(RegExp(r'\s+'), ' ');
    expect(flat, contains("if (true && apiKey == null)"));
    expect(flat, contains("if (false && other == null)"));
  });

  test('decodes nested Configuration via .decode()', () async {
    final out = await _runBuilder('''
import 'package:conduit_config/conduit_config.dart';

class Inner extends Configuration {
  Inner();
  String? name;
}

class Outer extends Configuration {
  Outer();
  late Inner inner;
}
''');
    final flat = out.dart!.replaceAll(RegExp(r'\s+'), ' ');
    expect(flat, contains('final item = Inner();'));
    expect(flat, contains('item.decode(v);'));
  });

  test('skips abstract Configuration subclasses', () async {
    final out = await _runBuilder('''
import 'package:conduit_config/conduit_config.dart';

abstract class Base extends Configuration {
  Base();
  String? x;
}
''');
    expect(out.dart, isNull);
    expect(out.json, isNull);
  });

  test('emits nothing when no Configuration subclasses are present', () async {
    final out = await _runBuilder('''
class Plain {}
''');
    expect(out.dart, isNull);
    expect(out.json, isNull);
  });
}
