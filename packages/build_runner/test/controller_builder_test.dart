import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:conduit_build_runner/src/controller_builder.dart';
import 'package:test/test.dart';

const _conduitCoreStub = '''
library conduit_core;

abstract class ControllerRuntime {
  bool get isMutable;
  ResourceControllerRuntime? get resourceController;
}

abstract class ResourceControllerRuntime {
  List<ResourceControllerParameter>? ivarParameters;
  late List<ResourceControllerOperation> operations;
  ResourceControllerDocumenter? documenter;
  void applyRequestProperties(
    ResourceController untypedController,
    ResourceControllerOperationInvocationArgs args,
  );
}

abstract class ResourceControllerDocumenter {}

class ResourceControllerOperation {
  ResourceControllerOperation({
    required this.scopes,
    required this.pathVariables,
    required this.httpMethod,
    required this.dartMethodName,
    required this.positionalParameters,
    required this.namedParameters,
    required this.invoker,
  });
  final List<Object?>? scopes;
  final List<String> pathVariables;
  final String httpMethod;
  final String dartMethodName;
  final List<ResourceControllerParameter> positionalParameters;
  final List<ResourceControllerParameter> namedParameters;
  final Future<dynamic> Function(
    ResourceController, ResourceControllerOperationInvocationArgs)
      invoker;
}

class ResourceControllerParameter {
  ResourceControllerParameter._();
  static ResourceControllerParameter make<T>({
    required String symbolName,
    required String? name,
    required BindingType location,
    required bool isRequired,
    required dynamic Function(dynamic) decoder,
    required dynamic defaultValue,
    required List<String>? acceptFilter,
    required List<String>? ignoreFilter,
    required List<String>? requireFilter,
    required List<String>? rejectFilter,
  }) =>
      ResourceControllerParameter._();
}

class ResourceControllerOperationInvocationArgs {
  late Map<String, dynamic> instanceVariables;
  late Map<String, dynamic> namedArguments;
  late List<dynamic> positionalArguments;
}

enum BindingType { query, header, body, path }

class Bind {
  const Bind.query(String this.name)
      : bindingType = BindingType.query;
  const Bind.header(String this.name)
      : bindingType = BindingType.header;
  const Bind.path(String this.name)
      : bindingType = BindingType.path;
  const Bind.body() : name = null, bindingType = BindingType.body;
  final String? name;
  final BindingType bindingType;
}

class Operation {
  const Operation(
    this.method, [
    this._pathVariable1,
    this._pathVariable2,
    this._pathVariable3,
    this._pathVariable4,
  ]);
  const Operation.get([
    this._pathVariable1,
    this._pathVariable2,
    this._pathVariable3,
    this._pathVariable4,
  ]) : method = 'GET';
  const Operation.post([
    this._pathVariable1,
    this._pathVariable2,
    this._pathVariable3,
    this._pathVariable4,
  ]) : method = 'POST';
  final String method;
  final String? _pathVariable1;
  final String? _pathVariable2;
  final String? _pathVariable3;
  final String? _pathVariable4;
}

abstract class Controller {}
abstract class ResourceController extends Controller {}
abstract class Serializable {
  void read(Map<String, dynamic> obj);
}

class RequestBody {
  T as<T>() => null as T;
}
''';

Future<({String? dart, String? json})> _runBuilder(String inputSource) async {
  final result = await testBuilder(
    controllerBuilder(BuilderOptions.empty),
    {
      'a|lib/controllers.dart': inputSource,
      'conduit_core|lib/conduit_core.dart': _conduitCoreStub,
      'conduit_core|lib/aot.dart': _conduitCoreStub,
    },
    flattenOutput: true,
  );
  final dartId = AssetId.parse('a|lib/controllers.controller.conduit.dart');
  final jsonId = AssetId.parse('a|lib/controllers.controller.conduit.json');
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
  test('emits a minimal runtime for a plain Controller subclass', () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

class HealthController extends Controller {}
''');
    expect(out.dart, isNotNull);
    expect(out.dart, contains(r'class $HealthControllerControllerRuntime'));
    expect(out.dart, contains('bool get isMutable => false'));
    expect(
      out.dart,
      contains('ResourceControllerRuntime? get resourceController => null'),
    );
    final manifest = json.decode(out.json!) as Map<String, dynamic>;
    expect(manifest['controllers'], equals(['HealthController']));
  });

  test('flags isMutable when a non-final field is present', () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

class MutableController extends Controller {
  String? cursor;
}
''');
    expect(out.dart, contains('bool get isMutable => true'));
  });

  test(
      'emits a ResourceControllerRuntime with one operation for a '
      '@Operation.get method', () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

class IdentityController extends ResourceController {
  @Operation.get('id')
  Future<dynamic> getOne(@Bind.path('id') int id) async => null;
}
''');
    expect(out.dart, contains(r'class $IdentityControllerControllerRuntime'));
    expect(out.dart,
        contains(r'class $IdentityControllerResourceControllerRuntime'));
    expect(out.dart, contains("dartMethodName: 'getOne'"));
    expect(out.dart, contains("httpMethod: 'GET'"));
    expect(out.dart, contains("pathVariables: ['id']"));
    expect(out.dart, contains('BindingType.path'));
    // Static-dispatch invoker must downcast to the concrete controller.
    expect(
      out.dart,
      contains('(rc as IdentityController).getOne('),
    );
  });

  test(
      'emits decoders for path/query/header/body bindings without crashing',
      () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

class Payload extends Serializable {
  @override
  void read(Map<String, dynamic> obj) {}
}

class MultiBindController extends ResourceController {
  @Operation.post('id')
  Future<dynamic> create(
    @Bind.path('id') int id,
    @Bind.query('name') String name,
    @Bind.header('X-Trace') String trace,
    @Bind.body() Payload body,
  ) async => null;
}
''');
    expect(out.dart, contains('BindingType.path'));
    expect(out.dart, contains('BindingType.query'));
    expect(out.dart, contains('BindingType.header'));
    expect(out.dart, contains('BindingType.body'));
    expect(out.dart, contains('Payload()..read'));
  });

  test('skips abstract Controller subclasses', () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

abstract class BaseController extends Controller {}
''');
    expect(out.dart, isNull);
    expect(out.json, isNull);
  });

  test('emits nothing when no Controller subclasses are present', () async {
    final out = await _runBuilder('''
class Plain {}
''');
    expect(out.dart, isNull);
    expect(out.json, isNull);
  });
}
