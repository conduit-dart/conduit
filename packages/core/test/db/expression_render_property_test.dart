// Property tests for the predicate AST -> SQL render round-trip.
//
// Hand-rolled and table-driven rather than via package:glados: a
// seeded generator builds random `SqlExpression` trees, and each
// property is checked against every seed. A failure message names the
// seed and the offending tree, so any counter-example is reproducible
// with a one-line change to `_seeds`.
//
// Properties:
//   1. Positional arity + order: `?` count == bound-value count == the
//      AST's parameter count, and values arrive in source order.
//   2. Named completeness: every bound name appears exactly once as a
//      placeholder, including when ParameterExpression names collide.
//   3. Named <-> positional round-trip: rewriting each `@name` in the
//      named render to `?` yields the positional render, and looking
//      the names up in the named map yields the positional list.
//   4. Values never reach the SQL text, whatever they contain.
//   5. QueryPredicate.and over AST-carrying leaves keeps the AST, and
//      its render is byte-identical to the combined format string (the
//      Postgres back-compat invariant from #267).
//   6. Rendering is deterministic.
import 'dart:math';

import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

class _NamedDialect extends SqlDialect {
  const _NamedDialect();
  @override
  String get name => 'named';
  @override
  String? columnDefinitionType(
    String typeString, {
    required bool autoincrement,
  }) => null;
  @override
  String tableExistsQuery() => 'SELECT 1';
}

class _PositionalDialect extends SqlDialect {
  const _PositionalDialect();
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

const _named = _NamedDialect();
const _positional = _PositionalDialect();

final _seeds = List<int>.generate(400, (i) => i);

/// Every bound value carries this marker so property 4 can look for
/// leaks without false positives from column names or operators.
const _marker = 'VAL⁣';

const _hostileValues = <Object?>[
  "$_marker'; DROP TABLE users; --",
  '$_marker @other ?',
  '$_marker%_\\',
  '$_marker\n) OR (1=1',
  _marker,
];

final _placeholder = RegExp(r'@(\w+)');

/// Random predicate-AST generator.
///
/// [collidingNames] draws ParameterExpression names from a two-name
/// pool so the named visitor's collision suffixing gets exercised;
/// otherwise names are unique. Raw fragments are only emitted with
/// unique names -- RawExpression bindings are merged verbatim by
/// design (see the visitor docs), so they are out of scope for the
/// collision property.
class _Gen {
  _Gen(int seed, {this.collidingNames = false}) : _r = Random(seed);

  final Random _r;
  final bool collidingNames;
  var _counter = 0;

  static const _columns = ['id', 'name', 'age', 'email', 'created_at'];
  static const _tables = ['t0', 't1', 'users'];
  static const _binOps = ['=', '!=', '<', '>', '<=', '>='];
  static const _literals = ['NULL', '1', 'TRUE', "'lit'"];

  T _pick<T>(List<T> xs) => xs[_r.nextInt(xs.length)];

  Object? _value() =>
      _r.nextBool() ? _pick(_hostileValues) : '$_marker${_r.nextInt(1000)}';

  ColumnExpression column() =>
      ColumnExpression(_pick(_columns), tableNamespace: _pick(_tables));

  ParameterExpression param() {
    final name = collidingNames ? _pick(const ['p', 'q']) : 'p${_counter++}';
    return ParameterExpression(name, _value());
  }

  SqlExpression operand() => switch (_r.nextInt(3)) {
    0 => column(),
    1 => LiteralExpression(_pick(_literals)),
    _ => param(),
  };

  SqlExpression leaf() => switch (_r.nextInt(collidingNames ? 5 : 6)) {
    0 => BinaryOpExpression(_pick(_binOps), column(), param()),
    1 => IsNullExpression(column(), negated: _r.nextBool()),
    2 => LikeExpression(
      column(),
      param(),
      caseSensitive: _r.nextBool(),
      negated: _r.nextBool(),
    ),
    3 => InExpression(
      column(),
      List.generate(1 + _r.nextInt(4), (_) => operand()),
      negated: _r.nextBool(),
    ),
    4 => BetweenExpression(column(), param(), param(), negated: _r.nextBool()),
    _ => () {
      final n = 'r${_counter++}';
      return RawExpression('raw_fn(@$n)', {n: _value()});
    }(),
  };

  SqlExpression tree([int depth = 0]) {
    if (depth >= 3 || _r.nextInt(3) == 0) {
      return leaf();
    }
    return switch (_r.nextInt(3)) {
      0 => UnaryOpExpression('NOT', tree(depth + 1)),
      _ => LogicalExpression(
        _r.nextBool() ? 'AND' : 'OR',
        List.generate(2 + _r.nextInt(3), (_) => tree(depth + 1)),
      ),
    };
  }
}

/// Bound values in the order their placeholders appear in the SQL.
List<Object?> _valuesInSourceOrder(SqlExpression e) => switch (e) {
  ParameterExpression(:final value) => [value],
  BinaryOpExpression(:final left, :final right) => [
    ..._valuesInSourceOrder(left),
    ..._valuesInSourceOrder(right),
  ],
  UnaryOpExpression(:final operand) => _valuesInSourceOrder(operand),
  LogicalExpression(:final children) => [
    for (final c in children) ..._valuesInSourceOrder(c),
  ],
  IsNullExpression(:final operand) => _valuesInSourceOrder(operand),
  LikeExpression(:final target, :final pattern) => [
    ..._valuesInSourceOrder(target),
    ..._valuesInSourceOrder(pattern),
  ],
  InExpression(:final target, :final values) => [
    ..._valuesInSourceOrder(target),
    for (final v in values) ..._valuesInSourceOrder(v),
  ],
  BetweenExpression(:final target, :final low, :final high) => [
    ..._valuesInSourceOrder(target),
    ..._valuesInSourceOrder(low),
    ..._valuesInSourceOrder(high),
  ],
  RawExpression(:final sql, :final parameters) => [
    for (final m in _placeholder.allMatches(sql)) parameters[m.group(1)],
  ],
  _ => const [],
};

void _forAllSeeds(String property, void Function(int seed) check) {
  test(property, () {
    for (final seed in _seeds) {
      check(seed);
    }
  });
}

String _why(int seed, RenderedExpression r) => 'seed=$seed\nsql=${r.sql}';

void main() {
  _forAllSeeds('positional: placeholder count and order match the AST', (seed) {
    final tree = _Gen(seed).tree();
    final r = _positional.renderExpression(tree);
    final expected = _valuesInSourceOrder(tree);
    expect(r.parameters, isEmpty, reason: _why(seed, r));
    expect(
      '?'.allMatches(r.sql).length,
      expected.length,
      reason: _why(seed, r),
    );
    expect(r.positionalParameters, expected, reason: _why(seed, r));
  });

  for (final colliding in [false, true]) {
    _forAllSeeds('named: every binding appears exactly once as a placeholder'
        '${colliding ? ' (colliding names)' : ''}', (seed) {
      final tree = _Gen(seed, collidingNames: colliding).tree();
      final r = _named.renderExpression(tree);
      final used = [
        for (final m in _placeholder.allMatches(r.sql)) m.group(1)!,
      ];
      expect(
        used.length,
        _valuesInSourceOrder(tree).length,
        reason: _why(seed, r),
      );
      expect(used.toSet().length, used.length, reason: _why(seed, r));
      expect(used.toSet(), r.parameters.keys.toSet());
      expect(r.positionalParameters, isEmpty);
    });
  }

  _forAllSeeds('named and positional renders round-trip', (seed) {
    final tree = _Gen(seed).tree();
    final named = _named.renderExpression(tree);
    final positional = _positional.renderExpression(tree);
    expect(
      named.sql.replaceAll(_placeholder, '?'),
      positional.sql,
      reason: 'seed=$seed',
    );
    expect(
      [
        for (final m in _placeholder.allMatches(named.sql))
          named.parameters[m.group(1)],
      ],
      positional.positionalParameters,
      reason: 'seed=$seed',
    );
  });

  _forAllSeeds('bound values never appear in the SQL text', (seed) {
    final tree = _Gen(seed).tree();
    for (final d in const <SqlDialect>[_named, _positional]) {
      final r = d.renderExpression(tree);
      expect(r.sql, isNot(contains(_marker)), reason: _why(seed, r));
    }
  });

  _forAllSeeds('QueryPredicate.and keeps an AST byte-identical to format', (
    seed,
  ) {
    final gen = _Gen(seed);
    final rnd = Random(seed);
    final leaves = List.generate(2 + rnd.nextInt(4), (_) {
      final ast = gen.tree(2);
      final r = _named.renderExpression(ast);
      return QueryPredicate.withExpression(ast, r.sql, r.parameters);
    });
    final combined = QueryPredicate.and(leaves);
    final expr = combined.expression;
    expect(expr, isNotNull, reason: 'seed=$seed');
    final r = _named.renderExpression(expr!);
    expect(r.sql, combined.format, reason: 'seed=$seed');
    expect(r.parameters, combined.parameters, reason: 'seed=$seed');
  });

  _forAllSeeds('rendering is deterministic', (seed) {
    final tree = _Gen(seed, collidingNames: seed.isOdd).tree();
    for (final d in const <SqlDialect>[_named, _positional]) {
      final a = d.renderExpression(tree);
      final b = d.renderExpression(tree);
      expect(a.sql, b.sql);
      expect(a.parameters, b.parameters);
      expect(a.positionalParameters, b.positionalParameters);
    }
  });
}
