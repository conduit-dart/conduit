// End-to-end microbenchmark: from per-column predicate construction
// through `QueryPredicate.and` combination to dialect-aware AST
// rendering. Stops short of executing against a database.
//
// This is the closest a microbenchmark can get to a real
// `Query<T>.where(...)` build cycle without standing up a full
// `ManagedContext` + schema. The work measured is the path that PR
// #267's AST migration touches:
//
//   1. Build N leaf `QueryPredicate` objects (each with an attached
//      `BinaryOpExpression` — the typical eq predicate emitted by
//      `ColumnExpressionBuilder.comparisonPredicate`).
//   2. Combine via `QueryPredicate.and`, which wraps the leaves in a
//      `LogicalExpression('AND', ...)` (see `predicate.dart`).
//   3. Render the combined AST to dialect SQL via the visitor.
//
// Run: `dart run bench/query_e2e_bench.dart`
library;

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:conduit_core/conduit_core.dart';

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

class _QueryE2EBench extends BenchmarkBase {
  _QueryE2EBench(this.dialect, this.terms, String label) : super(label);
  final SqlDialect dialect;
  final int terms;

  @override
  void run() {
    final preds = <QueryPredicate>[];
    for (var i = 0; i < terms; i++) {
      final ast = BinaryOpExpression(
        '=',
        ColumnExpression('c$i', tableNamespace: 't0'),
        ParameterExpression('t0_c${i}_v', i),
      );
      preds.add(QueryPredicate.withExpression(
        ast,
        't0.c$i = ${dialect.parameterPlaceholder("t0_c${i}_v")}',
        {'t0_c${i}_v': i},
      ));
    }
    final combined = QueryPredicate.and(preds);
    final expr = combined.expression;
    if (expr != null) {
      dialect.renderExpression(expr);
    }
  }
}

void main() {
  const named = _NamedDialect();
  const positional = _PositionalDialect();

  _QueryE2EBench(named, 5, 'query e2e: 5-term where() (named)').report();
  _QueryE2EBench(named, 10, 'query e2e: 10-term where() (named)').report();
  _QueryE2EBench(positional, 5,
          'query e2e: 5-term where() (positional)')
      .report();
  _QueryE2EBench(positional, 10,
          'query e2e: 10-term where() (positional)')
      .report();
}
