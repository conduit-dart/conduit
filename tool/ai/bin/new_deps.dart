/// Fails when the working tree adds a dependency that was not approved.
///
///     dart run tool/ai/bin/new_deps.dart --base origin/master --approve dio
///
/// Compares every pubspec.yaml tracked at `--base` (or added since) with the
/// working tree. Workspace packages (`conduit_*`, path dependencies inside
/// the repo) are always allowed. Exit code 1 lists the offenders.
library;

import 'dart:io';

import 'package:conduit_ai_tool/new_deps.dart';

Future<void> main(List<String> args) async {
  var base = 'origin/master';
  final approved = <String>{};
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--base':
        base = args[++i];
      case '--approve':
        approved.add(args[++i]);
      default:
        stderr.writeln('unknown argument ${args[i]}');
        exit(64);
    }
  }

  final paths = {
    ..._git(['ls-tree', '-r', '--name-only', base]).split('\n'),
    ..._git(['ls-files', '--cached', '--others', '--exclude-standard'])
        .split('\n'),
  }.where((p) => p == 'pubspec.yaml' || p.endsWith('/pubspec.yaml'));

  final before = <String, String>{};
  final after = <String, String>{};
  for (final path in paths) {
    final old = Process.runSync('git', ['show', '$base:$path']);
    if (old.exitCode == 0) before[path] = old.stdout as String;
    final file = File(path);
    if (file.existsSync()) after[path] = file.readAsStringSync();
  }

  final workspace = {
    for (final contents in after.values)
      if (RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(contents)
          case final m?)
        m.group(1)!,
  };

  final added = addedDependencies(before, after);
  final offenders = unapproved(added, {...approved, ...workspace});
  for (final MapEntry(key: path, value: names) in added.entries) {
    stdout.writeln('$path: +${names.join(', +')}');
  }
  if (offenders.isNotEmpty) {
    stderr.writeln('unapproved new dependencies: ${offenders.join(', ')}');
    exit(1);
  }
}

String _git(List<String> args) {
  final r = Process.runSync('git', args);
  if (r.exitCode != 0) {
    stderr.write(r.stderr);
    exit(r.exitCode);
  }
  return (r.stdout as String).trim();
}
