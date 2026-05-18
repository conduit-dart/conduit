import '../errors/graph_exception.dart';
import '../types/graph_node.dart';
import 'graph_filter.dart';
import 'graph_pattern.dart';

/// Sort direction for `orderBy`.
enum GraphSortDirection { ascending, descending }

/// A single ordering term: property + direction.
class GraphOrderBy {
  const GraphOrderBy(this.property, this.direction);

  final String property;
  final GraphSortDirection direction;

  @override
  String toString() => 'GraphOrderBy($property ${direction.name})';
}

/// Forward declaration of the executor a [GraphQuery] runs against.
///
/// Defined as a typedef rather than a direct import of
/// [GraphPersistentStore] so this file does not have to depend on the
/// store layer — the store layer already depends on this file. The
/// real signature lines up with [GraphPersistentStore.executeQuery].
typedef GraphQueryExecutor = Future<List<N>>
    Function<N extends GraphNode<N>>(GraphQuery<N> query);

/// A chainable, dialect-agnostic graph query.
///
/// Wraps a [GraphPattern] with optional `where`, `orderBy`, `limit`,
/// and `offset`. **Does not** lower to a `QueryPredicate.format`
/// string — the where-clause closure compiles to a structured
/// [GraphFilterExpression] that backends render in their native query
/// language.
///
/// ```dart
/// final q = context.graph.match<User>(
///   (u) => u.connectedTo<Friend>(),
/// ).where((u) => u['age'].greaterThan(21));
///
/// final adults = await q.fetch();
/// ```
class GraphQuery<N extends GraphNode<N>> {
  GraphQuery({required this.pattern, this.executor});

  final GraphPattern<N> pattern;

  /// The store-supplied executor that runs this query. `null` for
  /// detached queries — calling [fetch] then throws
  /// [GraphInvalidQuery]. Backends and tests can wire in their own
  /// executor when constructing a [GraphQuery] directly.
  final GraphQueryExecutor? executor;

  GraphFilterExpression? _filter;
  int? _limit;
  int? _offset;
  final List<GraphOrderBy> _orderBy = [];

  /// The compiled where-clause, or `null` if none has been set.
  GraphFilterExpression? get filter => _filter;

  int? get limit => _limit;
  int? get offset => _offset;
  List<GraphOrderBy> get orderBy => List.unmodifiable(_orderBy);

  /// Apply [predicate] as the where-clause.
  ///
  /// The closure receives a [GraphWhereProxy]; properties are accessed
  /// by name and comparison operators record [GraphFilterExpression]
  /// nodes instead of evaluating against runtime values:
  ///
  /// ```dart
  /// q.where((u) => u['age'].greaterThan(21).and(u['name'].equalTo('alice')));
  /// ```
  ///
  /// Calling `where` twice ANDs the new predicate onto the existing
  /// one — convenient for composable builders.
  GraphQuery<N> where(
    GraphFilterExpression Function(GraphWhereProxy proxy) predicate,
  ) {
    final next = predicate(GraphWhereProxy());
    _filter = _filter == null ? next : _filter!.and(next);
    return this;
  }

  /// Cap the result set at [count] rows. Throws [GraphInvalidQuery] if
  /// [count] is negative.
  GraphQuery<N> limitTo(int count) {
    if (count < 0) {
      throw GraphInvalidQuery('limit must be non-negative, got $count');
    }
    _limit = count;
    return this;
  }

  /// Skip [count] rows. Throws [GraphInvalidQuery] if [count] is
  /// negative.
  GraphQuery<N> offsetBy(int count) {
    if (count < 0) {
      throw GraphInvalidQuery('offset must be non-negative, got $count');
    }
    _offset = count;
    return this;
  }

  /// Append an ordering term.
  GraphQuery<N> orderByProperty(
    String property, {
    GraphSortDirection direction = GraphSortDirection.ascending,
  }) {
    _orderBy.add(GraphOrderBy(property, direction));
    return this;
  }

  /// Execute the query and return all matching nodes.
  Future<List<N>> fetch() {
    final exec = executor;
    if (exec == null) {
      throw GraphInvalidQuery(
        'GraphQuery is detached — no executor was provided. '
        'Build it through GraphContext.graph.match() to get a runnable query.',
      );
    }
    return exec<N>(this);
  }

  /// Execute the query and return the first match, or `null` if there
  /// were none.
  Future<N?> fetchOne() async {
    final capped = limit ?? 1;
    final rows = await (this..limitTo(capped < 1 ? 1 : capped)).fetch();
    return rows.isEmpty ? null : rows.first;
  }
}
