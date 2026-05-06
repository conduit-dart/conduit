/// Base class for all conduit_graph exceptions.
///
/// Deliberately *not* a subclass of conduit core's `QueryException` —
/// graph errors live in a parallel domain and tunneling them through
/// the SQL exception type would force callers to catch errors that
/// don't apply.
sealed class GraphException implements Exception {
  GraphException(this.message, {this.cause});

  /// A short human-readable description of what went wrong.
  final String message;

  /// The underlying cause, if this exception wraps another. Common
  /// when adapting a backend driver's error.
  final Object? cause;

  @override
  String toString() {
    final c = cause == null ? '' : ' (cause: $cause)';
    return '$runtimeType: $message$c';
  }
}

/// Connectivity / handshake / transport-level failure talking to the
/// graph backend.
final class GraphConnectionError extends GraphException {
  GraphConnectionError(super.message, {super.cause});
}

/// A backend-level constraint was violated (uniqueness, required-key,
/// etc). Note that conduit_graph itself does not enforce a schema —
/// this is reserved for backends that do.
final class GraphConstraintViolation extends GraphException {
  GraphConstraintViolation(super.message, {super.cause});
}

/// A node, edge, or relationship endpoint referenced by a query was
/// not found.
final class GraphNotFoundError extends GraphException {
  GraphNotFoundError(super.message, {super.cause});
}

/// The query was malformed or referenced a node/edge type that the
/// context does not know about.
final class GraphInvalidQuery extends GraphException {
  GraphInvalidQuery(super.message, {super.cause});
}
