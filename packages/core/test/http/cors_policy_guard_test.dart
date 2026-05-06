import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

void main() {
  group('CORSPolicy default', () {
    test('does NOT enable allowCredentials out of the box', () {
      // Regression guard: the previous default was `true` paired with
      // `allowedOrigins = ["*"]`, which effectively allowed credentialed
      // CORS from every origin. The new default opts users out; they
      // must explicitly turn credentials on with a concrete origin list.
      final p = CORSPolicy();
      expect(p.allowCredentials, isFalse);
      expect(p.allowedOrigins, ["*"]);
    });

    test('default policy passes validateConfiguration', () {
      // Whatever else the default does, it must not be self-rejecting.
      // (Apps that never override the policy still need to start.)
      CORSPolicy().validateConfiguration();
    });
  });

  group('CORSPolicy.validateConfiguration', () {
    test('throws on allowCredentials + wildcard origins', () {
      final p = CORSPolicy()
        ..allowCredentials = true; // wildcard origins still default
      expect(p.validateConfiguration, throwsStateError);
    });

    test('throws on allowCredentials + empty origins', () {
      final p = CORSPolicy()
        ..allowCredentials = true
        ..allowedOrigins = <String>[];
      expect(p.validateConfiguration, throwsStateError);
    });

    test('accepts allowCredentials + concrete origins', () {
      final p = CORSPolicy()
        ..allowCredentials = true
        ..allowedOrigins = ["http://example.com"];
      // Should not throw.
      p.validateConfiguration();
    });

    test('accepts wildcard origins when credentials are off', () {
      // The pre-existing public-API permissive case still works.
      final p = CORSPolicy()..allowCredentials = false;
      expect(p.allowedOrigins, ["*"]);
      p.validateConfiguration();
    });

    test('accepts empty origins when credentials are off', () {
      final p = CORSPolicy()
        ..allowCredentials = false
        ..allowedOrigins = <String>[];
      p.validateConfiguration();
    });
  });
}
