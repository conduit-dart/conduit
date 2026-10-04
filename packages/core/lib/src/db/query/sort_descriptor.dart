import 'package:conduit_core/src/db/query/query.dart';

/// The order in which a collection of objects should be sorted when returned from a database.
///
/// See [Query.sortBy] and [Query.pageBy] for more details.
class QuerySortDescriptor(
  /// The name of a property to sort by.
  var String key,

  /// The order in which values should be sorted.
  ///
  /// See [QuerySortOrder] for possible values.
  var QuerySortOrder order,
);
