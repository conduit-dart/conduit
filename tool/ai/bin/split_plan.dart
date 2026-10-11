/// Split proposals for the AI pipeline (see lib/split_plan.dart).
///
///     dart run tool/ai/bin/split_plan.dart --count research.json
///     dart run tool/ai/bin/split_plan.dart --render research.json
///     dart run tool/ai/bin/split_plan.dart --parse comment.md
///
/// `--count` validates the `split` field of the research output and prints
/// the number of parts (0: no split). `--render` prints the proposal
/// comment. `--parse` reads the plan back from a proposal comment and prints
/// it as JSON. Invalid input exits with code 2.
///
/// Used by .github/workflows/ai-research.yml and ai-split.yml.
library;

import 'dart:convert';
import 'dart:io';

import 'package:conduit_ai_tool/split_plan.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: split_plan.dart --count|--render|--parse <file>');
    exit(64);
  }
  final text = File(args[1]).readAsStringSync();
  try {
    switch (args[0]) {
      case '--count':
        stdout.writeln(_fromResearch(text).length);
      case '--render':
        stdout.write(renderProposal(_fromResearch(text)));
      case '--parse':
        stdout.writeln(
          jsonEncode([for (final p in parseProposal(text)) p.toJson()]),
        );
      default:
        stderr.writeln('unknown argument ${args[0]}');
        exit(64);
    }
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 2;
  }
}

List<Part> _fromResearch(String text) {
  final json = jsonDecode(text);
  if (json is! Map) {
    throw const FormatException('research.json is not an object');
  }
  return parsePlan(json['split']);
}
