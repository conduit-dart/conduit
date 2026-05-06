import '../errors/graph_exception.dart';

/// Comparison operators that a where-clause filter can express.
///
/// Backends translate these to their native query language; the DSL
/// itself is dialect-agnostic.
enum GraphFilterOperator {
  equal,
  notEqual,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  contains, // string contains / array contains, backend-defined
  startsWith,
  endsWith,
  inList,
  isNull,
  isNotNull,
}

/// Logical connector for compound filter expressions.
enum GraphFilterCombinator { and, or }

/// A structured filter expression — the AST the where-clause closure
/// compiles to.
///
/// This is **not** a string. The query DSL refuses to lower to a SQL
/// `QueryPredicate.format` — it emits a tree that backends render in
/// their own dialect (Cypher, openCypher, Gremlin, …).
sealed class GraphFilterExpression {
  const GraphFilterExpression();

  /// Combine this expression with [other] using AND.
  GraphFilterExpression and(GraphFilterExpression other) =>
      GraphCompoundFilter(GraphFilterCombinator.and, [this, other]);

  /// Combine this expression with [other] using OR.
  GraphFilterExpression or(GraphFilterExpression other) =>
      GraphCompoundFilter(GraphFilterCombinator.or, [this, other]);
}

/// A leaf filter: `<property> <op> <value?>`.
final class GraphPropertyFilter extends GraphFilterExpression {
  const GraphPropertyFilter({
    required this.property,
    required this.operator,
    this.value,
  });

  final String property;
  final GraphFilterOperator operator;
  final Object? value;

  @override
  String toString() => 'GraphPropertyFilter($property ${operator.name} $value)';
}

/// A compound expression — n-ary AND or OR.
final class GraphCompoundFilter extends GraphFilterExpression {
  GraphCompoundFilter(this.combinator, List<GraphFilterExpression> children)
      : children = List.unmodifiable(children) {
    if (children.isEmpty) {
      throw GraphInvalidQuery(
        'compound filter must have at least one child',
      );
    }
  }

  final GraphFilterCombinator combinator;
  final List<GraphFilterExpression> children;

  @override
  String toString() => 'GraphCompoundFilter(${combinator.name}, $children)';
}

/// A logical NOT.
final class GraphNotFilter extends GraphFilterExpression {
  const GraphNotFilter(this.child);

  final GraphFilterExpression child;

  @override
  String toString() => 'GraphNotFilter($child)';
}

/// Helper for the closure-built where-clause.
///
/// User code calls bare property accessors via [GraphWhereProxy]; the
/// proxy returns [GraphFilterTerm] objects whose comparison operators
/// are overloaded to record [GraphPropertyFilter] expressions instead
/// of evaluating against runtime values.
///
/// (This mirrors the proxy-based predicate building in conduit core's
/// `Query<T>.where` — structurally borrowed, graph-shaped output.)
class GraphFilterTerm {
  GraphFilterTerm(this._property);

  final String _property;

  GraphFilterExpression equalTo(Object? value) => GraphPropertyFilter(
        property: _property,
        operator: GraphFilterOperator.equal,
        value: value,
      );

  GraphFilterExpression notEqualTo(Object? value) => GraphPropertyFilter(
        property: _property,
        operator: GraphFilterOperator.notEqual,
        value: value,
      );

  GraphFilterExpression greaterThan(Object value) => GraphPropertyFilter(
        property: _property,
        operator: GraphFilterOperator.greaterThan,
        value: value,
      );

  GraphFilterExpression greaterThanOrEqualTo(Object value) =>
      GraphPropertyFilter(
        property: _property,
        operator: GraphFilterOperator.greaterThanOrEqual,
        value: value,
      );

  GraphFilterExpression lessThan(Object value) => GraphPropertyFilter(
        property: _property,
        operator: GraphFilterOperator.lessThan,
        value: value,
      );

  GraphFilterExpression lessThanOrEqualTo(Object value) =>
      GraphPropertyFilter(
        property: _property,
        operator: GraphFilterOperator.lessThanOrEqual,
        value: value,
      );

  GraphFilterExpression contains(Object value) => GraphPropertyFilter(
        property: _property,
        operator: GraphFilterOperator.contains,
        value: value,
      );

  GraphFilterExpression startsWith(String value) => GraphPropertyFilter(
        property: _property,
        operator: GraphFilterOperator.startsWith,
        value: value,
      );

  GraphFilterExpression endsWith(String value) => GraphPropertyFilter(
        property: _property,
        operator: GraphFilterOperator.endsWith,
        value: value,
      );

  GraphFilterExpression isIn(List<Object?> values) => GraphPropertyFilter(
        property: _property,
        operator: GraphFilterOperator.inList,
        value: List<Object?>.unmodifiable(values),
      );

  GraphFilterExpression get isNull => GraphPropertyFilter(
        property: _property,
        operator: GraphFilterOperator.isNull,
      );

  GraphFilterExpression get isNotNull => GraphPropertyFilter(
        property: _property,
        operator: GraphFilterOperator.isNotNull,
      );
}

/// The proxy passed to a `where` closure. Property accesses return
/// [GraphFilterTerm] objects.
class GraphWhereProxy {
  GraphWhereProxy();

  /// Look up a property as a filter term.
  ///
  /// Use either `proxy['age']` or `proxy.property('age')` — the second
  /// reads better in builder chains.
  GraphFilterTerm operator [](String property) => GraphFilterTerm(property);

  GraphFilterTerm property(String name) => GraphFilterTerm(name);
}
