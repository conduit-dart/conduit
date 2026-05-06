/// AST nodes for SQL `WHERE` predicate expressions.
///
/// Historically Conduit's `QueryPredicate` carried a raw SQL fragment
/// with hardcoded `@name`-style placeholders (the Postgres convention).
/// That worked while Postgres was the only backend, but it bakes a
/// placeholder-syntax assumption into every predicate built by the
/// framework — which breaks the moment a backend uses positional `?`
/// placeholders (MySQL) or a different `:name` convention (SQLite).
///
/// To support multiple dialects, predicate construction now produces a
/// dialect-neutral AST out of these node types. A per-dialect visitor
/// (see `SqlExpressionVisitor`) walks the AST and emits the
/// dialect-correct SQL string + parameter binding (named map for
/// Postgres/SQLite, positional list for MySQL).
///
/// Backwards compatibility: `QueryPredicate` still exposes a raw
/// `format` String and named-parameter Map (the historical surface).
/// When predicates are built from an AST, the framework attaches the
/// AST to the predicate as well; dialects that recognize it can render
/// from the AST. Predicates supplied as raw format strings (e.g. by
/// downstream user code via `QueryPredicate(formatString, params)`)
/// continue to flow through the legacy path.
///
/// Each node is immutable, cheap to construct, and trivially
/// serializable (no driver-specific value wrappers — the dialect's
/// visitor injects driver-specific value coercion when it walks the
/// tree).
library;

import 'package:conduit_core/src/db/query/predicate.dart';

/// Base class for every node in the predicate AST.
///
/// Sealed in spirit (Dart sealed classes ship in 3.0+ and the
/// framework already targets 3.12+), but we use `abstract` here to
/// keep the visitor open for downstream extensions that may want to
/// add custom expression types without forking the framework. The
/// visitor exposes a fallback hook for unknown node kinds.
abstract class SqlExpression {
  const SqlExpression();

  /// Dispatch to a visitor. Concrete subclasses call the visitor's
  /// matching `visitX` method.
  T accept<T>(SqlExpressionVisitor<T> visitor);
}

/// A reference to a column by name. Optionally namespaced by table
/// (the dialect's visitor decides whether to include the namespace
/// based on context — e.g., when a `JOIN` is present).
class ColumnExpression extends SqlExpression {
  const ColumnExpression(this.columnName, {this.tableNamespace});

  final String columnName;
  final String? tableNamespace;

  /// Returns the `<table>.<column>` form when [tableNamespace] is set,
  /// otherwise just `<column>`. Convenience for visitors that always
  /// emit qualified names.
  String render() =>
      tableNamespace == null ? columnName : '$tableNamespace.$columnName';

  @override
  T accept<T>(SqlExpressionVisitor<T> visitor) =>
      visitor.visitColumn(this);
}

/// A literal SQL token. Only a small number of safe constants are
/// emitted via this node (e.g., the numeric literal bounds for
/// page-cursor predicates) — any user-supplied value goes through
/// [ParameterExpression] instead so the dialect can bind it safely.
class LiteralExpression extends SqlExpression {
  const LiteralExpression(this.sql);

  final String sql;

  @override
  T accept<T>(SqlExpressionVisitor<T> visitor) =>
      visitor.visitLiteral(this);
}

/// A bind-parameter slot. The visitor renders this as a
/// dialect-correct placeholder (`@name` for Postgres, `:name` for
/// SQLite, `?` for MySQL) and records the bound value in its
/// accumulating parameter list/map.
class ParameterExpression extends SqlExpression {
  const ParameterExpression(this.name, this.value);

  /// Suggested name for the parameter. Used directly as the binding
  /// key for named-parameter dialects; ignored for positional-only
  /// dialects (MySQL) but kept for tracing / error messages.
  final String name;

  /// The bound value. May be a raw Dart value, or a driver-typed
  /// wrapper (e.g., postgres `TypedValue`) — the visitor passes it
  /// through to the underlying parameter container without
  /// inspecting it.
  final Object? value;

  @override
  T accept<T>(SqlExpressionVisitor<T> visitor) =>
      visitor.visitParameter(this);
}

/// Binary infix expression: `<left> <op> <right>`.
///
/// `op` is the rendered SQL operator literally — `=`, `<>`, `<`, `>`,
/// `<=`, `>=`, `!=`. Pattern-match operators (`LIKE`, `ILIKE`) live
/// on [LikeExpression] so the dialect can swap operator + escape
/// behavior in one place.
class BinaryOpExpression extends SqlExpression {
  const BinaryOpExpression(this.op, this.left, this.right);

  final String op;
  final SqlExpression left;
  final SqlExpression right;

  @override
  T accept<T>(SqlExpressionVisitor<T> visitor) =>
      visitor.visitBinaryOp(this);
}

/// Unary prefix expression: `<op> <operand>`. Currently used only for
/// `NOT`; included as a node kind so backends can extend it without
/// adding a new visitor method.
class UnaryOpExpression extends SqlExpression {
  const UnaryOpExpression(this.op, this.operand);

  final String op;
  final SqlExpression operand;

  @override
  T accept<T>(SqlExpressionVisitor<T> visitor) =>
      visitor.visitUnaryOp(this);
}

/// Logical combinator: AND / OR over an arbitrary number of children.
///
/// Distinct from [BinaryOpExpression] because logical operators have
/// associativity / parenthesization rules that vary across dialects
/// (Postgres tolerates redundant parens; SQLite and MySQL do too —
/// but the visitor still emits explicit parens so it stays correct
/// when a future dialect doesn't).
class LogicalExpression extends SqlExpression {
  const LogicalExpression(this.op, this.children);

  /// One of `AND` / `OR`. Stored as the literal SQL token so dialects
  /// don't have to translate.
  final String op;
  final List<SqlExpression> children;

  @override
  T accept<T>(SqlExpressionVisitor<T> visitor) =>
      visitor.visitLogical(this);
}

/// Null-check expression: `<operand> IS NULL` or `<operand> IS NOT NULL`.
///
/// Exposed as a node kind (rather than a `BinaryOpExpression` against
/// a `NULL` literal) because the spelling varies — Postgres
/// historically accepts `ISNULL`/`NOTNULL` shorthand; standard SQL
/// uses `IS NULL`/`IS NOT NULL`. Dialect's visitor reads
/// [SqlDialect.isNullOperator] / [SqlDialect.isNotNullOperator].
class IsNullExpression extends SqlExpression {
  const IsNullExpression(this.operand, {this.negated = false});

  final SqlExpression operand;
  final bool negated;

  @override
  T accept<T>(SqlExpressionVisitor<T> visitor) =>
      visitor.visitIsNull(this);
}

/// Pattern-match expression: `<target> LIKE <pattern>` (case-sensitive)
/// or its case-insensitive sibling. The dialect chooses the operator
/// (`LIKE` / `ILIKE` / `LIKE BINARY`) and applies escape rules to
/// `pattern` if needed.
class LikeExpression extends SqlExpression {
  const LikeExpression(
    this.target,
    this.pattern, {
    required this.caseSensitive,
    this.negated = false,
  });

  final SqlExpression target;

  /// Should already be a [ParameterExpression] (or [LiteralExpression]
  /// for very specific tests). Wildcard escaping is the caller's
  /// responsibility — done before the AST is built.
  final SqlExpression pattern;
  final bool caseSensitive;
  final bool negated;

  @override
  T accept<T>(SqlExpressionVisitor<T> visitor) =>
      visitor.visitLike(this);
}

/// Set-membership expression: `<target> IN (<v1>, <v2>, ...)` or
/// `NOT IN`.
///
/// Subqueries are not represented today — Conduit's predicate builders
/// only emit `IN (literals)`. If/when a backend grows subquery support
/// the node can be extended with an alternate `subquery` field; the
/// visitor signature is already flexible enough.
class InExpression extends SqlExpression {
  const InExpression(this.target, this.values, {this.negated = false});

  final SqlExpression target;
  final List<SqlExpression> values;
  final bool negated;

  @override
  T accept<T>(SqlExpressionVisitor<T> visitor) =>
      visitor.visitIn(this);
}

/// Range expression: `<target> BETWEEN <low> AND <high>` or `NOT BETWEEN`.
///
/// Modeled as its own node (rather than `(target >= low AND target <=
/// high)`) because (a) `BETWEEN` is shorter and matches the existing
/// PG output byte-for-byte, and (b) some dialects optimize it
/// independently of the equivalent compound predicate.
class BetweenExpression extends SqlExpression {
  const BetweenExpression(
    this.target,
    this.low,
    this.high, {
    this.negated = false,
  });

  final SqlExpression target;
  final SqlExpression low;
  final SqlExpression high;
  final bool negated;

  @override
  T accept<T>(SqlExpressionVisitor<T> visitor) =>
      visitor.visitBetween(this);
}

/// Escape hatch — emit a raw SQL fragment with named-parameter
/// bindings. Used to bridge predicates that downstream user code
/// constructed via the legacy `QueryPredicate(format, parameters)`
/// constructor. The visitor renders the fragment verbatim under
/// named-parameter dialects, and rewrites named placeholders to
/// positional ones under positional-parameter dialects.
class RawExpression extends SqlExpression {
  const RawExpression(this.sql, [this.parameters = const {}]);

  final String sql;
  final Map<String, Object?> parameters;

  @override
  T accept<T>(SqlExpressionVisitor<T> visitor) =>
      visitor.visitRaw(this);
}

/// Visitor pattern entry point for predicate AST traversal.
///
/// Concrete dialects implement this to render the AST into a
/// dialect-correct `(sql, params)` pair. The shape of `params`
/// depends on the dialect — named dialects use a `Map<String,
/// Object?>` accumulator, positional dialects use a
/// `List<Object?>`. The visitor's `T` lets callers chain or compose
/// without committing to a single shape.
abstract class SqlExpressionVisitor<T> {
  T visitColumn(ColumnExpression node);
  T visitLiteral(LiteralExpression node);
  T visitParameter(ParameterExpression node);
  T visitBinaryOp(BinaryOpExpression node);
  T visitUnaryOp(UnaryOpExpression node);
  T visitLogical(LogicalExpression node);
  T visitIsNull(IsNullExpression node);
  T visitLike(LikeExpression node);
  T visitIn(InExpression node);
  T visitBetween(BetweenExpression node);
  T visitRaw(RawExpression node);
}

/// The output of a render pass: a SQL fragment (the predicate body —
/// what would go after `WHERE`) plus the parameter binding shape the
/// dialect prefers.
///
/// For named dialects (Postgres, SQLite), `parameters` is a
/// `Map<String, Object?>` and `positionalParameters` is empty. For
/// positional dialects (MySQL), `parameters` is empty and
/// `positionalParameters` is the ordered list of bound values.
///
/// This is intentionally a value class without machinery — callers
/// pass it straight to their persistent store's execute path.
class RenderedExpression {
  const RenderedExpression(this.sql, {
    this.parameters = const {},
    this.positionalParameters = const [],
  });

  final String sql;
  final Map<String, Object?> parameters;
  final List<Object?> positionalParameters;

  /// Convert a [RenderedExpression] back into a legacy [QueryPredicate]
  /// for back-compat with the existing `sqlWhereClause`, `sqlJoin`,
  /// and friends. Named dialects round-trip cleanly; positional
  /// dialects emit a predicate whose `parameters` map keys are
  /// `'?0', '?1', ...` (just so the map shape is preserved — call
  /// sites that need positional binding read [positionalParameters]
  /// directly).
  QueryPredicate toQueryPredicate() {
    if (positionalParameters.isEmpty) {
      return QueryPredicate(sql, Map.of(parameters));
    }
    final fakeMap = <String, Object?>{};
    for (var i = 0; i < positionalParameters.length; i++) {
      fakeMap['?$i'] = positionalParameters[i];
    }
    return QueryPredicate(sql, fakeMap);
  }
}
