// Microbenchmarks for `QueryPredicate` construction across the AST
// node kinds the framework's predicate builders emit. Each iteration
// builds a *fresh* predicate from scratch (no shared/cached AST) — the
// cost of the AST construction itself is what we're measuring.
//
// PR #267 introduced an AST + visitor pattern alongside the legacy
// `format` string. Predicates produced by the framework's internal
// builders now populate both forms. The PG path renders the AST back
// to a byte-identical format string, so output is unchanged — but the
// AST construction itself is new work. These benches capture the
// per-shape cost so a regression analysis can A/B against pre-#267.
//
// Run: `dart run bench/predicate_construction_bench.dart`
library;

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:conduit_core/conduit_core.dart';

// ---------------------------------------------------------------------------
// Single equality:  `t0.id = @t0_id`
// ---------------------------------------------------------------------------

class _SingleEqBench extends BenchmarkBase {
  _SingleEqBench() : super('predicate: single eq');

  @override
  void run() {
    final ast = BinaryOpExpression(
      '=',
      ColumnExpression('id', tableNamespace: 't0'),
      ParameterExpression('t0_id', 42),
    );
    QueryPredicate.withExpression(ast, 't0.id = @t0_id', {'t0_id': 42});
  }
}

// ---------------------------------------------------------------------------
// AND chain of N equality predicates combined via `QueryPredicate.and`.
// Mirrors the pattern emitted by the where()-clause builders for
// multi-filter queries: each leaf is a fresh `QueryPredicate.withExpression`,
// and `.and(...)` wraps the children in a `LogicalExpression('AND', ...)`.
// ---------------------------------------------------------------------------

class _AndChainBench extends BenchmarkBase {
  _AndChainBench(this.terms) : super('predicate: $terms-term AND');
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
        't0.c$i = @t0_c${i}_v',
        {'t0_c${i}_v': i},
      ));
    }
    QueryPredicate.and(preds);
  }
}

// ---------------------------------------------------------------------------
// Mixed AND/OR predicate with explicit parens: (a = ? AND (b = ? OR c = ?)).
// ---------------------------------------------------------------------------

class _MixedAndOrBench extends BenchmarkBase {
  _MixedAndOrBench() : super('predicate: mixed AND/OR');

  @override
  void run() {
    final left = BinaryOpExpression(
      '=',
      ColumnExpression('a', tableNamespace: 't0'),
      ParameterExpression('t0_a', 1),
    );
    final right = LogicalExpression('OR', [
      BinaryOpExpression(
        '=',
        ColumnExpression('b', tableNamespace: 't0'),
        ParameterExpression('t0_b', 2),
      ),
      BinaryOpExpression(
        '=',
        ColumnExpression('c', tableNamespace: 't0'),
        ParameterExpression('t0_c', 3),
      ),
    ]);
    final ast = LogicalExpression('AND', [left, right]);
    QueryPredicate.withExpression(
      ast,
      '(t0.a = @t0_a AND (t0.b = @t0_b OR t0.c = @t0_c))',
      {'t0_a': 1, 't0_b': 2, 't0_c': 3},
    );
  }
}

// ---------------------------------------------------------------------------
// IN-list of 20 values. Mirrors `containsPredicate`: 20 fresh
// `ParameterExpression`s laid out under a single `InExpression`.
// ---------------------------------------------------------------------------

class _InListBench extends BenchmarkBase {
  _InListBench(this.size) : super('predicate: IN($size)');
  final int size;

  @override
  void run() {
    final values = <SqlExpression>[];
    final params = <String, Object?>{};
    final tokens = <String>[];
    for (var i = 0; i < size; i++) {
      final name = 't0_id_${i}_';
      values.add(ParameterExpression(name, i));
      params[name] = i;
      tokens.add('@$name');
    }
    final ast = InExpression(
      ColumnExpression('id', tableNamespace: 't0'),
      values,
    );
    QueryPredicate.withExpression(
      ast,
      't0.id IN (${tokens.join(",")})',
      params,
    );
  }
}

void main() {
  _SingleEqBench().report();
  _AndChainBench(5).report();
  _AndChainBench(10).report();
  _MixedAndOrBench().report();
  _InListBench(20).report();
}
