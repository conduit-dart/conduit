/// Concrete `SqlExpressionVisitor` implementations that render the
/// predicate AST into dialect-specific SQL.
///
/// Two flavors:
///
///   - [NamedSqlExpressionVisitor] — emits `@name` / `:name` style
///     placeholders and a `Map<String, Object?>` parameter
///     accumulator. Used by Postgres and SQLite. Each
///     [ParameterExpression] contributes one map entry; if multiple
///     expressions reference the same parameter name (rare — the
///     builders tend to use prefixed unique names) the visitor
///     suffixes a counter.
///
///   - [PositionalSqlExpressionVisitor] — emits `?` placeholders and
///     a `List<Object?>` parameter accumulator, in left-to-right
///     order of the SQL string. Used by MySQL. Parameter names are
///     ignored at render time but kept in the AST so error messages
///     and traces stay readable.
///
/// Both visitors return a [RenderedExpression] from [render]. The
/// [SqlDialect] base class provides a `render(...)` convenience that
/// constructs the appropriate visitor based on its
/// [SqlDialect.parameterStyle] and walks the AST in one shot.
///
/// Each `visit*` method returns the rendered SQL fragment for its node
/// as a plain `String`; bound values accumulate on the visitor instance
/// and are only surfaced by [render]. Visitors are therefore single-use.
library;

import 'package:conduit_core/src/db/persistent_store/sql_dialect.dart';
import 'package:conduit_core/src/db/query/expression_ast.dart';

/// Visitor base for named-parameter dialects (`@name` for Postgres,
/// `:name` for SQLite). Subclasses override [renderPlaceholder] to
/// produce the dialect-specific prefix.
class NamedSqlExpressionVisitor extends SqlExpressionVisitor<String> {
  NamedSqlExpressionVisitor(this.dialect);

  final SqlDialect dialect;

  /// Accumulated bindings keyed by the parameter name as it appears
  /// in the rendered SQL (without the placeholder prefix).
  final Map<String, Object?> _parameters = {};

  /// Counter for collision suffixes — the predicate builders
  /// already use prefixed unique names, but if the same
  /// `ParameterExpression(name)` shows up twice we disambiguate
  /// rather than silently aliasing the second occurrence to the
  /// first's value.
  int _collisionCounter = 0;

  /// Walk [expr] and produce a fully rendered `(sql, params)` pair.
  RenderedExpression render(SqlExpression expr) {
    final sql = expr.accept(this);
    return RenderedExpression(sql, parameters: Map.of(_parameters));
  }

  @override
  String visitColumn(ColumnExpression node) => node.render();

  @override
  String visitLiteral(LiteralExpression node) => node.sql;

  @override
  String visitParameter(ParameterExpression node) {
    var name = node.name;
    while (_parameters.containsKey(name)) {
      name = '${node.name}_${_collisionCounter++}';
    }
    _parameters[name] = node.value;
    return dialect.parameterPlaceholder(name);
  }

  @override
  String visitBinaryOp(BinaryOpExpression node) {
    final left = node.left.accept(this);
    final right = node.right.accept(this);
    return '$left ${node.op} $right';
  }

  @override
  String visitUnaryOp(UnaryOpExpression node) {
    final operand = node.operand.accept(this);
    return '${node.op} $operand';
  }

  @override
  String visitLogical(LogicalExpression node) {
    final parts = node.children.map((c) => c.accept(this)).toList();
    // Match the legacy PG output format exactly: `(a AND b AND c)`.
    return '(${parts.join(' ${node.op} ')})';
  }

  @override
  String visitIsNull(IsNullExpression node) {
    final operand = node.operand.accept(this);
    final op = node.negated
        ? dialect.isNotNullOperator
        : dialect.isNullOperator;
    return '$operand $op';
  }

  @override
  String visitLike(LikeExpression node) {
    final target = node.target.accept(this);
    final pattern = node.pattern.accept(this);
    var op = node.caseSensitive
        ? dialect.caseSensitiveLikeOperator
        : dialect.caseInsensitiveLikeOperator;
    if (node.negated) {
      op = 'NOT $op';
    }
    return '$target $op $pattern';
  }

  @override
  String visitIn(InExpression node) {
    final target = node.target.accept(this);
    final values = node.values.map((v) => v.accept(this)).join(',');
    final keyword = node.negated ? 'NOT IN' : 'IN';
    return '$target $keyword ($values)';
  }

  @override
  String visitBetween(BetweenExpression node) {
    final target = node.target.accept(this);
    final low = node.low.accept(this);
    final high = node.high.accept(this);
    final op = node.negated ? 'NOT BETWEEN' : 'BETWEEN';
    return '$target $op $low AND $high';
  }

  @override
  String visitRaw(RawExpression node) {
    // Raw fragments are emitted verbatim and their named bindings are
    // merged into the accumulator. The fragment's placeholder syntax
    // must already match the dialect — `RawExpression` exists for
    // backwards compatibility with predicates the framework didn't
    // build itself, and the legacy convention is `@name` (Postgres).
    // SQLite accepts `@name` natively; on MySQL these would have to
    // be rewritten by the positional visitor.
    _parameters.addAll(node.parameters);
    return node.sql;
  }
}

/// Visitor base for positional-parameter dialects (`?` for MySQL).
/// Each [ParameterExpression] appends to [positionalParameters] in
/// SQL-string order; placeholders all render as `?`.
class PositionalSqlExpressionVisitor extends SqlExpressionVisitor<String> {
  PositionalSqlExpressionVisitor(this.dialect);

  final SqlDialect dialect;

  /// Bound values, in the order they appear in the rendered SQL.
  final List<Object?> _positional = [];

  RenderedExpression render(SqlExpression expr) {
    final sql = expr.accept(this);
    return RenderedExpression(sql, positionalParameters: List.of(_positional));
  }

  @override
  String visitColumn(ColumnExpression node) => node.render();

  @override
  String visitLiteral(LiteralExpression node) => node.sql;

  @override
  String visitParameter(ParameterExpression node) {
    _positional.add(node.value);
    return '?';
  }

  @override
  String visitBinaryOp(BinaryOpExpression node) {
    final left = node.left.accept(this);
    final right = node.right.accept(this);
    return '$left ${node.op} $right';
  }

  @override
  String visitUnaryOp(UnaryOpExpression node) {
    final operand = node.operand.accept(this);
    return '${node.op} $operand';
  }

  @override
  String visitLogical(LogicalExpression node) {
    final parts = node.children.map((c) => c.accept(this)).toList();
    return '(${parts.join(' ${node.op} ')})';
  }

  @override
  String visitIsNull(IsNullExpression node) {
    final operand = node.operand.accept(this);
    final op = node.negated
        ? dialect.isNotNullOperator
        : dialect.isNullOperator;
    return '$operand $op';
  }

  @override
  String visitLike(LikeExpression node) {
    final target = node.target.accept(this);
    final pattern = node.pattern.accept(this);
    var op = node.caseSensitive
        ? dialect.caseSensitiveLikeOperator
        : dialect.caseInsensitiveLikeOperator;
    if (node.negated) {
      op = 'NOT $op';
    }
    return '$target $op $pattern';
  }

  @override
  String visitIn(InExpression node) {
    final target = node.target.accept(this);
    final values = node.values.map((v) => v.accept(this)).join(',');
    final keyword = node.negated ? 'NOT IN' : 'IN';
    return '$target $keyword ($values)';
  }

  @override
  String visitBetween(BetweenExpression node) {
    final target = node.target.accept(this);
    final low = node.low.accept(this);
    final high = node.high.accept(this);
    final op = node.negated ? 'NOT BETWEEN' : 'BETWEEN';
    return '$target $op $low AND $high';
  }

  @override
  String visitRaw(RawExpression node) {
    // Rewrite `@name` placeholders in the raw SQL into `?` and append
    // the corresponding values to the positional list, in the order
    // the placeholders appear in the SQL. This is a best-effort
    // bridge — raw expressions are an escape hatch and the framework
    // doesn't generate them for AST-rendered paths.
    var sql = node.sql;
    final pattern = RegExp(r'@(\w+)');
    final matches = pattern.allMatches(sql).toList();
    final buffer = StringBuffer();
    var cursor = 0;
    for (final m in matches) {
      buffer.write(sql.substring(cursor, m.start));
      buffer.write('?');
      _positional.add(node.parameters[m.group(1)]);
      cursor = m.end;
    }
    buffer.write(sql.substring(cursor));
    return buffer.toString();
  }
}
