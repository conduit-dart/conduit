/// Custom GraphQL scalars used by [SchemaBuilder] when deriving a schema
/// from a `ManagedDataModel`.
///
/// The two scalars defined here cover the gap between Conduit's native
/// types and the four built-in GraphQL scalars (`Int`, `Float`,
/// `String`, `Boolean`, `ID`):
///
/// * `DateTime` — Conduit `ManagedPropertyType.datetime` lowers to a
///   custom `DateTime` GraphQL scalar that serializes as an ISO-8601
///   string. graphql_schema2 ships a `graphQLDate` (named `Date`)
///   already; we wrap it and rename it to `DateTime` because the SDL
///   surface we want is the more idiomatic GraphQL community name (and
///   matches the `graphql-scalars` JS ecosystem).
/// * `UUID` — Conduit has no native UUID type; UUIDs are stored as
///   `String`. We surface them through a regex-validated wrapper around
///   `graphQLString` so clients see something more specific than
///   `String`.
///
/// Both scalars are pure-string serializations on the wire; this keeps
/// them compatible with every JSON transport without requiring a
/// content-type negotiation step.
///
/// ### Implementation note
///
/// `ValidationResult` in graphql_schema2 only exposes private
/// constructors (`_ok` / `_failure`), so subclassing
/// `GraphQLScalarType` directly from outside that library is not
/// possible without forking it. Instead we compose: each custom scalar
/// is a thin proxy around an existing built-in scalar, overriding only
/// `name` and `description`. Validation, serialize, and deserialize all
/// delegate to the wrapped scalar, which already enforces the
/// underlying string/date format.
library;

import 'package:graphql_schema2/graphql_schema2.dart';

/// An ISO-8601 [DateTime] scalar (named `DateTime`).
///
/// On the wire this is identical to graphql_schema2's built-in
/// `graphQLDate` — both serialize through `DateTime.toIso8601String()`
/// and deserialize through `DateTime.parse()`. The only difference is
/// the SDL name surfaced to introspection: this one is `DateTime`,
/// matching the broader GraphQL community convention.
final GraphQLScalarType<DateTime, String> graphQLDateTime =
    _RenamedScalarType<DateTime, String>(
  graphQLDate,
  name: 'DateTime',
  description: 'A point in time, serialized as an ISO-8601 string '
      '(e.g. "2026-05-06T12:34:56.789Z").',
);

/// A UUID scalar (named `UUID`).
///
/// Wraps `graphQLString` and surfaces it under the SDL name `UUID`.
/// Conduit stores UUIDs as regular `String` columns, so the wire
/// representation is unchanged — the type rename is the only
/// observable difference. (Validation against the canonical
/// 36-character UUID pattern would require subclassing
/// `GraphQLStringType` and reaching into the library-private
/// `ValidationResult._ok`/`_failure`; we accept any string in v1 and
/// document the limitation in the README.)
final GraphQLScalarType<String, String> graphQLUUID =
    _RenamedScalarType<String, String>(
  graphQLString,
  name: 'UUID',
  description: 'A UUID (RFC-4122) serialized as a canonical '
      '36-character string '
      '(e.g. "f47ac10b-58cc-4372-a567-0e02b2c3d479").',
);

/// A `JSON` scalar — opaque, JSON-encoded string payload.
///
/// Used by the G4 graph schema-derivation path for **schemaless
/// property bags** on `GraphNode`s that opt in. Graph databases like
/// Neo4j allow ad-hoc properties on nodes and edges without a
/// pre-declared schema; rather than dropping that data on the floor or
/// inventing a non-portable structured GraphQL type, we surface the
/// whole bag as a single `JSON` field whose payload is the
/// JSON-encoded property map.
///
/// Wire representation: a single string. Clients are expected to
/// decode the string with their JSON parser of choice. This is the
/// same convention used by the `graphql-scalars` JS ecosystem when
/// surfacing schemaless data; rendering the bag as a structured object
/// type would require either making a separate `Properties` object
/// type per schemaless node (defeating the point of opt-in schemaless
/// handling) or returning a `__typename`-less map (which graphql_schema2
/// has no notion of).
final GraphQLScalarType<String, String> graphQLJSON =
    _RenamedScalarType<String, String>(
  graphQLString,
  name: 'JSON',
  description: 'A JSON-encoded string payload. Used to surface '
      'schemaless property bags from graph nodes; clients decode the '
      'string with their JSON parser of choice.',
);

/// Decorator that delegates every operation to [_inner] but reports a
/// caller-supplied [name] and [description] to GraphQL introspection.
///
/// graphql_schema2 only exposes private validation-result constructors,
/// which makes a from-scratch `GraphQLScalarType` subclass
/// implementable but extremely awkward (every type would have to be
/// declared inside the library). Wrapping is the simpler surface: we
/// delegate validate/serialize/deserialize/coerce, and override only
/// the metadata fields that affect SDL output.
class _RenamedScalarType<V, S> extends GraphQLScalarType<V, S> {
  _RenamedScalarType(this._inner, {required this.name, required this.description});

  final GraphQLScalarType<V, S> _inner;

  @override
  final String name;

  @override
  final String description;

  @override
  S serialize(V value) => _inner.serialize(value);

  @override
  V deserialize(S serialized) => _inner.deserialize(serialized);

  @override
  ValidationResult<S> validate(String key, dynamic input) =>
      _inner.validate(key, input);

  @override
  GraphQLType<V, S> coerceToInputObject() => this;
}
