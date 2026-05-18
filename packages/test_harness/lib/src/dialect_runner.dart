import 'dart:io';

import 'dialect_annotations.dart';

/// Resolve the dialect the active test process is targetting.
///
/// Resolution order:
///   1. Explicit [override] argument (used by harness subclasses that
///      already know their dialect at install time).
///   2. `CONDUIT_TEST_DIALECT` environment variable. Accepts the lower
///      case dialect name (`postgres`, `sqlite`, `mysql`, `cockroach`).
///   3. Default: [Dialect.postgres] — preserves the legacy behaviour of
///      tests that predate this annotation system.
///
/// A nonsense value in the env var raises [ArgumentError] rather than
/// silently degrading to postgres — better to surface a typo than to
/// quietly run the wrong matrix.
Dialect resolveActiveDialect({Dialect? override}) {
  if (override != null) return override;

  final raw = Platform.environment['CONDUIT_TEST_DIALECT'];
  if (raw == null || raw.trim().isEmpty) {
    return Dialect.postgres;
  }

  final normalized = raw.trim().toLowerCase();
  for (final dialect in Dialect.values) {
    if (dialect.name == normalized) return dialect;
  }
  throw ArgumentError.value(
    raw,
    'CONDUIT_TEST_DIALECT',
    'Unknown dialect — expected one of ${Dialect.values.map((d) => d.name).join(', ')}.',
  );
}

/// Result of evaluating an [OnlyOn] / [SkipOn] pair against a target
/// [Dialect]. `null` means "run normally"; a non-null value is the
/// reason string to pass to `package:test`'s `skip:` parameter.
class DialectSkipDecision {
  const DialectSkipDecision._(this.skipReason);

  /// Skip with the given reason.
  factory DialectSkipDecision.skip(String reason) =
      DialectSkipDecision._;

  /// Run the test.
  static const DialectSkipDecision run = DialectSkipDecision._(null);

  /// `null` if the test should run, otherwise a human-readable
  /// explanation suitable for `skip:`.
  final String? skipReason;

  /// `true` if [skipReason] is non-null.
  bool get shouldSkip => skipReason != null;
}

/// Decide whether a test annotated with [onlyOn] and/or [skipOn]
/// should run against [active]. Either annotation may be null.
///
/// Semantics match the docstrings on [OnlyOn] / [SkipOn]:
///
///   * `OnlyOn([X, Y])` → run only if `active` is in `[X, Y]`,
///     otherwise skip with a reason mentioning the allowed dialects.
///   * `SkipOn([X])` → skip if `active == X`, run otherwise.
///   * Both annotations: `OnlyOn` takes precedence — if the dialect
///     isn't in the allow-list it's skipped before `SkipOn` is even
///     consulted. (In practice you'd never write both, but the
///     ordering must be deterministic.)
DialectSkipDecision evaluateAnnotations({
  required Dialect active,
  OnlyOn? onlyOn,
  SkipOn? skipOn,
}) {
  if (onlyOn != null && !onlyOn.dialects.contains(active)) {
    final allowed = onlyOn.dialects.map((d) => d.name).join(', ');
    final reason = onlyOn.reason ??
        '@OnlyOn restricts this test to [$allowed]; '
            'active dialect is ${active.name}.';
    return DialectSkipDecision.skip(reason);
  }

  if (skipOn != null && skipOn.dialects.contains(active)) {
    final reason = skipOn.reason ??
        '@SkipOn excludes this test on dialect ${active.name}.';
    return DialectSkipDecision.skip(reason);
  }

  return DialectSkipDecision.run;
}

/// Helper for the common "skip the rest of this group on dialect
/// mismatch" pattern. Use from inside a `setUpAll`:
///
/// ```dart
/// group('jsonb operators', () {
///   setUpAll(() => skipIfDialectMismatch(
///         onlyOn: const OnlyOn([Dialect.postgres]),
///       ));
///
///   test('@> round-trips', () async { ... });
/// });
/// ```
///
/// On mismatch, throws a [TestSkipped] error with a descriptive
/// reason — `package:test` reports the group as skipped with that
/// reason. On match, returns normally.
void skipIfDialectMismatch({
  OnlyOn? onlyOn,
  SkipOn? skipOn,
  Dialect? activeOverride,
}) {
  final active = resolveActiveDialect(override: activeOverride);
  final decision = evaluateAnnotations(
    active: active,
    onlyOn: onlyOn,
    skipOn: skipOn,
  );
  if (decision.shouldSkip) {
    throw TestSkipped(decision.skipReason!);
  }
}

/// Lightweight error type recognised by `package:test`'s setUp/Group
/// machinery as a "skip the rest of this group" signal. We don't
/// import `package:test`'s internal `TestFailure`/`Skipped` because
/// those aren't part of its public API; instead we throw a marker
/// the caller can intercept, and the convention is that `setUpAll`
/// throwing this leads to a skipped group with the message attached.
///
/// Implementing as a real `Error` keeps the stack-trace reporting
/// honest — the test will appear as "skipped" with a clear reason
/// rather than as a passing-but-no-tests-ran group.
class TestSkipped implements Exception {
  TestSkipped(this.reason);
  final String reason;

  @override
  String toString() => 'TestSkipped: $reason';
}
