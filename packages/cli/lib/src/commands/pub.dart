import 'dart:io';

Future cachePackages(
    Iterable<String> packageNames, String projectVersion) async {
  const String cmd = "dart";
  final args = [
    "pub",
    "cache",
    "add",
    "-v",
  ];
  for (final String name in packageNames) {
    final res = await Process.run(
      cmd,
      [...args, name],
      runInShell: true,
    );
    if (res.exitCode != 0) {
      final retry = await Process.run(
        cmd,
        [...args.sublist(0, 3), name],
        runInShell: true,
      );
      if (retry.exitCode != 0) {
        print("${res.stdout}");
        print("${res.stderr}");
        throw StateError(
          "'pub cache' failed with the following message: ${res.stderr}",
        );
      }
    }
  }
}

Future<Uri?> findGlobalPath() async {
  const String cmd = "dart";

  final res = await Process.run(
    cmd,
    ["pub", "global", "list"],
    runInShell: true,
  );
  RegExp regex = RegExp(r'^.*conduit.* at path "(/[^"]+)"$', multiLine: true);

  Match? match = regex.firstMatch(res.stdout);
  if (match != null) {
    return Uri.directory(match.group(1)!);
  }
  return null;
}
