import 'package:conduit_core/src/auth/_secret_compare.dart';
import 'package:test/test.dart';

/// Constant-time-ness can't be unit-tested directly (timing varies across
/// hosts and CI). What we *can* assert is that [secretsEqual] returns the
/// same boolean as `==` for every comparison the auth code would
/// realistically perform: equal/unequal strings, length mismatches,
/// nullability, and the empty-string case. The xor-loop's
/// constant-time property is then a property of the implementation,
/// reviewed at code-review time.
void main() {
  group('secretsEqual', () {
    test('returns true on identical strings', () {
      expect(secretsEqual('abc', 'abc'), isTrue);
      expect(secretsEqual('', ''), isTrue);
      expect(secretsEqual('a' * 1024, 'a' * 1024), isTrue);
    });

    test('returns false on differing strings of equal length', () {
      expect(secretsEqual('abc', 'abd'), isFalse);
      expect(secretsEqual('foo', 'bar'), isFalse);
    });

    test('returns false on length mismatch', () {
      expect(secretsEqual('abc', 'abcd'), isFalse);
      expect(secretsEqual('abcd', 'abc'), isFalse);
      expect(secretsEqual('', 'a'), isFalse);
      expect(secretsEqual('a', ''), isFalse);
    });

    test('returns false when either side is null', () {
      expect(secretsEqual(null, 'x'), isFalse);
      expect(secretsEqual('x', null), isFalse);
      // Both null is also false: a null secret should never match anything,
      // including null, since the call site is "user input vs server-stored
      // secret" and a server with no stored secret should refuse all input.
      expect(secretsEqual(null, null), isFalse);
    });

    test('matches `==` semantics across a fuzz set', () {
      const samples = [
        'short',
        'short',
        'longer string with spaces',
        'longer string with spaces',
        'longer string with spaces!',
        '',
        'é',
        'é',
        'é!',
      ];
      for (final a in samples) {
        for (final b in samples) {
          expect(secretsEqual(a, b), a == b,
              reason: 'mismatch on (${a.length}, ${b.length})');
        }
      }
    });
  });
}
