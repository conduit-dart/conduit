import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:conduit_build_runner/src/registry_builder.dart';
import 'package:test/test.dart';

Future<String?> _runBuilder(Map<String, String> assets) async {
  final result = await testBuilder(
    RegistryBuilder(),
    assets,
    flattenOutput: true,
  );
  final outputId = AssetId.parse('a|lib/conduit.g.dart');
  if (!result.outputs.contains(outputId)) return null;
  return result.readerWriter.testing.readString(outputId);
}

void main() {
  test('emits bootstrap() that registers channel/serializable/controller',
      () async {
    final out = await _runBuilder({
      'a|lib/channel.channel.conduit.json': '{"channels":["HelloChannel"]}',
      'a|lib/channel.channel.conduit.dart':
          '// stub channel runtime\n',
      'a|lib/model.serializable.conduit.json':
          '{"serializables":["UserPayload"]}',
      'a|lib/model.serializable.conduit.dart':
          '// stub serializable runtime\n',
      'a|lib/health.controller.conduit.json':
          '{"controllers":["HealthController"]}',
      'a|lib/health.controller.conduit.dart':
          '// stub controller runtime\n',
    });

    expect(out, isNotNull);
    expect(
      out,
      contains("import 'package:a/channel.channel.conduit.dart'"),
    );
    expect(
      out,
      contains("import 'package:a/model.serializable.conduit.dart'"),
    );
    expect(
      out,
      contains("import 'package:a/health.controller.conduit.dart'"),
    );

    expect(out, contains(r"map['HelloChannel'] = "));
    expect(out, contains(r"map['UserPayload'] = "));
    expect(out, contains(r"map['HealthController'] = "));
    expect(out, contains(r'$HelloChannelChannelRuntime()'));
    expect(out, contains(r'$UserPayloadSerializableRuntime()'));
    expect(out, contains(r'$HealthControllerControllerRuntime()'));

    expect(out, contains('void bootstrap()'));
    expect(
      out,
      contains(r'RuntimeContext.install(_$ConduitGeneratedContext());'),
    );
  });

  test('still emits a registry when no manifests exist', () async {
    final out = await _runBuilder(const {
      'a|lib/_placeholder.dart': '// just to anchor the package\n',
    });
    expect(out, isNotNull);
    expect(out, contains('void bootstrap()'));
    expect(out, contains('RuntimeCollection(map)'));
  });

  test('handles multiple classes in a single manifest', () async {
    final out = await _runBuilder({
      'a|lib/models.serializable.conduit.json':
          '{"serializables":["A","B","C"]}',
      'a|lib/models.serializable.conduit.dart': '// stub\n',
    });
    expect(out, isNotNull);
    expect(out, contains(r'$ASerializableRuntime()'));
    expect(out, contains(r'$BSerializableRuntime()'));
    expect(out, contains(r'$CSerializableRuntime()'));
  });
}
