/// Vets dependency candidates against pub.dev and prints the issue comment.
///
///     dart run tool/ai/bin/dep_candidates.dart \
///         --sdk-floor 3.13.0 --rationale .ai/rationale.json dio http
///
///     dart run tool/ai/bin/dep_candidates.dart --parse-choice comment.md
///
/// Used by .github/workflows/ai-research.yml and ai-implement.yml.
library;

import 'dart:convert';
import 'dart:io';

import 'package:conduit_ai_tool/dep_candidates.dart';
import 'package:pub_semver/pub_semver.dart';

Future<void> main(List<String> args) async {
  var sdkFloor = Version(3, 13, 0);
  var now = DateTime.now().toUtc();
  var rationale = <String, String>{};
  final names = <String>[];

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--sdk-floor':
        sdkFloor = Version.parse(args[++i]);
      case '--now':
        now = DateTime.parse(args[++i]).toUtc();
      case '--rationale':
        rationale = parseRationale(File(args[++i]).readAsStringSync());
      case '--parse-choice':
        try {
          stdout.writeln(parseChoice(File(args[++i]).readAsStringSync()));
        } on FormatException catch (e) {
          stderr.writeln(e.message);
          exitCode = 2;
        }
        return;
      default:
        names.add(args[i]);
    }
  }

  final valid = RegExp(r'^[a-z][a-z0-9_]*$');
  final client = HttpClient()..userAgent = 'conduit-ai-pipeline';
  try {
    final candidates = <Candidate>[];
    for (final name in names.toSet()) {
      if (!valid.hasMatch(name)) {
        candidates.add(
          Candidate(
            name: name,
            found: false,
            exclusions: const ['not a valid package name'],
          ),
        );
        continue;
      }
      candidates.add(
        await evaluate(
          name,
          fetch: (path) => _fetch(client, path),
          now: now,
          sdkFloor: sdkFloor,
        ),
      );
    }
    stdout.write(
      renderComment(candidates, sdkFloor: sdkFloor, rationale: rationale),
    );
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>?> _fetch(HttpClient client, String path) async {
  final request = await client.getUrl(Uri.https('pub.dev', path));
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode == HttpStatus.notFound) return null;
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('pub.dev $path returned ${response.statusCode}');
  }
  return jsonDecode(body) as Map<String, dynamic>;
}
