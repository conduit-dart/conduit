import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:conduit_build_runner/src/managed_object_builder.dart';
import 'package:test/test.dart';

const _conduitCoreStub = '''
library conduit_core;

abstract class ManagedObject<T> {
  ManagedBacking? backing;
}

class ManagedBacking {}

abstract class ManagedEntityRuntime {
  ManagedEntity get entity;
  void finalize(ManagedDataModel dataModel) {}
  ManagedObject instanceOfImplementation({ManagedBacking? backing});
  ManagedSet setOfImplementation(Iterable<dynamic> objects);
  void setTransientValueForKey(
      ManagedObject object, String key, dynamic value);
  dynamic getTransientValueForKey(ManagedObject object, String? key);
  bool isValueInstanceOf(dynamic value);
  bool isValueListOf(dynamic value);
  String? getPropertyName(Invocation invocation, ManagedEntity entity);
  dynamic dynamicConvertFromPrimitiveValue(
      ManagedPropertyDescription property, dynamic value);
}

class ManagedEntity {
  ManagedEntity(this.tableName, this.instanceType, this.tableDefinitionName);
  final String tableName;
  final Type instanceType;
  final String tableDefinitionName;
  String primaryKey = '';
  Map<Symbol, String> symbolMap = {};
  Map<String, ManagedAttributeDescription?> attributes = {};
  Map<String, ManagedRelationshipDescription?> relationships = const {};
  List<ManagedValidator> validators = [];
  List<ManagedPropertyDescription>? uniquePropertySet;
  Map<String, ManagedPropertyDescription> get properties => {
        ...attributes.cast<String, ManagedPropertyDescription>(),
        ...relationships.cast<String, ManagedPropertyDescription>(),
      };
}

class ManagedDataModel {}

abstract class ManagedPropertyDescription {
  List<ManagedValidator> get validators;
}

class ManagedAttributeDescription extends ManagedPropertyDescription {
  ManagedAttributeDescription._();
  static ManagedAttributeDescription make<T>(
    ManagedEntity entity,
    String name,
    ManagedType type, {
    bool primaryKey = false,
    String? defaultValue,
    bool unique = false,
    bool indexed = false,
    bool nullable = false,
    bool includedInDefaultResultSet = true,
    bool autoincrement = false,
    List<ManagedValidator> validators = const [],
    Object? responseKey,
    Object? responseModel,
  }) =>
      ManagedAttributeDescription._();
  @override
  List<ManagedValidator> get validators => const [];
}

class ManagedRelationshipDescription extends ManagedPropertyDescription {
  @override
  List<ManagedValidator> get validators => const [];
}

class ManagedSet<T> {
  ManagedSet.fromDynamic(Iterable<dynamic> objects);
}

class ManagedType {
  ManagedType._();
  static ManagedType make<T>(
      ManagedPropertyType kind,
      ManagedType? elements,
      Map<String, dynamic> enumMap) =>
      ManagedType._();
}

enum ManagedPropertyType {
  string,
  integer,
  bigInteger,
  doublePrecision,
  boolean,
  datetime,
  document,
  list,
  map,
}

class ManagedValidator {
  ManagedValidator(this.validate, this.state);
  final Validate validate;
  final dynamic state;
}

class Validate {
  const Validate();
  dynamic compile(ManagedType type, {Type? relationshipInverseType}) => null;
}

class Column {
  const Column({
    this.databaseType,
    this.isPrimaryKey = false,
    this.autoincrement = false,
    this.defaultValue,
    this.isNullable = false,
    this.isUnique = false,
    this.isIndexed = false,
    this.shouldOmitByDefault = false,
    this.useSnakeCaseName = false,
    this.name,
  });
  final ManagedPropertyType? databaseType;
  final bool isPrimaryKey;
  final bool autoincrement;
  final String? defaultValue;
  final bool isNullable;
  final bool isUnique;
  final bool isIndexed;
  final bool shouldOmitByDefault;
  final bool useSnakeCaseName;
  final String? name;
}

const Column primaryKey = Column(
  isPrimaryKey: true,
  autoincrement: true,
  isIndexed: true,
);

class Table {
  const Table({
    this.name,
    this.useSnakeCaseName = true,
    this.useSnakeCaseColumnName = true,
    this.uniquePropertySet,
  });
  final String? name;
  final bool useSnakeCaseName;
  final bool useSnakeCaseColumnName;
  final List<Symbol>? uniquePropertySet;
}

class ResponseModel {
  const ResponseModel({this.includeIfNullField = true});
  final bool includeIfNullField;
}

class ResponseKey {
  const ResponseKey({this.name, this.includeIfNull = true});
  final String? name;
  final bool includeIfNull;
}

class Document {}
''';

Future<({String? dart, String? json})> _runBuilder(String source) async {
  final result = await testBuilder(
    managedObjectBuilder(BuilderOptions.empty),
    {
      'a|lib/models.dart': source,
      'conduit_core|lib/conduit_core.dart': _conduitCoreStub,
      'conduit_core|lib/aot.dart': _conduitCoreStub,
    },
    flattenOutput: true,
  );
  final dartId = AssetId.parse('a|lib/models.managed.conduit.dart');
  final jsonId = AssetId.parse('a|lib/models.managed.conduit.json');
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
  test('emits a runtime + manifest for a simple ManagedObject', () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

class _User {
  @primaryKey
  int? id;
  String? email;
}

class User extends ManagedObject<_User> implements _User {
  @override
  ManagedBacking? backing;
  @override
  int? id;
  @override
  String? email;
}
''');
    expect(out.dart, isNotNull);
    expect(out.dart, contains(r'class $UserEntityRuntime'));
    final flat = out.dart!.replaceAll(RegExp(r'\s+'), ' ');
    // Conduit convention: table-def class `_User` → table name `_user`
    // (recase snake_case preserves the leading underscore).
    expect(flat, contains("ManagedEntity( '_user'"));
    expect(flat, contains("entity.primaryKey = 'id'"));
    expect(flat, contains('primaryKey: true'));
    expect(flat, contains('instanceOfImplementation'));
    final manifest = json.decode(out.json!) as Map<String, dynamic>;
    expect(manifest['managedObjects'], equals(['User']));
  });

  test('honors @Table(name: ...) override for table name', () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

@Table(name: 'my_users')
class _User {
  @primaryKey
  int? id;
}

class User extends ManagedObject<_User> implements _User {
  @override
  ManagedBacking? backing;
  @override
  int? id;
}
''');
    final flat = out.dart!.replaceAll(RegExp(r'\s+'), ' ');
    expect(flat, contains("ManagedEntity( 'my_users'"));
  });

  test('skips classes that are not ManagedObject subclasses', () async {
    final out = await _runBuilder('''
class Plain {}
''');
    expect(out.dart, isNull);
    expect(out.json, isNull);
  });

  test('skips abstract subclasses', () async {
    final out = await _runBuilder('''
import 'package:conduit_core/conduit_core.dart';

class _Base {
  @primaryKey
  int? id;
}

abstract class Base extends ManagedObject<_Base> implements _Base {
  @override
  ManagedBacking? backing;
  @override
  int? id;
}
''');
    expect(out.dart, isNull);
    expect(out.json, isNull);
  });
}
