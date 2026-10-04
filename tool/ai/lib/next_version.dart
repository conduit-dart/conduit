/// Picks the next release version from conventional-commit subjects, so the
/// release-prep stage never lets a model choose the version number.
library;

import 'package:pub_semver/pub_semver.dart';

final _header = RegExp(r'^(\w+)(\([^)]*\))?(!)?:');

/// How a set of commits moves the version.
enum Bump { major, minor, patch }

/// `type!:` or a `BREAKING CHANGE:` footer is major, `feat` is minor,
/// anything else is patch.
Bump bumpFor(Iterable<String> commits) {
  var bump = Bump.patch;
  for (final commit in commits) {
    final subject = commit.split('\n').first;
    final m = _header.firstMatch(subject);
    if (m?.group(3) == '!' ||
        RegExp(r'^BREAKING[ -]CHANGE:', multiLine: true).hasMatch(commit)) {
      return Bump.major;
    }
    if (m?.group(1) == 'feat') bump = Bump.minor;
  }
  return bump;
}

/// Commits that carry a breaking change (for the migration notes).
List<String> breakingCommits(Iterable<String> commits) => [
  for (final commit in commits)
    if (_header.firstMatch(commit.split('\n').first)?.group(3) == '!' ||
        RegExp(r'^BREAKING[ -]CHANGE:', multiLine: true).hasMatch(commit))
      commit.split('\n').first,
];

/// The version after [current] for [bump].
Version nextVersion(Version current, Bump bump) => switch (bump) {
  Bump.major => current.nextMajor,
  Bump.minor => current.nextMinor,
  Bump.patch => current.nextPatch,
};
