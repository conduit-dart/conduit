// Golden SQL fixtures for the predicate AST -> SQL render at the
// conduit_core boundary.
//
// Each case drives the real `Query.where(...)` DSL through the
// dialect-agnostic `QueryBuilder` (the same path every relational
// backend takes since #267/#275) and records, per dialect shape:
//
//   - the legacy `QueryPredicate.format` string the builders emit, and
//   - what `SqlDialect.renderExpression` produces from the attached AST,
//     plus the bound parameters (named map or positional list).
//
// The perf benches in bench/ catch render *cost* regressions; these
// goldens catch render *output* regressions (operator spelling,
// placeholder style, parameter naming, parenthesisation) that the
// benches cannot see.
//
// Regenerate after an intentional output change:
//
//   CONDUIT_UPDATE_GOLDENS=1 dart test test/db/predicate_render_golden_test.dart
//
// and review the fixture diff like any other code change.
import 'dart:io';

import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

import '../not_tests/helpers.dart';

const _goldenPath = 'test/db/goldens/predicate_render.golden';

/// Postgres-shaped: `@name` placeholders (the [SqlDialect] default),
/// named bindings, and `ILIKE` for case-insensitive matching -- a
/// distinct spelling, so the golden proves the dialect hook is honoured
/// by both the format string and the AST render.
class _AtNamedDialect extends SqlDialect {
  const new();
  @override
  String get name => 'named-at';
  @override
  String get caseInsensitiveLikeOperator => 'ILIKE';
  @override
  String? columnDefinitionType(
    String typeString, {
    required bool autoincrement,
  }) => null;
  @override
  String tableExistsQuery() => 'SELECT 1';
}

/// SQLite-shaped: `:name` placeholders, named bindings, default `LIKE`.
class const _ColonNamedDialect() extends SqlDialect {
  @override
  String get name => 'named-colon';
  @override
  String parameterPlaceholder(String name) => ':$name';
  @override
  String? columnDefinitionType(
    String typeString, {
    required bool autoincrement,
  }) => null;
  @override
  String tableExistsQuery() => 'SELECT 1';
}

/// MySQL-shaped: `?` placeholders, positional bindings.
class _PositionalDialect extends SqlDialect {
  const new();
  @override
  String get name => 'positional';
  @override
  SqlParameterStyle get parameterStyle => SqlParameterStyle.positional;
  @override
  String parameterPlaceholder(String name) => '?';
  @override
  String? columnDefinitionType(
    String typeString, {
    required bool autoincrement,
  }) => null;
  @override
  String tableExistsQuery() => 'SELECT 1';
}

class _DialectStore(@override final SqlDialect dialect)
    extends DefaultPersistentStore;

typedef _Shape = void Function(Query<GoldenBook> q);

/// The corpus. Names are the golden section headers -- keep them stable.
final Map<String, _Shape> _cases = {
  'eq int': (q) => q.where((o) => o.pages).equalTo(42),
  'not-eq int': (q) => q.where((o) => o.pages).notEqualTo(7),
  'eq string (case-sensitive)': (q) => q.where((o) => o.title).equalTo('Dune'),
  'eq string (case-insensitive)': (q) =>
      q.where((o) => o.title).equalTo('dune', caseSensitive: false),
  'not eq string': (q) => q.where((o) => o.title).not.equalTo('Dune'),
  // Two predicates per column force QueryPredicate.and to rename the
  // colliding parameters, which drops the AST (format fallback). KNOWN
  // BUG pinned here: the rename only rewrites `@name` placeholders, so
  // under `:name` dialects (SQLite, MySQL) the format string keeps the
  // original placeholder twice while the map holds the renamed key --
  // SQLite rejects the bind; see the named-colon block in the golden.
  // Fixing QueryPredicate.and will (correctly) change that block.
  'lt / lte / gt / gte AND chain': (q) => q
    ..where((o) => o.pages).lessThan(500)
    ..where((o) => o.pages).greaterThan(10)
    ..where((o) => o.rating).lessThanEqualTo(4.5)
    ..where((o) => o.rating).greaterThanEqualTo(1.0),
  'beginsWith': (q) => q.where((o) => o.title).beginsWith('The'),
  'endsWith (case-insensitive)': (q) =>
      q.where((o) => o.title).endsWith('ing', caseSensitive: false),
  'contains': (q) => q.where((o) => o.title).contains('of'),
  'not contains': (q) => q.where((o) => o.title).not.contains('of'),
  'like (wildcards passed through)': (q) =>
      q.where((o) => o.title).like('D_n%'),
  'oneOf': (q) => q.where((o) => o.pages).oneOf([1, 2, 3]),
  'not oneOf': (q) => q.where((o) => o.pages).not.oneOf([4, 5]),
  'between': (q) => q.where((o) => o.pages).between(100, 200),
  'outsideOf': (q) => q.where((o) => o.pages).outsideOf(100, 200),
  'isNull': (q) => q.where((o) => o.subtitle).isNull(),
  'isNotNull': (q) => q.where((o) => o.subtitle).isNotNull(),
  'foreign key via belongs-to': (q) => q.where((o) => o.author!.id).equalTo(9),
  'implicit join on related property': (q) =>
      q.where((o) => o.author!.name).beginsWith('Le Guin'),
  'injection-shaped value stays a parameter': (q) =>
      q.where((o) => o.title).equalTo("x'; DROP TABLE _goldenbook; --"),
  'mixed AND across five predicates': (q) => q
    ..where((o) => o.title).contains('a')
    ..where((o) => o.pages).oneOf([10, 20])
    ..where((o) => o.subtitle).isNotNull()
    ..where((o) => o.rating).between(2.0, 3.0)
    ..where((o) => o.pages).notEqualTo(15),
};

const _dialects = <SqlDialect>[
  _AtNamedDialect(),
  _ColonNamedDialect(),
  _PositionalDialect(),
];

/// Depth-first walk over the root builder and every joined table
/// builder, yielding each table's finalized predicate.
Iterable<(String, QueryPredicate)> _predicates(TableBuilder t) sync* {
  final p = t.predicate;
  if (p != null && p.format.isNotEmpty) {
    yield (t.sqlTableReference, p);
  }
  for (final child in t.returning.whereType<TableBuilder>()) {
    yield* _predicates(child);
  }
}

String _describe(Object? v) => switch (v) {
  null => 'null',
  final String s => "'$s'",
  _ => '$v',
};

/// Renders one case under one dialect into its golden text block and
/// enforces the hard invariant: the AST render is byte-identical to the
/// legacy format string the same builder produced.
String _renderCase(String caseName, _Shape shape, SqlDialect dialect) {
  final ctx = ManagedContext(
    ManagedDataModel([GoldenBook, GoldenAuthor]),
    _DialectStore(dialect),
  );
  final q = Query<GoldenBook>(ctx);
  shape(q);
  final builder = QueryBuilder(q as QueryMixin);

  final out = StringBuffer();
  for (final (table, predicate) in _predicates(builder)) {
    final expr = predicate.expression;
    if (expr == null) {
      // Predicates without an AST (legacy string predicates) execute
      // from the format string. Record that path verbatim.
      out.writeln('  [$table] (no AST; format fallback) ${predicate.format}');
      final keys = predicate.parameters.keys.toList()..sort();
      for (final k in keys) {
        out.writeln('    $k = ${_describe(predicate.parameters[k])}');
      }
      continue;
    }
    final rendered = dialect.renderExpression(expr);
    // When QueryPredicate.and renamed colliding keys, the legacy format
    // and the renderer pick different (equally valid) suffixes, so only
    // the bound values must agree; otherwise the text is identical.
    final renamed = !predicate.parameters.keys.toSet().containsAll(
      rendered.parameters.keys,
    );
    if (renamed) {
      expect(
        rendered.parameters.values.toList(),
        predicate.parameters.values.toList(),
        reason: '[$caseName/${dialect.name}] AST bound different values',
      );
    } else {
      expect(
        rendered.sql,
        predicate.format,
        reason:
            '[$caseName/${dialect.name}] AST render diverged from the '
            'legacy format string',
      );
    }

    out.writeln('  [$table] ${rendered.sql}');
    if (dialect.parameterStyle == SqlParameterStyle.named) {
      if (!renamed) expect(rendered.parameters, predicate.parameters);
      final keys = rendered.parameters.keys.toList()..sort();
      for (final k in keys) {
        out.writeln('    $k = ${_describe(rendered.parameters[k])}');
      }
    } else {
      expect(rendered.parameters, isEmpty);
      for (final (i, v) in rendered.positionalParameters.indexed) {
        out.writeln('    ?$i = ${_describe(v)}');
      }
    }
  }
  return out.toString();
}

String _renderAll() {
  final out = StringBuffer()
    ..writeln('# Generated by test/db/predicate_render_golden_test.dart.')
    ..writeln('# Regenerate with CONDUIT_UPDATE_GOLDENS=1; review the diff.');
  for (final MapEntry(key: name, value: shape) in _cases.entries) {
    out
      ..writeln()
      ..writeln('## $name');
    for (final d in _dialects) {
      out
        ..writeln('- ${d.name}')
        ..write(_renderCase(name, shape, d));
    }
  }
  return out.toString();
}

void main() {
  test('predicate AST render matches golden fixtures', () {
    final actual = _renderAll();
    final file = File(_goldenPath);
    if (Platform.environment['CONDUIT_UPDATE_GOLDENS'] == '1') {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(actual);
      markTestSkipped('golden regenerated at $_goldenPath');
      return;
    }
    expect(
      file.existsSync(),
      isTrue,
      reason: 'missing $_goldenPath; run with CONDUIT_UPDATE_GOLDENS=1',
    );
    // Normalise line endings so a CRLF checkout (Windows CI) compares
    // equal to the LF fixture.
    final expected = file.readAsStringSync().replaceAll('\r\n', '\n');
    expect(actual, expected);
  });

  test('injection-shaped values never reach the SQL text', () {
    const hostile = "x'; DROP TABLE _goldenbook; --";
    for (final d in _dialects) {
      final text = _renderCase(
        'hostile',
        (q) => q.where((o) => o.title).equalTo(hostile),
        d,
      );
      final sqlLines = text
          .split('\n')
          .where((l) => l.startsWith('  ['))
          .join('\n');
      expect(sqlLines, isNot(contains('DROP TABLE')), reason: d.name);
    }
  });
}

class _GoldenAuthor {
  @primaryKey
  int? id;

  String? name;

  ManagedSet<GoldenBook>? books;
}

class GoldenAuthor extends ManagedObject<_GoldenAuthor>
    implements _GoldenAuthor;

class _GoldenBook {
  @primaryKey
  int? id;

  String? title;

  @Column(nullable: true)
  String? subtitle;

  int? pages;

  double? rating;

  @Relate(Symbol('books'))
  GoldenAuthor? author;
}

class GoldenBook extends ManagedObject<_GoldenBook> implements _GoldenBook;
