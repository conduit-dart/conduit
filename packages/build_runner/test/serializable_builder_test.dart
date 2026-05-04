import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:conduit_build_runner/src/serializable_builder.dart';
import 'package:test/test.dart';

const _conduitCoreStub = '''
library conduit_core;

abstract class Serializable {
  void readFromMap(Map<String, dynamic> object);
  Map<String, dynamic> asMap();
}

abstract class SerializableRuntime {
  Object documentSchema(Object context);
}
''';

const _conduitOpenApiStub = '''
library conduit_open_api;
class APISchemaObject {
  static APISchemaObject integer() => APISchemaObject();
  static APISchemaObject number() => APISchemaObject();
  static APISchemaObject string({String? format}) => APISchemaObject();
  static APISchemaObject boolean() => APISchemaObject();
  static APISchemaObject object(Map<String, APISchemaObject> p) =>
      APISchemaObject();
  static APISchemaObject array({APISchemaObject? ofSchema}) =>
      APISchemaObject();
  String? title;
  Object? type;
  APISchemaObject? additionalPropertySchema;
}
class APIType { static const Object object = 'object'; }
class APIDocumentContext {}
''';

Future<String?> _runBuilder(String inputSource) async {
  final result = await testBuilder(
    serializableBuilder(BuilderOptions.empty),
    {
      'a|lib/model.dart': inputSource,
      'conduit_core|lib/conduit_core.dart': _conduitCoreStub,
      'conduit_core|lib/aot.dart': _conduitCoreStub,
      'conduit_open_api|lib/v3.dart': _conduitOpenApiStub,
    },
    flattenOutput: true,
  );
  final outputId =
      AssetId.parse('a|lib/model.serializable.conduit.dart');
  if (!result.outputs.contains(outputId)) return null;
  return result.readerWriter.testing.readString(outputId);
}

void main() {
  test('emits a generated runtime per concrete Serializable subclass',
      () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

class User implements Serializable {
  int id = 0;
  String name = '';
  bool active = false;
  DateTime? createdAt;

  @override
  void readFromMap(Map<String, dynamic> object) {}

  @override
  Map<String, dynamic> asMap() => const {};
}
''');

    expect(out, isNotNull);
    expect(out, contains(r'class $UserSerializableRuntime'));
    expect(out, contains("'id': APISchemaObject.integer()"));
    expect(out, contains("'name': APISchemaObject.string()"));
    expect(out, contains("'active': APISchemaObject.boolean()"));
    expect(
      out,
      contains("'createdAt': APISchemaObject.string(format: 'date-time')"),
    );
    expect(out, contains("..title = 'User'"));
  });

  test('skips abstract classes', () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

abstract class Base implements Serializable {
  int id = 0;
  @override
  void readFromMap(Map<String, dynamic> object) {}
  @override
  Map<String, dynamic> asMap() => const {};
}
''');
    expect(out, isNull);
  });

  test('emits no output when no Serializable subclasses are present',
      () async {
    final out = await _runBuilder('''
class Plain {
  int id = 0;
}
''');
    expect(out, isNull);
  });

  test('handles List<int> and Map<String, String>', () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

class Bag implements Serializable {
  List<int> ids = const [];
  Map<String, String> tags = const {};
  @override
  void readFromMap(Map<String, dynamic> object) {}
  @override
  Map<String, dynamic> asMap() => const {};
}
''');
    expect(out, isNotNull);
    expect(out, contains("APISchemaObject.array("));
    expect(out, contains("ofSchema: APISchemaObject.integer()"));
    expect(out, contains("..type = APIType.object"));
    expect(out, contains("additionalPropertySchema = APISchemaObject.string()"));
  });
}
