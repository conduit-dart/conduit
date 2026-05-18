// Unit tests for the [FieldAuthorize] runtime behavior.
//
// Exercises [wrapResolverWithAuth] directly so the wrapper's contract
// can be verified without spinning up a full HTTP request — the
// integration-shaped tests live in `cross_source_schema_test.dart`.
//
// The wrapper accepts either a real [Request] (production path) or an
// inline [Authorization] under the `fieldAuthorizationArgKey` channel
// (test/embedding path). These tests use the inline channel for the
// scope checks; the [allowOwner] case still needs a real Request, so
// we construct one against a stub `HttpRequest`.

import 'dart:io';

import 'package:conduit_core/conduit_core.dart' hide SchemaBuilder;
import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:test/test.dart';

void main() {
  group('wrapResolverWithAuth — scope checks', () {
    test('allows when caller scopes intersect annotation scopes', () async {
      const auth = FieldAuthorize(scopes: ['pii:read']);
      final wrapped = wrapResolverWithAuth(_passThroughResolver, auth);
      final result = await wrapped(
        const _Parent(),
        <String, dynamic>{
          fieldAuthorizationArgKey: _authWithScopes(['pii:read']),
        },
      );
      expect(result, equals('ok'));
    });

    test('rejects when caller scopes do not intersect annotation scopes',
        () async {
      const auth = FieldAuthorize(scopes: ['pii:read']);
      final wrapped = wrapResolverWithAuth(_passThroughResolver, auth);
      expect(
        () => wrapped(
          const _Parent(),
          <String, dynamic>{
            fieldAuthorizationArgKey: _authWithScopes(['profile:read']),
          },
        ),
        throwsA(isA<GraphQLException>()),
      );
    });

    test('rejects when neither Request nor Authorization is in args',
        () async {
      const auth = FieldAuthorize(scopes: ['pii:read']);
      final wrapped = wrapResolverWithAuth(_passThroughResolver, auth);
      expect(
        () => wrapped(const _Parent(), const <String, dynamic>{}),
        throwsA(isA<GraphQLException>()),
      );
    });
  });

  group('wrapResolverWithAuth — allowOwner', () {
    test('allowOwner short-circuits the scope check when it returns true',
        () async {
      final auth = FieldAuthorize(
        scopes: const ['pii:read'],
        allowOwner: (parent, request) =>
            parent is _Parent && parent.isOwner,
      );
      final wrapped = wrapResolverWithAuth(_passThroughResolver, auth);
      final request = _stubRequest()..authorization = _authWithScopes([]);
      final result = await wrapped(
        const _Parent(isOwner: true),
        <String, dynamic>{authorizationArgKey: request},
      );
      expect(result, equals('ok'));
    });

    test('allowOwner does not short-circuit when it returns false',
        () async {
      final auth = FieldAuthorize(
        scopes: const ['pii:read'],
        allowOwner: (parent, request) => false,
      );
      final wrapped = wrapResolverWithAuth(_passThroughResolver, auth);
      final request = _stubRequest()
        ..authorization = _authWithScopes(['profile:read']);
      expect(
        () => wrapped(
          const _Parent(),
          <String, dynamic>{authorizationArgKey: request},
        ),
        throwsA(isA<GraphQLException>()),
      );
    });
  });

  group('MapFieldAuthPolicy', () {
    test('returns the registered FieldAuthorize for a given key', () {
      const auth1 = FieldAuthorize(scopes: ['pii:read']);
      const auth2 = FieldAuthorize(scopes: ['admin']);
      const key1 = GraphPropertyAuthKey(_FakeProfile, 'ssn');
      const key2 = GraphPropertyAuthKey(_FakeAccount, 'balance');
      final policy = MapFieldAuthPolicy(<Object, FieldAuthorize>{
        key1: auth1,
        key2: auth2,
      });
      expect(identical(policy.authFor(key1), auth1), isTrue);
      expect(identical(policy.authFor(key2), auth2), isTrue);
    });

    test('returns null for unknown keys', () {
      const policy = MapFieldAuthPolicy(<Object, FieldAuthorize>{});
      expect(
        policy.authFor(const GraphPropertyAuthKey(_FakeAccount, 'x')),
        isNull,
      );
    });

    test('GraphPropertyAuthKey hashes / compares structurally', () {
      const a = GraphPropertyAuthKey(_FakeProfile, 'ssn');
      const b = GraphPropertyAuthKey(_FakeProfile, 'ssn');
      const c = GraphPropertyAuthKey(_FakeProfile, 'email');
      expect(a == b, isTrue);
      expect(a.hashCode, equals(b.hashCode));
      expect(a == c, isFalse);
    });
  });
}

// -- Helpers ---------------------------------------------------------------

Object? _passThroughResolver(Object? parent, Map<String, dynamic> args) =>
    'ok';

class _Parent {
  const _Parent({this.isOwner = false});
  final bool isOwner;
}

class _FakeProfile {}

class _FakeAccount {}

Authorization _authWithScopes(List<String> scopeStrings) => Authorization(
      'client',
      null,
      null,
      scopes: scopeStrings.map(AuthScope.new).toList(),
    );

/// Constructs a real [Request] against a stub [HttpRequest]. Only the
/// `Request.authorization` slot is exercised by [wrapResolverWithAuth]
/// — the rest of the `HttpRequest` surface is unused.
Request _stubRequest() => Request(_StubHttpRequest());

class _StubHttpRequest implements HttpRequest {
  @override
  Uri get uri => Uri.parse('/');

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
