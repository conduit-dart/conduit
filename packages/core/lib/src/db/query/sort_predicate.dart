import 'package:conduit_core/src/db/query/query.dart';

/// The order in which a collection of objects should be sorted when returned from a database.
class QuerySortPredicate {
  QuerySortPredicate(
    this.predicate,
    this.order,
  );

  /// The name of a property to sort by.
  String predicate;

  /// The order in which values should be sorted.
  ///
  /// See [QuerySortOrder] for possible values.
  QuerySortOrder order;
}
