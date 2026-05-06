import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

/// Stand-alone dialect for the visitor tests. We don't import a
/// concrete backend dialect (postgres / sqlite / mysql) here because
/// (a) cross-package test deps are awkward, and (b) the visitor's
/// behavior is the contract we're testing, not the dialect's
/// per-operator overrides — those live in each backend's dialect tests.
class _NamedDialect extends SqlDialect {
  const _NamedDialect();
  @override
  String get name => 'named-test';
  @override
  String? columnDefinitionType(String typeString,
          {required bool autoincrement}) =>
      null;
  @override
  String tableExistsQuery() => 'SELECT 1';
}

/// Same as above but in positional mode and emitting `?` placeholders.
class _PositionalDialect extends SqlDialect {
  const _PositionalDialect();
  @override
  String get name => 'positional-test';
  @override
  SqlParameterStyle get parameterStyle => SqlParameterStyle.positional;
  @override
  String parameterPlaceholder(String name) => '?';
  @override
  String? columnDefinitionType(String typeString,
          {required bool autoincrement}) =>
      null;
  @override
  String tableExistsQuery() => 'SELECT 1';
}

void main() {
  group('Named dialect rendering', () {
    const d = _NamedDialect();

    test('column-only renders identifier', () {
      final r = d.renderExpression(
        ColumnExpression('email', tableNamespace: 'users'),
      );
      expect(r.sql, 'users.email');
      expect(r.parameters, isEmpty);
      expect(r.positionalParameters, isEmpty);
    });

    test('binary-op renders @-prefixed placeholder + collected param', () {
      final r = d.renderExpression(
        BinaryOpExpression(
          '=',
          ColumnExpression('id', tableNamespace: 't0'),
          ParameterExpression('id_v', 42),
        ),
      );
      expect(r.sql, 't0.id = @id_v');
      expect(r.parameters, {'id_v': 42});
    });

    test('AND combinator wraps children in single set of parens', () {
      final r = d.renderExpression(
        LogicalExpression('AND', [
          BinaryOpExpression(
            '=',
            ColumnExpression('a', tableNamespace: 't0'),
            ParameterExpression('a_v', 1),
          ),
          BinaryOpExpression(
            '=',
            ColumnExpression('b', tableNamespace: 't0'),
            ParameterExpression('b_v', 2),
          ),
        ]),
      );
      expect(r.sql, '(t0.a = @a_v AND t0.b = @b_v)');
      expect(r.parameters, {'a_v': 1, 'b_v': 2});
    });

    test('IS NULL respects dialect operator override', () {
      final r = d.renderExpression(
        IsNullExpression(ColumnExpression('email', tableNamespace: 't0')),
      );
      expect(r.sql, 't0.email IS NULL');
    });

    test('IS NOT NULL via negated', () {
      final r = d.renderExpression(
        IsNullExpression(
          ColumnExpression('email', tableNamespace: 't0'),
          negated: true,
        ),
      );
      expect(r.sql, 't0.email IS NOT NULL');
    });

    test('IN list renders comma-separated placeholders', () {
      final r = d.renderExpression(
        InExpression(
          ColumnExpression('id', tableNamespace: 't0'),
          [
            ParameterExpression('id_0', 1),
            ParameterExpression('id_1', 2),
            ParameterExpression('id_2', 3),
          ],
        ),
      );
      expect(r.sql, 't0.id IN (@id_0,@id_1,@id_2)');
      expect(r.parameters, {'id_0': 1, 'id_1': 2, 'id_2': 3});
    });

    test('NOT IN via negated', () {
      final r = d.renderExpression(
        InExpression(
          ColumnExpression('id', tableNamespace: 't0'),
          [ParameterExpression('id_0', 1)],
          negated: true,
        ),
      );
      expect(r.sql, 't0.id NOT IN (@id_0)');
    });

    test('BETWEEN renders both bounds', () {
      final r = d.renderExpression(
        BetweenExpression(
          ColumnExpression('n', tableNamespace: 't0'),
          ParameterExpression('lo', 1),
          ParameterExpression('hi', 10),
        ),
      );
      expect(r.sql, 't0.n BETWEEN @lo AND @hi');
      expect(r.parameters, {'lo': 1, 'hi': 10});
    });

    test('LIKE case-sensitive uses dialect default', () {
      final r = d.renderExpression(
        LikeExpression(
          ColumnExpression('name', tableNamespace: 't0'),
          ParameterExpression('p', 'al%'),
          caseSensitive: true,
        ),
      );
      expect(r.sql, 't0.name LIKE @p');
    });

    test('NOT LIKE via negated', () {
      final r = d.renderExpression(
        LikeExpression(
          ColumnExpression('name', tableNamespace: 't0'),
          ParameterExpression('p', 'al%'),
          caseSensitive: true,
          negated: true,
        ),
      );
      expect(r.sql, 't0.name NOT LIKE @p');
    });

    test('Parameter name collisions disambiguate with suffix', () {
      // The predicate builders pre-disambiguate so this is rare in
      // practice, but the visitor needs to be defensive — silently
      // dropping the second value would corrupt query results.
      final r = d.renderExpression(
        LogicalExpression('AND', [
          BinaryOpExpression(
            '=',
            ColumnExpression('a'),
            ParameterExpression('p', 1),
          ),
          BinaryOpExpression(
            '=',
            ColumnExpression('b'),
            ParameterExpression('p', 2),
          ),
        ]),
      );
      expect(r.sql, '(a = @p AND b = @p_0)');
      expect(r.parameters, {'p': 1, 'p_0': 2});
    });
  });

  group('Positional dialect rendering', () {
    const d = _PositionalDialect();

    test('comparison emits ? + appends value to positional list', () {
      final r = d.renderExpression(
        BinaryOpExpression(
          '=',
          ColumnExpression('id', tableNamespace: 't0'),
          ParameterExpression('id_v', 42),
        ),
      );
      expect(r.sql, 't0.id = ?');
      expect(r.positionalParameters, [42]);
      expect(r.parameters, isEmpty);
    });

    test('AND with three children appends in left-to-right order', () {
      final r = d.renderExpression(
        LogicalExpression('AND', [
          BinaryOpExpression('=', ColumnExpression('a'),
              ParameterExpression('av', 1)),
          BinaryOpExpression('=', ColumnExpression('b'),
              ParameterExpression('bv', 2)),
          BinaryOpExpression('=', ColumnExpression('c'),
              ParameterExpression('cv', 3)),
        ]),
      );
      expect(r.sql, '(a = ? AND b = ? AND c = ?)');
      expect(r.positionalParameters, [1, 2, 3]);
    });

    test('IN list expands to ?,?,? with values in order', () {
      final r = d.renderExpression(
        InExpression(
          ColumnExpression('id'),
          [
            ParameterExpression('a', 1),
            ParameterExpression('b', 2),
            ParameterExpression('c', 3),
          ],
        ),
      );
      expect(r.sql, 'id IN (?,?,?)');
      expect(r.positionalParameters, [1, 2, 3]);
    });

    test('BETWEEN binds low then high', () {
      final r = d.renderExpression(
        BetweenExpression(
          ColumnExpression('n'),
          ParameterExpression('lo', 5),
          ParameterExpression('hi', 10),
        ),
      );
      expect(r.sql, 'n BETWEEN ? AND ?');
      expect(r.positionalParameters, [5, 10]);
    });

    test('IS NULL uses standard SQL form (no parameter)', () {
      final r = d.renderExpression(
        IsNullExpression(ColumnExpression('email')),
      );
      expect(r.sql, 'email IS NULL');
      expect(r.positionalParameters, isEmpty);
    });

    test('Raw expression rewrites @name placeholders into ? + ordered values', () {
      final r = d.renderExpression(
        RawExpression(
          'a = @x AND b = @y',
          {'x': 100, 'y': 200},
        ),
      );
      expect(r.sql, 'a = ? AND b = ?');
      expect(r.positionalParameters, [100, 200]);
    });
  });

  group('QueryPredicate AST integration', () {
    test('and() preserves AST when no parameter-name collision', () {
      final p1 = QueryPredicate(
        'a = @av',
        {'av': 1},
        BinaryOpExpression(
          '=',
          ColumnExpression('a'),
          ParameterExpression('av', 1),
        ),
      );
      final p2 = QueryPredicate(
        'b = @bv',
        {'bv': 2},
        BinaryOpExpression(
          '=',
          ColumnExpression('b'),
          ParameterExpression('bv', 2),
        ),
      );

      final combined = QueryPredicate.and([p1, p2]);
      expect(combined.expression, isA<LogicalExpression>());
      expect(
        (combined.expression as LogicalExpression).children,
        hasLength(2),
      );
      expect(combined.format, '(a = @av AND b = @bv)');
    });

    test('and() drops AST when parameter names collide', () {
      // The dupe-renaming path rewrites the format string but doesn't
      // touch the AST, so the safe choice is to drop the AST and let
      // the backend fall back to the format-string render.
      final p1 = QueryPredicate(
        'p = @p',
        {'p': 1},
        BinaryOpExpression(
          '=',
          ColumnExpression('p'),
          ParameterExpression('p', 1),
        ),
      );
      final p2 = QueryPredicate(
        'p = @p',
        {'p': 2},
        BinaryOpExpression(
          '=',
          ColumnExpression('p'),
          ParameterExpression('p', 2),
        ),
      );
      final combined = QueryPredicate.and([p1, p2]);
      expect(combined.expression, isNull);
      expect(combined.format, '(p = @p AND p = @p0)');
      expect(combined.parameters, {'p': 1, 'p0': 2});
    });

    test('and() drops AST when any constituent lacks one', () {
      final p1 = QueryPredicate(
        'a = @a',
        {'a': 1},
        BinaryOpExpression(
          '=',
          ColumnExpression('a'),
          ParameterExpression('a', 1),
        ),
      );
      final p2 = QueryPredicate('b = 1'); // no AST attached
      final combined = QueryPredicate.and([p1, p2]);
      expect(combined.expression, isNull);
      expect(combined.format, '(a = @a AND b = 1)');
    });
  });
}
