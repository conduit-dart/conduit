import 'package:conduit_ai_tool/next_version.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  test('fixes only: patch', () {
    expect(bumpFor(['fix(core): x', 'docs: y', 'chore: z']), Bump.patch);
  });

  test('any feat: minor', () {
    expect(bumpFor(['fix: x', 'feat(sqlite): y']), Bump.minor);
  });

  test('bang or BREAKING CHANGE footer: major', () {
    expect(bumpFor(['feat: x', 'build!: raise floor']), Bump.major);
    expect(bumpFor(['refactor(core)!: y']), Bump.major);
    expect(bumpFor(['fix: x\n\nBREAKING CHANGE: removed y']), Bump.major);
  });

  test('a bang outside the type is not breaking', () {
    expect(bumpFor(['fix: handle "!:" in paths']), Bump.patch);
  });

  test('the real log since v7.0.0 releases 8.0.0', () {
    // Subjects from `git log v7.0.0..origin/master` on 2026-10-04.
    const log = [
      'fix(test): exclude integration-tagged suites from a plain dart test (#306)',
      'refactor: adopt Dart 3.13 constructor lints and primary constructors (#311)',
      'build!: hardening pass — Dart 3.13 floor, format/coverage/advisory CI (#304)',
      'feat(sqlite): Document/JSON column support (#299)',
    ];
    expect(nextVersion(Version(7, 0, 0), bumpFor(log)), Version(8, 0, 0));
    expect(breakingCommits(log), [log[2]]);
  });

  test('nextVersion', () {
    expect(nextVersion(Version(7, 0, 0), Bump.minor), Version(7, 1, 0));
    expect(nextVersion(Version(7, 1, 3), Bump.patch), Version(7, 1, 4));
  });
}
