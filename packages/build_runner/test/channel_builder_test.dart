import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:conduit_build_runner/src/channel_builder.dart';
import 'package:test/test.dart';

const _conduitCoreStub = '''
library conduit_core;

abstract class ApplicationChannel {}
abstract class ChannelRuntime {}
class ApplicationOptions {}
typedef IsolateEntryFunction = void Function(ApplicationInitialServerMessage);
class ApplicationInitialServerMessage {
  final Object? configuration;
  final int identifier;
  final Object? parentMessagePort;
  final bool logToConsole;
  ApplicationInitialServerMessage({
    this.configuration,
    this.identifier = 0,
    this.parentMessagePort,
    this.logToConsole = false,
  });
}
''';

const _isolateApplicationServerStub = '''
library conduit_core_isolate_application_server;

import 'package:conduit_core/conduit_core.dart';

class ApplicationIsolateServer {
  ApplicationIsolateServer(
    Type channelType,
    Object? config,
    int id,
    Object? port, {
    bool logToConsole = false,
  });
  void start({bool shareHttpServer = false}) {}
}
''';

const _conduitCommonStub = '''
library conduit_common;
class APIComponentDocumenter {}
''';

Future<({String? dart, String? json})> _runBuilder(String inputSource) async {
  final result = await testBuilder(
    channelBuilder(BuilderOptions.empty),
    {
      'a|lib/channel.dart': inputSource,
      'conduit_core|lib/conduit_core.dart': _conduitCoreStub,
      'conduit_core|lib/aot.dart': _conduitCoreStub,
      'conduit_core|lib/src/application/isolate_application_server.dart':
          _isolateApplicationServerStub,
      'conduit_common|lib/conduit_common.dart': _conduitCommonStub,
    },
    flattenOutput: true,
  );
  final dartId = AssetId.parse('a|lib/channel.channel.conduit.dart');
  final jsonId = AssetId.parse('a|lib/channel.channel.conduit.json');
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
  test('emits a runtime + manifest per ApplicationChannel subclass',
      () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

class HelloChannel extends ApplicationChannel {}
''');

    expect(out.dart, isNotNull);
    expect(out.dart, contains(r'class $HelloChannelChannelRuntime'));
    expect(out.dart, contains("String get name => 'HelloChannel'"));
    expect(out.dart, contains('Type get channelType => HelloChannel'));
    expect(out.dart, contains('instantiateChannel() => HelloChannel()'));

    expect(out.json, isNotNull);
    final manifest = json.decode(out.json!) as Map<String, dynamic>;
    expect(manifest['channels'], equals(['HelloChannel']));
  });

  test('emits initializeApplication call when present', () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

class WithInit extends ApplicationChannel {
  static Future<void> initializeApplication(ApplicationOptions options) async {}
}
''');
    expect(
      out.dart,
      contains('await WithInit.initializeApplication(config);'),
    );
  });

  test('skips abstract subclasses', () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

abstract class Base extends ApplicationChannel {}
''');
    expect(out.dart, isNull);
    expect(out.json, isNull);
  });

  test('emits nothing when no ApplicationChannel subclasses are present',
      () async {
    final out = await _runBuilder('''
class Plain {}
''');
    expect(out.dart, isNull);
    expect(out.json, isNull);
  });
}
