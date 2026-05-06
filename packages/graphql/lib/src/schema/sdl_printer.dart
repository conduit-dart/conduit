/// Minimal SDL printer for `graphql_schema2` schemas.
///
/// Used by the G2 golden-schema test. graphql_schema2 v6.5.0 does not
/// ship an SDL writer, and pulling in a separate parser/printer
/// dependency just for the golden test is overkill — so we hand-roll
/// a deterministic, minimal printer that covers exactly the surface
/// `SchemaBuilder` emits today (object types, scalars, lists,
/// non-null wrappers, field arguments, descriptions). Anything outside
/// that surface (interfaces, unions, enums, directives, mutations,
/// subscriptions, input objects) is not yet supported and will
/// throw — by design, so a future contributor adding e.g. mutation
/// support can't accidentally rely on a stale printer.
library;

import 'package:graphql_schema2/graphql_schema2.dart';

/// Renders [schema] as a deterministic SDL string.
///
/// Type ordering: `Query` first, then every other reachable
/// `GraphQLObjectType` in alphabetical order, then every reachable
/// scalar (alphabetical). Field ordering inside a type is preserved
/// from declaration.
String printSchema(GraphQLSchema schema) {
  final query = schema.queryType;
  if (query == null) {
    throw ArgumentError('Schema has no queryType');
  }

  final objectTypes = <GraphQLObjectType>{};
  final scalarTypes = <GraphQLType<dynamic, dynamic>>{};
  _collectTypes(query, objectTypes, scalarTypes);

  final buf = StringBuffer();

  // Custom (non-built-in) scalars first, alphabetical.
  final builtInScalarNames = {'Int', 'Float', 'String', 'Boolean', 'ID'};
  final customScalars = scalarTypes
      .where((s) => !builtInScalarNames.contains(s.name))
      .toList()
    ..sort((a, b) => a.name!.compareTo(b.name!));
  for (final s in customScalars) {
    if (s.description?.isNotEmpty == true) {
      buf.writeln('"""${s.description}"""');
    }
    buf.writeln('scalar ${s.name}');
    buf.writeln();
  }

  // Query first, then alphabetical.
  final orderedObjects = <GraphQLObjectType>[
    query,
    ...objectTypes.where((t) => t != query).toList()
      ..sort((a, b) => a.name.compareTo(b.name)),
  ];

  for (final t in orderedObjects) {
    if (t.description?.isNotEmpty == true) {
      buf.writeln('"""${t.description}"""');
    }
    buf.writeln('type ${t.name} {');
    for (final f in t.fields) {
      if (f.description?.isNotEmpty == true) {
        buf.writeln('  """${f.description}"""');
      }
      final args = _renderArgs(f.inputs);
      buf.writeln('  ${f.name}$args: ${_renderType(f.type)}');
    }
    buf.writeln('}');
    buf.writeln();
  }

  return '${buf.toString().trimRight()}\n';
}

void _collectTypes(
  GraphQLObjectType root,
  Set<GraphQLObjectType> objects,
  Set<GraphQLType<dynamic, dynamic>> scalars,
) {
  if (!objects.add(root)) return;
  for (final f in root.fields) {
    _walkType(f.type, objects, scalars);
    for (final input in f.inputs) {
      _walkType(input.type, objects, scalars);
    }
  }
}

void _walkType(
  GraphQLType<dynamic, dynamic> type,
  Set<GraphQLObjectType> objects,
  Set<GraphQLType<dynamic, dynamic>> scalars,
) {
  GraphQLType current = type;
  while (true) {
    if (current is GraphQLNonNullableType) {
      current = current.ofType;
      continue;
    }
    if (current is GraphQLListType) {
      current = current.ofType;
      continue;
    }
    if (current is GraphQLObjectType) {
      _collectTypes(current, objects, scalars);
      return;
    }
    if (current is GraphQLScalarType) {
      scalars.add(current);
      return;
    }
    throw UnsupportedError(
      'SDL printer does not yet handle type ${current.runtimeType} '
      '(named ${current.name}). Add support before extending the schema '
      'beyond object types + scalars.',
    );
  }
}

String _renderType(GraphQLType<dynamic, dynamic> type) {
  if (type is GraphQLNonNullableType) {
    return '${_renderType(type.ofType)}!';
  }
  if (type is GraphQLListType) {
    return '[${_renderType(type.ofType)}]';
  }
  if (type is GraphQLObjectType) return type.name;
  if (type is GraphQLScalarType) return type.name!;
  throw UnsupportedError(
    'SDL printer does not yet handle type ${type.runtimeType}',
  );
}

String _renderArgs(List<GraphQLFieldInput> inputs) {
  if (inputs.isEmpty) return '';
  final rendered = inputs
      .map((i) => '${i.name}: ${_renderType(i.type)}')
      .join(', ');
  return '($rendered)';
}
