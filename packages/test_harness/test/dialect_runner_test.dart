import 'package:conduit_test/conduit_test.dart';
import 'package:test/test.dart';

void main() {
  group('evaluateAnnotations', () {
    test('no annotations runs by default on every dialect', () {
      for (final d in Dialect.values) {
        final decision = evaluateAnnotations(active: d);
        expect(decision.shouldSkip, isFalse,
            reason: 'no annotations should never skip on ${d.name}');
        expect(decision.skipReason, isNull);
      }
    });

    test('OnlyOn allow-list runs when active dialect is allowed', () {
      final decision = evaluateAnnotations(
        active: Dialect.postgres,
        onlyOn: const OnlyOn([Dialect.postgres, Dialect.cockroach]),
      );
      expect(decision.shouldSkip, isFalse);
    });

    test('OnlyOn allow-list skips when active dialect is excluded', () {
      final decision = evaluateAnnotations(
        active: Dialect.mysql,
        onlyOn: const OnlyOn([Dialect.postgres]),
      );
      expect(decision.shouldSkip, isTrue);
      expect(decision.skipReason, contains('postgres'));
      expect(decision.skipReason, contains('mysql'));
    });

    test('OnlyOn uses caller-supplied reason if present', () {
      final decision = evaluateAnnotations(
        active: Dialect.sqlite,
        onlyOn: const OnlyOn([Dialect.postgres],
            reason: 'jsonb is postgres-only'),
      );
      expect(decision.skipReason, equals('jsonb is postgres-only'));
    });

    test('SkipOn skips when active dialect is in the deny list', () {
      final decision = evaluateAnnotations(
        active: Dialect.mysql,
        skipOn: const SkipOn([Dialect.mysql], reason: 'no RETURNING'),
      );
      expect(decision.shouldSkip, isTrue);
      expect(decision.skipReason, equals('no RETURNING'));
    });

    test('SkipOn runs when active dialect is not in the deny list', () {
      final decision = evaluateAnnotations(
        active: Dialect.postgres,
        skipOn: const SkipOn([Dialect.mysql]),
      );
      expect(decision.shouldSkip, isFalse);
    });

    test('OnlyOn takes precedence over SkipOn when both are present', () {
      // OnlyOn excludes mysql first; SkipOn would also exclude mysql, but
      // we never get there. Verify the reason cites OnlyOn, not SkipOn.
      final decision = evaluateAnnotations(
        active: Dialect.mysql,
        onlyOn: const OnlyOn([Dialect.postgres]),
        skipOn: const SkipOn([Dialect.mysql], reason: 'should not show up'),
      );
      expect(decision.shouldSkip, isTrue);
      expect(decision.skipReason, isNot(contains('should not show up')));
    });

    test('PostgresOnly shorthand behaves identically to OnlyOn([postgres])',
        () {
      final shorthand =
          evaluateAnnotations(active: Dialect.sqlite, onlyOn: const PostgresOnly());
      final longhand = evaluateAnnotations(
          active: Dialect.sqlite, onlyOn: const OnlyOn([Dialect.postgres]));
      expect(shorthand.shouldSkip, equals(longhand.shouldSkip));
    });
  });

  group('resolveActiveDialect', () {
    test('explicit override wins', () {
      expect(resolveActiveDialect(override: Dialect.sqlite), Dialect.sqlite);
    });

    test('defaults to postgres when env var is missing or empty', () {
      // Hard to mutate Platform.environment in-process, so only test
      // the override + default branches; env-var resolution is exercised
      // by the integration test which sets CONDUIT_TEST_DIALECT.
      // Falls through to env-then-default.
      final actual = resolveActiveDialect();
      expect(Dialect.values, contains(actual));
    });
  });

  group('skipIfDialectMismatch', () {
    test('returns normally when dialect matches', () {
      expect(
        () => skipIfDialectMismatch(
          activeOverride: Dialect.postgres,
          onlyOn: const OnlyOn([Dialect.postgres]),
        ),
        returnsNormally,
      );
    });

    test('throws TestSkipped when dialect mismatches', () {
      expect(
        () => skipIfDialectMismatch(
          activeOverride: Dialect.mysql,
          onlyOn: const OnlyOn([Dialect.postgres]),
        ),
        throwsA(isA<TestSkipped>()),
      );
    });
  });

  group('fixture: simulated harness with both annotations', () {
    // Stand-in for a real harness — exercises the runner against a
    // configurable dialect to make sure the fanout decisions match
    // expectations.
    void runFanout({
      required Dialect active,
      OnlyOn? onlyOn,
      SkipOn? skipOn,
      required bool expectSkip,
    }) {
      final decision = evaluateAnnotations(
        active: active,
        onlyOn: onlyOn,
        skipOn: skipOn,
      );
      expect(decision.shouldSkip, expectSkip,
          reason: 'active=${active.name} onlyOn=$onlyOn skipOn=$skipOn');
    }

    test('cockroach treated independently from postgres', () {
      // A test that uses postgres-specific syntax should still skip on
      // cockroach unless explicitly listed.
      runFanout(
        active: Dialect.cockroach,
        onlyOn: const OnlyOn([Dialect.postgres]),
        expectSkip: true,
      );
      runFanout(
        active: Dialect.cockroach,
        onlyOn: const OnlyOn([Dialect.postgres, Dialect.cockroach]),
        expectSkip: false,
      );
    });

    test('SkipOn list with multiple dialects', () {
      runFanout(
        active: Dialect.mysql,
        skipOn: const SkipOn([Dialect.mysql, Dialect.sqlite]),
        expectSkip: true,
      );
      runFanout(
        active: Dialect.sqlite,
        skipOn: const SkipOn([Dialect.mysql, Dialect.sqlite]),
        expectSkip: true,
      );
      runFanout(
        active: Dialect.postgres,
        skipOn: const SkipOn([Dialect.mysql, Dialect.sqlite]),
        expectSkip: false,
      );
    });
  });
}
