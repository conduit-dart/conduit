import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';

/// Generates a `ManagedEntityRuntime` per `ManagedObject<T>` subclass in
/// the input library, replacing the mirror-based `ManagedEntityRuntimeImpl`
/// in `packages/core/lib/src/runtime/orm_impl.dart`.
///
/// Emits two siblings per source library:
///  - `<src>.managed.conduit.dart` — runtime code with one
///    `$<Class>EntityRuntime` per ManagedObject subclass, plus a
///    free-standing `ManagedEntity` factory.
///  - `<src>.managed.conduit.json` — manifest the registry builder reads
///    to install entities into the data model. Schema:
///    `{"managedObjects": ["User", ...]}`.
///
/// **Phase 1 scope** — single-table entities (no `@Relate`), no enum-typed
/// columns, no transient `@Serialize`-annotated getters/setters. Apps that
/// need any of those should keep building via `conduit build` until the
/// follow-ups land. The output here is good enough to AOT-compile a basic
/// CRUD app whose ManagedObjects don't reference one another.
///
/// What is supported:
///  - `@primaryKey int`, `@Column(...)` with primaryKey/unique/indexed/
///    nullable/omitByDefault/autoincrement/defaultValue/databaseType/
///    useSnakeCaseName/name.
///  - `@Validate(...)` and `@ValidatePresent`/etc — copied verbatim into
///    the emitted source so const-instances and named constructors round-
///    trip exactly.
///  - `@ResponseKey(...)` and `@ResponseModel(...)`.
///  - Standard column types: `int`, `String`, `bool`, `double`, `DateTime`,
///    `Document`, `List<int>`.
class ManagedObjectBuilder implements Builder {
  static const _conduitCorePackagePrefix = 'package:conduit_core/';
  static const _managedObjectName = 'ManagedObject';

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.managed.conduit.dart', '.managed.conduit.json'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    if (!await buildStep.resolver.isLibrary(input)) return;
    final lib = await buildStep.inputLibrary;

    final entities = <_EntityAnalysis>[];
    for (final klass in lib.classes) {
      if (klass.isAbstract) continue;
      final analysis = _analyzeManagedObject(klass);
      if (analysis != null) entities.add(analysis);
    }

    if (entities.isEmpty) return;

    final manifest = {
      'managedObjects': entities.map((e) => e.instanceClassName).toList(),
    };
    await buildStep.writeAsString(
      input.changeExtension('.managed.conduit.json'),
      json.encode(manifest),
    );

    final inputUri = input.uri.toString();
    final extraImports = <String>{};
    for (final e in entities) {
      extraImports.addAll(e.requiredImportUris);
    }
    extraImports.removeWhere((u) => u == inputUri);

    final buf = StringBuffer()
      ..writeln(
        '// GENERATED CODE - DO NOT MODIFY BY HAND. '
        'conduit_build_runner ManagedObjectBuilder.',
      )
      ..writeln(
        '// ignore_for_file: type=lint, directives_ordering, '
        'no_leading_underscores_for_local_identifiers, '
        'unused_local_variable, unnecessary_cast',
      )
      ..writeln()
      ..writeln("import 'package:conduit_core/aot.dart';")
      ..writeln("import '$inputUri';");
    for (final u in extraImports) {
      buf.writeln("import '$u';");
    }
    buf.writeln();

    for (final e in entities) {
      buf.writeln(_emitRuntime(e));
    }

    await buildStep.writeAsString(
      input.changeExtension('.managed.conduit.dart'),
      buf.toString(),
    );
  }

  /// Returns a non-null analysis iff [klass] is a concrete subclass of
  /// `ManagedObject<T>` from `package:conduit_core`.
  _EntityAnalysis? _analyzeManagedObject(ClassElement klass) {
    final managedSuper = _findManagedObjectSupertype(klass);
    if (managedSuper == null) return null;
    if (managedSuper.typeArguments.isEmpty) return null;
    final tableDefType = managedSuper.typeArguments.first;
    if (tableDefType is! InterfaceType) return null;
    final tableDefElement = tableDefType.element;

    final tableMeta = _readTableAnnotation(tableDefElement.metadata.annotations);
    final responseModelMeta =
        _readResponseModelAnnotation(tableDefElement.metadata.annotations);

    final useSnakeCaseTable = tableMeta?.useSnakeCaseName ?? true;
    final useSnakeCaseColumn = tableMeta?.useSnakeCaseColumnName ?? true;

    final tableName = tableMeta?.name ?? _maybeSnake(tableDefElement.name ?? '', useSnakeCaseTable);
    if (tableName.isEmpty) return null;

    final imports = <String>{};
    final tableUri = tableDefElement.library.identifier;
    imports.add(tableUri);

    final properties = <_PropertyAnalysis>[];
    for (final field in tableDefElement.fields) {
      if (field.isStatic) continue;
      if (field.isSynthetic) continue;
      final propName = field.name;
      if (propName == null) continue;
      final analysis = _analyzePersistentField(
        field,
        useSnakeCase: useSnakeCaseColumn,
        imports: imports,
      );
      if (analysis == null) continue;
      properties.add(analysis);
    }

    final primaryKey = properties.firstWhereOrNull((p) => p.primaryKey);
    if (primaryKey == null) return null;

    return _EntityAnalysis(
      instanceClassName: klass.name ?? '',
      tableDefinitionClassName: tableDefElement.name ?? '',
      tableName: tableName,
      primaryKeyName: primaryKey.name,
      properties: properties,
      uniquePropertySet: tableMeta?.uniquePropertySet,
      responseModelLiteral: responseModelMeta,
      requiredImportUris: imports,
    );
  }

  InterfaceType? _findManagedObjectSupertype(ClassElement klass) {
    for (final t in klass.allSupertypes) {
      final el = t.element;
      if (el.name != _managedObjectName) continue;
      if (!el.library.identifier.startsWith(_conduitCorePackagePrefix)) {
        continue;
      }
      return t;
    }
    return null;
  }

  _PropertyAnalysis? _analyzePersistentField(
    FieldElement field, {
    required bool useSnakeCase,
    required Set<String> imports,
  }) {
    final annotations = field.metadata.annotations;
    final fieldName = field.name;
    if (fieldName == null) return null;
    final fieldType = field.type;
    if (fieldType is! InterfaceType) return null;

    final isPrimaryKey = annotations.any(_isPrimaryKeyAnnotation);
    final columnMeta = _readColumnAnnotation(annotations);

    final ann = _ColumnAnnotation(
      isPrimaryKey: columnMeta?.isPrimaryKey ?? isPrimaryKey,
      autoincrement:
          columnMeta?.autoincrement ?? (isPrimaryKey ? true : false),
      isNullable: columnMeta?.isNullable ?? false,
      isUnique: columnMeta?.isUnique ?? false,
      isIndexed: columnMeta?.isIndexed ?? (isPrimaryKey ? true : false),
      shouldOmitByDefault: columnMeta?.shouldOmitByDefault ?? false,
      defaultValueLiteral: isPrimaryKey
          ? null
          : (columnMeta?.defaultValueLiteral),
      databaseType: columnMeta?.databaseType,
      useSnakeCaseName: columnMeta?.useSnakeCaseName ?? useSnakeCase,
      explicitName: columnMeta?.explicitName,
    );

    final managedType = _resolveManagedType(fieldType);
    if (managedType == null) return null;

    final columnName = ann.explicitName ??
        _maybeSnake(fieldName, ann.useSnakeCaseName ?? useSnakeCase);

    final validatorSources = <String>[];
    for (final a in annotations) {
      final src = _validatorSourceFromAnnotation(a, imports);
      if (src != null) validatorSources.add(src);
    }

    final responseKey = _readResponseKeyAnnotation(annotations);

    return _PropertyAnalysis(
      name: columnName,
      propertyName: fieldName,
      declaredTypeSource: _typeSourceWithoutNullable(fieldType),
      managedTypeKind: managedType.kind,
      managedTypeArgs: managedType.typeArguments,
      primaryKey: ann.isPrimaryKey,
      autoincrement: ann.autoincrement,
      nullable: ann.isNullable,
      unique: ann.isUnique,
      indexed: ann.isIndexed,
      includedInDefaultResultSet: !ann.shouldOmitByDefault,
      defaultValueLiteral: ann.defaultValueLiteral,
      validatorSources: validatorSources,
      responseKeyLiteral: responseKey,
    );
  }

  /// Maps a Dart type to the `ManagedPropertyType` kind the runtime
  /// switches on. Returns null for unsupported types.
  _ManagedTypeInfo? _resolveManagedType(InterfaceType t) {
    final name = t.element.name ?? '';
    switch (name) {
      case 'int':
        return _ManagedTypeInfo('integer', name);
      case 'String':
        return _ManagedTypeInfo('string', name);
      case 'bool':
        return _ManagedTypeInfo('boolean', name);
      case 'double':
        return _ManagedTypeInfo('doublePrecision', name);
      case 'DateTime':
        return _ManagedTypeInfo('datetime', name);
      case 'Document':
        return _ManagedTypeInfo('document', name);
      case 'List':
        if (t.typeArguments.length == 1 &&
            (t.typeArguments.first.element?.name == 'int')) {
          return _ManagedTypeInfo('list', 'List<int>',
              typeArguments: ['int']);
        }
        return null;
      default:
        return null;
    }
  }

  bool _isPrimaryKeyAnnotation(ElementAnnotation a) {
    final element = a.element;
    if (element == null) return false;
    // primaryKey is a top-level const Column(...) — match by simple name.
    final value = a.computeConstantValue();
    if (value == null) return false;
    final t = value.type;
    if (t is! InterfaceType) return false;
    if (!t.element.library.identifier
        .startsWith(_conduitCorePackagePrefix)) return false;
    if (t.element.name != 'Column') return false;
    return value.getField('isPrimaryKey')?.toBoolValue() == true;
  }

  _ColumnAnnotation? _readColumnAnnotation(List<ElementAnnotation> metadata) {
    for (final a in metadata) {
      final value = a.computeConstantValue();
      if (value == null) continue;
      final t = value.type;
      if (t is! InterfaceType) continue;
      if (!t.element.library.identifier
          .startsWith(_conduitCorePackagePrefix)) continue;
      if (t.element.name != 'Column') continue;

      final defaultValueRaw = value.getField('defaultValue')?.toStringValue();
      String? defaultLiteral;
      if (defaultValueRaw != null) {
        defaultLiteral = "'${defaultValueRaw.replaceAll("'", r"\'")}'";
      }

      return _ColumnAnnotation(
        isPrimaryKey: value.getField('isPrimaryKey')?.toBoolValue() ?? false,
        autoincrement:
            value.getField('autoincrement')?.toBoolValue() ?? false,
        isNullable: value.getField('isNullable')?.toBoolValue() ?? false,
        isUnique: value.getField('isUnique')?.toBoolValue() ?? false,
        isIndexed: value.getField('isIndexed')?.toBoolValue() ?? false,
        shouldOmitByDefault:
            value.getField('shouldOmitByDefault')?.toBoolValue() ?? false,
        defaultValueLiteral: defaultLiteral,
        databaseType: _readManagedPropertyTypeEnum(
            value.getField('databaseType')),
        useSnakeCaseName: value.getField('useSnakeCaseName')?.toBoolValue(),
        explicitName: value.getField('name')?.toStringValue(),
      );
    }
    return null;
  }

  String? _readManagedPropertyTypeEnum(Object? field) {
    if (field == null) return null;
    // Stored as enum index in analyzer's DartObject; map to name.
    final getter = (field as dynamic).getField as dynamic;
    try {
      final n = getter('_name')?.toStringValue();
      if (n != null) return 'ManagedPropertyType.$n';
    } catch (_) {}
    return null;
  }

  _TableAnnotation? _readTableAnnotation(List<ElementAnnotation> metadata) {
    for (final a in metadata) {
      final value = a.computeConstantValue();
      if (value == null) continue;
      final t = value.type;
      if (t is! InterfaceType) continue;
      if (!t.element.library.identifier
          .startsWith(_conduitCorePackagePrefix)) continue;
      if (t.element.name != 'Table') continue;
      return _TableAnnotation(
        name: value.getField('name')?.toStringValue(),
        useSnakeCaseName:
            value.getField('useSnakeCaseName')?.toBoolValue() ?? true,
        useSnakeCaseColumnName:
            value.getField('useSnakeCaseColumnName')?.toBoolValue() ?? true,
        uniquePropertySet: _readSymbolList(
          value.getField('uniquePropertySet'),
        ),
      );
    }
    return null;
  }

  List<String>? _readSymbolList(Object? field) {
    if (field == null) return null;
    try {
      final list = (field as dynamic).toListValue();
      if (list == null) return null;
      final names = <String>[];
      for (final v in list) {
        final s = (v as dynamic).toSymbolValue();
        if (s is String) names.add(s);
      }
      return names;
    } catch (_) {
      return null;
    }
  }

  String? _readResponseModelAnnotation(List<ElementAnnotation> metadata) {
    for (final a in metadata) {
      final value = a.computeConstantValue();
      if (value == null) continue;
      final t = value.type;
      if (t is! InterfaceType) continue;
      if (!t.element.library.identifier
          .startsWith(_conduitCorePackagePrefix)) continue;
      if (t.element.name != 'ResponseModel') continue;
      final include =
          value.getField('includeIfNullField')?.toBoolValue() ?? true;
      return 'const ResponseModel(includeIfNullField: $include)';
    }
    return null;
  }

  String? _readResponseKeyAnnotation(List<ElementAnnotation> metadata) {
    for (final a in metadata) {
      final value = a.computeConstantValue();
      if (value == null) continue;
      final t = value.type;
      if (t is! InterfaceType) continue;
      if (!t.element.library.identifier
          .startsWith(_conduitCorePackagePrefix)) continue;
      if (t.element.name != 'ResponseKey') continue;
      final name = value.getField('name')?.toStringValue();
      final includeIfNull =
          value.getField('includeIfNull')?.toBoolValue() ?? true;
      final nameSrc = name == null ? 'null' : "'$name'";
      return 'const ResponseKey(name: $nameSrc, includeIfNull: $includeIfNull)';
    }
    return null;
  }

  /// If [a] is a `@Validate*` const-instance annotation, return its
  /// source so we can copy it verbatim into the emitted runtime. Adds the
  /// declaring library URI to [imports].
  String? _validatorSourceFromAnnotation(
    ElementAnnotation a,
    Set<String> imports,
  ) {
    final value = a.computeConstantValue();
    if (value == null) return null;
    final t = value.type;
    if (t is! InterfaceType) return null;
    final el = t.element;
    final libUri = el.library.identifier;
    if (!libUri.startsWith(_conduitCorePackagePrefix)) return null;
    final isValidate = el.allSupertypes
            .any((s) => s.element.name == 'Validate') ||
        el.name == 'Validate';
    if (!isValidate) return null;
    imports.add(libUri);
    final src = a.toSource();
    if (src.startsWith('@')) return src.substring(1);
    return src;
  }

  String _emitRuntime(_EntityAnalysis e) {
    final attrEntries = e.properties
        .map(
          (p) => "'${p.propertyName}': ${_attributeInstantiator(e, p)}",
        )
        .join(', ');

    final symbolMapEntries = StringBuffer();
    for (final p in e.properties) {
      symbolMapEntries.writeln(
        "      Symbol('${p.propertyName}'): '${p.propertyName}',",
      );
      symbolMapEntries.writeln(
        "      Symbol('${p.propertyName}='): '${p.propertyName}',",
      );
    }

    final uniqueLiteral = e.uniquePropertySet == null
        ? 'null'
        : '[${e.uniquePropertySet!.map((s) => "'$s'").join(',')}]'
            ".map((k) => entity.properties[k]).whereType<ManagedPropertyDescription>().toList()";

    return '''
class \$${e.instanceClassName}EntityRuntime extends ManagedEntityRuntime {
  \$${e.instanceClassName}EntityRuntime() {
    _entity = _build();
  }

  late final ManagedEntity _entity;

  @override
  ManagedEntity get entity => _entity;

  ManagedEntity _build() {
    final entity = ManagedEntity(
      '${e.tableName}',
      ${e.instanceClassName},
      '${e.tableDefinitionClassName}',
    )..validators = [];
    entity.primaryKey = '${e.primaryKeyName}';
    entity.symbolMap = {
${symbolMapEntries.toString().trimRight()}
    };
    entity.attributes = <String, ManagedAttributeDescription?>{$attrEntries};
    return entity;
  }

  @override
  void finalize(ManagedDataModel dataModel) {
    _entity.relationships = const <String, ManagedRelationshipDescription?>{};
    _entity.validators = [];
    _entity.validators.addAll(_entity.attributes.values
        .expand((a) => a == null ? const <ManagedValidator>[] : a.validators));
    _entity.uniquePropertySet = $uniqueLiteral;
  }

  @override
  ManagedObject instanceOfImplementation({ManagedBacking? backing}) {
    final object = ${e.instanceClassName}();
    if (backing != null) {
      object.backing = backing;
    }
    return object;
  }

  @override
  ManagedSet setOfImplementation(Iterable<dynamic> objects) {
    return ManagedSet<${e.instanceClassName}>.fromDynamic(objects);
  }

  @override
  void setTransientValueForKey(
    ManagedObject object,
    String key,
    dynamic value,
  ) {}

  @override
  dynamic getTransientValueForKey(ManagedObject object, String? key) => null;

  @override
  bool isValueInstanceOf(dynamic value) => value is ${e.instanceClassName};

  @override
  bool isValueListOf(dynamic value) => value is List<${e.instanceClassName}>;

  @override
  String? getPropertyName(Invocation invocation, ManagedEntity entity) {
    return entity.symbolMap[invocation.memberName];
  }

  @override
  dynamic dynamicConvertFromPrimitiveValue(
    ManagedPropertyDescription property,
    dynamic value,
  ) {
    return value;
  }
}
''';
  }

  String _attributeInstantiator(_EntityAnalysis e, _PropertyAnalysis p) {
    final validatorSrc = p.validatorSources.isEmpty
        ? '<ManagedValidator>[]'
        : '() {'
            'final out = <ManagedValidator>[];'
            'for (final v in <Validate>[${p.validatorSources.join(', ')}]) {'
            '  final state = v.compile('
            '    ManagedType.make<${p.declaredTypeSource}>(${_managedKindName(p.managedTypeKind)}, null, const <String, dynamic>{}),'
            '    relationshipInverseType: null);'
            '  out.add(ManagedValidator(v, state));'
            '}'
            'return out;'
            '}()';

    final defaultValue = p.defaultValueLiteral ?? 'null';
    final responseKey = p.responseKeyLiteral ?? 'null';
    final responseModel = e.responseModelLiteral ?? 'null';

    return '''ManagedAttributeDescription.make<${p.declaredTypeSource}>(
        entity,
        '${p.propertyName}',
        ManagedType.make<${p.declaredTypeSource}>(${_managedKindName(p.managedTypeKind)}, null, const <String, dynamic>{}),
        primaryKey: ${p.primaryKey},
        defaultValue: $defaultValue,
        unique: ${p.unique},
        indexed: ${p.indexed},
        nullable: ${p.nullable},
        includedInDefaultResultSet: ${p.includedInDefaultResultSet},
        autoincrement: ${p.autoincrement},
        validators: $validatorSrc,
        responseKey: $responseKey,
        responseModel: $responseModel)''';
  }

  String _managedKindName(String kind) => 'ManagedPropertyType.$kind';

  /// Roughly equivalent to `recase`'s `String.snakeCase` (which the mirror
  /// impl uses): split on non-alphanumerics + camelCase boundaries, lowercase,
  /// rejoin with `_`, but preserve a single leading `_` (the conduit
  /// convention for table-def classes is `_User` → `_user`).
  static String _maybeSnake(String name, bool useSnake) {
    if (!useSnake) return name;
    if (name.isEmpty) return name;
    final hasLeadingUnderscore = name.startsWith('_');
    var body = name;
    while (body.startsWith('_')) {
      body = body.substring(1);
    }
    final words = <String>[];
    final current = StringBuffer();
    for (var i = 0; i < body.length; i++) {
      final c = body[i];
      final isUpper = c == c.toUpperCase() && c != c.toLowerCase();
      if (c == '_' || c == '-' || c == ' ') {
        if (current.isNotEmpty) {
          words.add(current.toString());
          current.clear();
        }
        continue;
      }
      if (isUpper && current.isNotEmpty) {
        words.add(current.toString());
        current.clear();
      }
      current.write(c.toLowerCase());
    }
    if (current.isNotEmpty) words.add(current.toString());
    final joined = words.join('_');
    return hasLeadingUnderscore ? '_$joined' : joined;
  }

  static String _typeSourceWithoutNullable(DartType t) {
    final s = t.getDisplayString();
    return s.endsWith('?') ? s.substring(0, s.length - 1) : s;
  }
}

class _EntityAnalysis {
  _EntityAnalysis({
    required this.instanceClassName,
    required this.tableDefinitionClassName,
    required this.tableName,
    required this.primaryKeyName,
    required this.properties,
    required this.uniquePropertySet,
    required this.responseModelLiteral,
    required this.requiredImportUris,
  });
  final String instanceClassName;
  final String tableDefinitionClassName;
  final String tableName;
  final String primaryKeyName;
  final List<_PropertyAnalysis> properties;
  final List<String>? uniquePropertySet;
  final String? responseModelLiteral;
  final Set<String> requiredImportUris;
}

class _PropertyAnalysis {
  _PropertyAnalysis({
    required this.name,
    required this.propertyName,
    required this.declaredTypeSource,
    required this.managedTypeKind,
    required this.managedTypeArgs,
    required this.primaryKey,
    required this.autoincrement,
    required this.nullable,
    required this.unique,
    required this.indexed,
    required this.includedInDefaultResultSet,
    required this.defaultValueLiteral,
    required this.validatorSources,
    required this.responseKeyLiteral,
  });
  final String name;
  final String propertyName;
  final String declaredTypeSource;
  final String managedTypeKind;
  final List<String> managedTypeArgs;
  final bool primaryKey;
  final bool autoincrement;
  final bool nullable;
  final bool unique;
  final bool indexed;
  final bool includedInDefaultResultSet;
  final String? defaultValueLiteral;
  final List<String> validatorSources;
  final String? responseKeyLiteral;
}

class _ColumnAnnotation {
  _ColumnAnnotation({
    required this.isPrimaryKey,
    required this.autoincrement,
    required this.isNullable,
    required this.isUnique,
    required this.isIndexed,
    required this.shouldOmitByDefault,
    required this.defaultValueLiteral,
    required this.databaseType,
    required this.useSnakeCaseName,
    required this.explicitName,
  });
  final bool isPrimaryKey;
  final bool autoincrement;
  final bool isNullable;
  final bool isUnique;
  final bool isIndexed;
  final bool shouldOmitByDefault;
  final String? defaultValueLiteral;
  final String? databaseType;
  final bool? useSnakeCaseName;
  final String? explicitName;
}

class _TableAnnotation {
  _TableAnnotation({
    required this.name,
    required this.useSnakeCaseName,
    required this.useSnakeCaseColumnName,
    required this.uniquePropertySet,
  });
  final String? name;
  final bool useSnakeCaseName;
  final bool useSnakeCaseColumnName;
  final List<String>? uniquePropertySet;
}

class _ManagedTypeInfo {
  _ManagedTypeInfo(this.kind, this.dartName, {this.typeArguments = const []});
  final String kind;
  final String dartName;
  final List<String> typeArguments;
}

extension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

Builder managedObjectBuilder(BuilderOptions options) =>
    ManagedObjectBuilder();
