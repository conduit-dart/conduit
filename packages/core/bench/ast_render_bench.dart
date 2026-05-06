// Microbenchmarks for rendering an *already-built* `SqlExpression` AST
// to dialect SQL via `SqlExpressionVisitor`. PR #267 introduced the
// visitor pattern so a single AST can render to either named-parameter
// (`@name` / `:name`) or positional-parameter (`?`) dialects without
// the predicate builders having to know which.
//
// AST construction is excluded from each iteration's `run()` body —
// the AST is built once in setup and reused. What's measured here is
// pure traversal + string allocation cost.
//
// Run: `dart run bench/ast_render_bench.dart`
library;

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:conduit_core/conduit_core.dart';

// Stand-alone dialects — same pattern as `expression_ast_test.dart`.
// We don't import a concrete backend dialect here because (a) those
// pull driver-typed values into the AST, and (b) the visitor's traversal
// is the contract we're measuring, not the dialect's per-operator
// overrides.

class _NamedDialect extends SqlDialect {
  const _NamedDialect();
  @override
  String get name => 'named-bench';
  @override
  String? columnDefinitionType(String typeString,
          {required bool autoincrement}) =>
      null;
  @override
  String tableExistsQuery() => 'SELECT 1';
}

class _PositionalDialect extends SqlDialect {
  const _PositionalDialect();
  @override
  String get name => 'positional-bench';
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

SqlExpression _buildAndChain(int terms) {
  final children = <SqlExpression>[];
  for (var i = 0; i < terms; i++) {
    children.add(BinaryOpExpression(
      '=',
      ColumnExpression('c$i', tableNamespace: 't0'),
      ParameterExpression('t0_c${i}_v', i),
    ));
  }
  return LogicalExpression('AND', children);
}

class _RenderBench extends BenchmarkBase {
  _RenderBench(this.dialect, this.expr, String label) : super(label);
  final SqlDialect dialect;
  final SqlExpression expr;

  @override
  void run() {
    dialect.renderExpression(expr);
  }
}

void main() {
  const named = _NamedDialect();
  const positional = _PositionalDialect();

  final and5 = _buildAndChain(5);
  final and10 = _buildAndChain(10);

  _RenderBench(named, and5, 'ast render: 5-term AND (named)').report();
  _RenderBench(named, and10, 'ast render: 10-term AND (named)').report();
  _RenderBench(positional, and5,
          'ast render: 5-term AND (positional)')
      .report();
  _RenderBench(positional, and10,
          'ast render: 10-term AND (positional)')
      .report();
}
