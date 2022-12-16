import 'package:conduit_core/src/http/serializable.dart';

/// An exception thrown when an ORM property validator is violated.
///
/// Behaves the same as [SerializableException].
class ValidationException extends SerializableException {
  ValidationException(super.errors);
}
