/// Prints the next release version and writes the breaking commits.
///
///     dart run tool/ai/bin/next_version.dart --current 7.0.0 \
///         --commits .ai/commits.txt --breaking-out .ai/breaking.txt
///
/// `--commits` holds full commit messages separated by NUL bytes
/// (`git log -z --format=%B <last-tag>..HEAD`).
library;

import 'dart:io';

import 'package:conduit_ai_tool/next_version.dart';
import 'package:pub_semver/pub_semver.dart';

void main(List<String> args) {
  late Version current;
  late String commitsPath;
  String? breakingOut;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--current':
        current = Version.parse(args[++i]);
      case '--commits':
        commitsPath = args[++i];
      case '--breaking-out':
        breakingOut = args[++i];
    }
  }
  final commits = File(commitsPath)
      .readAsStringSync()
      .split('\u0000')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList();
  if (commits.isEmpty) {
    stderr.writeln('no commits since the last release');
    exit(3);
  }
  if (breakingOut != null) {
    File(breakingOut).writeAsStringSync(breakingCommits(commits).join('\n'));
  }
  stdout.writeln(nextVersion(current, bumpFor(commits)));
}
