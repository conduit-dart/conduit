import 'dart:io';

Future cachePackages(
    Iterable<String> packageNames, String projectVersion) async {
  const cmd = "dart";
  final args = [
    "pub",
    "cache",
    "add",
    "-v",
  ];
  for (final name in packageNames) {
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
        throw StateError(
          "'pub cache' failed with the following message: ${res.stderr}",
        );
      }
    }
  }
}

Future<String?> findGlobalPath() async {
  const cmd = "dart";

  final res = await Process.run(
    cmd,
    ["pub", "global", "list"],
    runInShell: true,
  );
  var regex = RegExp(r'conduit.* at path "([^"]+)"$', multiLine: true);

  Match? match = regex.firstMatch(res.stdout);
  return match?.group(1);
}

Future<String?> findGlobalVersion() async {
  const cmd = "dart";

  final res = await Process.run(
    cmd,
    ["pub", "global", "list"],
    runInShell: true,
  );
  var lineRegex = RegExp(r'conduit .*');
  var versionRegex =
      RegExp(r'\d+\.\d+\.\d+(?:\.\d+)?(?:-[a-zA-Z\d]+(?:\.[a-zA-Z\d]+)*)?');
  Match? lineMatch = lineRegex.firstMatch(res.stdout);

  if (lineMatch != null) {
    Match? versionMatch = versionRegex.firstMatch(lineMatch.group(0)!);
    if (versionMatch != null) {
      return versionMatch.group(0);
    }
  }
  return null;
}
