/// Detects dependencies added between two versions of the workspace's
/// pubspec files, so the implementation stage can refuse any dependency the
/// maintainer did not approve at Gate 2.
library;

import 'package:yaml/yaml.dart';

const _sections = ['dependencies', 'dev_dependencies'];

/// The dependency names declared in one pubspec, across [_sections].
Set<String> declaredDependencies(String pubspecYaml) {
  final doc = loadYaml(pubspecYaml);
  if (doc is! YamlMap) return const {};
  return {
    for (final section in _sections)
      if (doc[section] case final YamlMap deps)
        for (final name in deps.keys) name as String,
  };
}

/// Returns `package path -> newly added dependency names`.
///
/// [before] and [after] map a pubspec path to its contents; a path missing
/// from [before] is a new package and all of its dependencies count as new.
Map<String, Set<String>> addedDependencies(
  Map<String, String> before,
  Map<String, String> after,
) {
  final added = <String, Set<String>>{};
  for (final MapEntry(key: path, value: contents) in after.entries) {
    final old = before[path];
    final fresh = declaredDependencies(contents)
        .difference(old == null ? const <String>{} : declaredDependencies(old));
    if (fresh.isNotEmpty) added[path] = fresh;
  }
  return added;
}

/// Names added anywhere that are not in [approved].
Set<String> unapproved(Map<String, Set<String>> added, Set<String> approved) =>
    {for (final names in added.values) ...names}.difference(approved);
