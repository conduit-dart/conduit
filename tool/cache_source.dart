// Copies every publishable workspace package into the pub cache as
// `hosted/pub.dev/<name>-<version>`, so `conduit create` and the CLI tests
// resolve the workspace sources instead of downloading from pub.dev.
//
// Used by the `cache-source` melos script on every platform. It replaces the
// per-package `melos exec` copy, whose package-name substitution differs
// between melos versions and between sh and cmd.exe.
//
//   dart tool/cache_source.dart
import 'dart:io';

void main() {
  final cache =
      Platform.environment['PUB_CACHE'] ??
      (Platform.isWindows
          ? '${Platform.environment['LOCALAPPDATA']}\\Pub\\Cache'
          : '${Platform.environment['HOME']}/.pub-cache');
  final hosted = Directory(_join([cache, 'hosted', 'pub.dev']));

  var copied = 0;
  for (final member in _workspaceMembers(File('pubspec.yaml'))) {
    final pubspec = File(_join([member, 'pubspec.yaml']));
    if (!pubspec.existsSync()) continue;
    final text = pubspec.readAsStringSync();
    if (RegExp(r'^publish_to:\s*none\b', multiLine: true).hasMatch(text)) {
      continue;
    }
    final name = _field(text, 'name');
    final version = _field(text, 'version');
    if (name == null || version == null) {
      stderr.writeln('$member: pubspec.yaml has no name or version');
      exitCode = 1;
      return;
    }
    final dest = Directory(_join([hosted.path, '$name-$version']));
    _copyContents(Directory(member), dest);
    stdout.writeln('$name-$version -> ${dest.path}');
    copied++;
  }
  stdout.writeln('Cached $copied packages in ${hosted.path}');
}

/// The `workspace:` list of the root pubspec.
List<String> _workspaceMembers(File root) {
  final members = <String>[];
  var inWorkspace = false;
  for (final line in root.readAsLinesSync()) {
    if (line.startsWith('workspace:')) {
      inWorkspace = true;
    } else if (inWorkspace) {
      final item = RegExp(r'^\s+-\s+(\S+)').firstMatch(line);
      if (item != null) {
        members.add(item.group(1)!);
      } else if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#')) {
        break;
      }
    }
  }
  return members;
}

String? _field(String pubspec, String key) => RegExp(
  '^$key:\\s*["\']?([^"\'\\s#]+)',
  multiLine: true,
).firstMatch(pubspec)?.group(1);

/// Copies the non-hidden entries of [from] into [to], like `cp -rf from/* to`.
void _copyContents(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync(followLinks: false)) {
    final base = _basename(entity);
    if (base.startsWith('.')) continue;
    _copy(entity, _join([to.path, base]));
  }
}

/// Copies [entity] to [target]. Symlinks (such as the packages' README.md,
/// which point at the root README) are resolved by hand and copied as their
/// target's contents: following them implicitly fails on Windows, and a
/// relative link would dangle inside the cache.
void _copy(FileSystemEntity entity, String target) {
  if (entity is Link) {
    final dest = entity.targetSync().replaceAll('/', Platform.pathSeparator);
    final resolved = File(dest).isAbsolute
        ? dest
        : _join([entity.parent.path, dest]);
    final type = FileSystemEntity.typeSync(resolved);
    if (type == FileSystemEntityType.file) {
      _copy(File(resolved), target);
    } else if (type == FileSystemEntityType.directory) {
      _copy(Directory(resolved), target);
    } else {
      stderr.writeln('skipping dangling link ${entity.path} -> $dest');
    }
  } else if (entity is File) {
    entity.copySync(target);
  } else if (entity is Directory) {
    Directory(target).createSync(recursive: true);
    for (final child in entity.listSync(followLinks: false)) {
      _copy(child, _join([target, _basename(child)]));
    }
  }
}

String _basename(FileSystemEntity entity) =>
    entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);

String _join(List<String> parts) => parts.join(Platform.pathSeparator);
