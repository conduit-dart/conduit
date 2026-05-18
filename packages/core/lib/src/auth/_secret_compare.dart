/// Constant-time string equality for secret comparison.
///
/// `==` and `!=` on Dart strings short-circuit on the first byte that
/// differs. That timing differential leaks information: a remote
/// attacker who can measure response latency precisely enough can
/// extract the stored secret one byte at a time. This matters for
/// client secrets, password-hash output (PBKDF2 base64), and any
/// other server-held string the requester is trying to guess.
///
/// [secretsEqual] runs in time proportional to the length of the
/// longer input, regardless of whether the strings match. The xor
/// loop produces a single accumulated diff that's only checked once
/// at the end. A length mismatch still returns `false`, but the
/// timing of that path is intentionally similar to the equal-length
/// path so `length` doesn't leak either.
///
/// Use anywhere a remote-controlled string is compared against a
/// server-held secret. Do NOT use for length-prefixed protocol
/// fields where the length itself is public — there `==` is fine
/// and faster.
library;

bool secretsEqual(String? a, String? b) {
  // Either side null ⇒ no match. Returning early on null leaks
  // "this client has no stored secret" via timing, but that fact
  // is already implied by the protocol flow (public vs confidential
  // client). The case we care about — a remote attacker guessing a
  // present secret byte-by-byte — runs through the loop below.
  if (a == null || b == null) return false;
  // Compare via codeUnits to avoid grapheme-cluster surprises;
  // PBKDF2 base64 output is ASCII anyway. The ternary picks the
  // longer length so the loop runs the same number of iterations
  // even on length mismatch — without leaking which side was
  // longer (the result is `false` either way).
  final aUnits = a.codeUnits;
  final bUnits = b.codeUnits;
  final n = aUnits.length > bUnits.length ? aUnits.length : bUnits.length;
  var diff = aUnits.length ^ bUnits.length;
  for (var i = 0; i < n; i++) {
    final av = i < aUnits.length ? aUnits[i] : 0;
    final bv = i < bUnits.length ? bUnits[i] : 0;
    diff |= av ^ bv;
  }
  return diff == 0;
}
