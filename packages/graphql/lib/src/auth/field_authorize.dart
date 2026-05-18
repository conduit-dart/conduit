/// Field-level authorization for the GraphQL transport.
///
/// G5 introduces [FieldAuthorize], an annotation that marks a single
/// resolver-eligible property — either a `ManagedObject` attribute /
/// relationship on the SQL side, or a graph-side property whose
/// metadata is supplied through [GraphSchemaConfig] — as requiring an
/// OAuth scope before the field is resolved.
///
/// [FieldAuthPolicy] is the runtime lookup table the resolver-wrapping
/// machinery consults during execution. Apps build a policy once at
/// schema-build time and hand it to [PersistenceResolverFactory.hooks].
///
/// ### Why a separate policy lookup
///
/// Conduit's `ManagedAttributeDescription` does not preserve arbitrary
/// annotations through the data-model build (see
/// `packages/core/lib/src/db/managed/property_description.dart` — only
/// `Validate`, `ResponseModel`, and `ResponseKey` are first-class).
/// Reflecting back at runtime against the declaring class would require
/// `dart:mirrors`, which is being deprecated.
///
/// The user-facing answer: keep [FieldAuthorize] as a documentation
/// annotation that an app may attach to its `ManagedObject` properties
/// for human reviewers, AND build a [FieldAuthPolicy] at startup that
/// maps the same `(entity, field)` keys to the same policy values.
/// G5 wires only the policy at execution time. A future phase can add
/// a build-time transformer that scrapes the annotation off the source
/// and emits the policy automatically; that transformer is explicitly
/// out of scope here so the G5 surface stays pure-Dart and deploy-safe.
///
/// On the graph side the asymmetry is smaller: `GraphNode` does not
/// support per-property annotations either, and graph property metadata
/// already lives in [GraphSchemaConfig]. G5's
/// [GraphPropertyDescriptor] gains an `auth` field so graph-side auth
/// declarations live alongside the rest of the property declaration.
library;

import 'package:conduit_core/conduit_core.dart';

/// Annotation marking a property as requiring one or more OAuth scopes
/// before its resolver may run.
///
/// Attach to a `ManagedObject` property (or pass the same instance into
/// a [GraphPropertyDescriptor]'s `auth:` slot) and add a matching entry
/// to [FieldAuthPolicy] so the runtime can look it up.
///
/// ```dart
/// class _User {
///   @primaryKey
///   int? id;
///
///   @Column(unique: true)
///   String? email;
///
///   /// Only callers with `pii:read` may see the SSN.
///   @FieldAuthorize(scopes: ['pii:read'])
///   @Column(nullable: true)
///   String? ssn;
/// }
/// ```
///
/// Scope semantics: the caller must hold **at least one** of the listed
/// scopes (any-of). To require all-of, list them in [scopes] only once
/// each and use the auth backend's scope-subset rules to express
/// composite scopes (e.g. `pii:read.full` implying `pii:read`).
///
/// If [allowOwner] is supplied, it short-circuits the scope check: when
/// `allowOwner(parent, request)` returns `true`, the field resolves
/// regardless of scope. The closure runs only when scopes do not
/// authorize the request, so it never adds latency for fully-scoped
/// callers.
class FieldAuthorize {
  /// Creates a field-auth declaration.
  const FieldAuthorize({this.scopes = const [], this.allowOwner});

  /// OAuth scopes accepted on this field, any-of semantics.
  final List<String> scopes;

  /// Optional callback. When non-null and scopes do not authorize, the
  /// callback is invoked with the parent value (typically a
  /// `ManagedObject` or `GraphNode`) and the conduit [Request]; a
  /// `true` return bypasses the scope check.
  final bool Function(Object parent, Request request)? allowOwner;
}

/// Runtime lookup for [FieldAuthorize] declarations.
///
/// The resolver-wrapping machinery consults this policy at execution
/// time to determine whether to allow a resolver to run. Build it once
/// at startup (typically in `ApplicationChannel.prepare`) and pass it
/// to [PersistenceResolverFactory.hooks].
abstract class FieldAuthPolicy {
  /// Returns the [FieldAuthorize] declaration for [property], or
  /// `null` if the field is unauthenticated (the default).
  ///
  /// [property] is the descriptor the resolver factory has in hand at
  /// schema-build time:
  ///
  /// * On the SQL side this is a [ManagedAttributeDescription] or
  ///   [ManagedRelationshipDescription].
  /// * On the graph side this is a [GraphPropertyAuthKey] — a
  ///   `(nodeOrEdgeType, propertyName)` pair the schema builder
  ///   produces from the [GraphSchemaConfig] entries.
  FieldAuthorize? authFor(Object property);
}

/// Composite key the graph side passes into [FieldAuthPolicy.authFor].
///
/// Symmetric with the relational side, where the property descriptor
/// is itself a unique handle. On the graph side we have no such object,
/// so we synthesize one — the type and the property name together are
/// unique within a single [GraphSchemaConfig].
class GraphPropertyAuthKey {
  const GraphPropertyAuthKey(this.declaringType, this.propertyName);

  /// Either a `GraphNode` or `GraphEdge` Dart [Type].
  final Type declaringType;

  /// Property name as declared in the [GraphSchemaConfig] entry.
  final String propertyName;

  @override
  bool operator ==(Object other) =>
      other is GraphPropertyAuthKey &&
      other.declaringType == declaringType &&
      other.propertyName == propertyName;

  @override
  int get hashCode => Object.hash(declaringType, propertyName);

  @override
  String toString() => 'GraphPropertyAuthKey($declaringType.$propertyName)';
}

/// In-memory [FieldAuthPolicy] backed by a [Map] of explicit entries.
///
/// Convenience factory: declare every authorized field at one call site
/// and the policy reads through it at execution time. Apps that want
/// more dynamic behavior subclass [FieldAuthPolicy] directly.
class MapFieldAuthPolicy implements FieldAuthPolicy {
  /// Builds a policy from a flat [Map] of property descriptor → auth
  /// declaration. The keys are the same descriptors the resolver
  /// factories surface — pass [ManagedAttributeDescription] /
  /// [ManagedRelationshipDescription] for the SQL side and
  /// [GraphPropertyAuthKey] for the graph side.
  ///
  /// Lookups by reference identity for the SQL descriptors (the same
  /// descriptor instance is used at both build time and execution time);
  /// by structural equality for graph keys (see [GraphPropertyAuthKey]).
  const MapFieldAuthPolicy(this._entries);

  final Map<Object, FieldAuthorize> _entries;

  @override
  FieldAuthorize? authFor(Object property) => _entries[property];
}

/// Key for the `argumentValues` entry surfacing the [Authorization]
/// the conduit [Request] carries. The auth-wrapping resolver reads it
/// off the request rather than off args (the args channel is the
/// [Request], not the authorization), but exposing the constant here
/// keeps it discoverable.
const String authorizationArgKey = 'conduitRequest';
