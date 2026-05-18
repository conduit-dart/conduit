import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

const _alphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

void main() {
  group('randomStringOfLength', () {
    test('produces strings of the requested length over the OAuth alphabet',
        () {
      for (final len in [1, 16, 32, 64, 256]) {
        final s = randomStringOfLength(len);
        expect(s.length, len);
        for (final cu in s.codeUnits) {
          expect(_alphabet.codeUnits.contains(cu), isTrue,
              reason: 'unexpected char ${String.fromCharCode(cu)}');
        }
      }
    });

    test(
        'character distribution is approximately uniform '
        '(no modulo bias)', () {
      // The previous form `r.nextInt(1000) % 62` biased the first 12
      // characters of the alphabet (1000 mod 62 == 12). Detect that with
      // a chi-square test against the uniform expectation.
      const sampleSize = 100000; // 100k chars across the alphabet
      const k = 62;
      const expectedPerChar = sampleSize / k;

      final counts = <int, int>{};
      // Generate enough total characters to land sampleSize hits.
      final iters = (sampleSize / 32).ceil();
      var produced = 0;
      for (var i = 0; i < iters; i++) {
        final s = randomStringOfLength(32);
        for (final cu in s.codeUnits) {
          if (produced >= sampleSize) break;
          counts[cu] = (counts[cu] ?? 0) + 1;
          produced++;
        }
        if (produced >= sampleSize) break;
      }

      // Chi-square statistic.
      var chi2 = 0.0;
      for (final cu in _alphabet.codeUnits) {
        final obs = counts[cu] ?? 0;
        final diff = obs - expectedPerChar;
        chi2 += diff * diff / expectedPerChar;
      }

      // For df = 61 and α = 0.001, the critical value is ~99.6.
      // The biased version reliably trips this; the fixed version
      // hovers around 60-70 with occasional excursions to 90.
      expect(chi2, lessThan(99.6),
          reason: 'character distribution not uniform: chi2=$chi2');
    });
  });
}
