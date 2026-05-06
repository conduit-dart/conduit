import 'dart:convert';

import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

String _basic(String s) => 'Basic ${base64Encode(utf8.encode(s))}';

void main() {
  const parser = AuthorizationBasicParser();

  group('AuthorizationBasicParser', () {
    test('parses simple username:password', () {
      final c = parser.parse(_basic('alice:s3cret'));
      expect(c.username, 'alice');
      expect(c.password, 's3cret');
    });

    test('passwords containing : are accepted (RFC 7617 §2)', () {
      // A password with a single internal colon — the previous parser
      // rejected this because it split on every colon and required
      // exactly two pieces.
      final c = parser.parse(_basic('alice:s3:cret'));
      expect(c.username, 'alice');
      expect(c.password, 's3:cret');
    });

    test('passwords containing multiple : are accepted', () {
      final c = parser.parse(_basic('alice:a:b:c:d'));
      expect(c.username, 'alice');
      expect(c.password, 'a:b:c:d');
    });

    test('empty password is accepted', () {
      final c = parser.parse(_basic('alice:'));
      expect(c.username, 'alice');
      expect(c.password, '');
    });

    test('empty username is accepted', () {
      final c = parser.parse(_basic(':s3cret'));
      expect(c.username, '');
      expect(c.password, 's3cret');
    });

    test('credentials with no colon throw malformed', () {
      expect(
        () => parser.parse(_basic('aliceonly')),
        throwsA(
          isA<AuthorizationParserException>().having(
            (e) => e.reason,
            'reason',
            AuthorizationParserExceptionReason.malformed,
          ),
        ),
      );
    });
  });
}
