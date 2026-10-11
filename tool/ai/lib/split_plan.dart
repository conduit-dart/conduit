/// Validates and renders the research stage's proposal to split an issue
/// into sub-issues.
///
/// The research agent writes the proposed parts to `.ai/research.json`
/// (`split`). The pipeline checks them here, posts them as a comment with
/// the plan embedded as JSON, and only creates the sub-issues once a
/// maintainer adds `split:approved`. The plan the maintainer approved is
/// read back from that comment, so an edit to its JSON block is what gets
/// created.
library;

import 'dart:convert';

/// Marks the issue comment that carries the split proposal.
const splitMarker = '<!-- conduit-ai:split -->';

/// Fewest and most parts a split may have.
const minParts = 2;
const maxParts = 6;

const _maxTitle = 100;
const _maxBody = 6000;

/// One proposed sub-issue.
class Part {
  new({
    required this.title,
    required this.body,
    required this.dependsOn,
    required this.manual,
  });

  /// Issue title.
  final String title;

  /// Issue body (markdown): what this part delivers and how it is tested.
  final String body;

  /// 1-based positions of earlier parts that must land first.
  final List<int> dependsOn;

  /// True when the part needs a maintainer (workflows, CI infrastructure,
  /// secrets) and must not enter the pipeline.
  final bool manual;

  Map<String, Object> toJson() => {
    'title': title,
    'body': body,
    'depends_on': dependsOn,
    'manual': manual,
  };
}

/// Parses and validates a split plan (a JSON list). An empty list means
/// "do not split". Throws [FormatException] naming the first problem.
List<Part> parsePlan(Object? json) {
  if (json == null) return const [];
  if (json is! List) throw const FormatException('split must be a list');
  if (json.isEmpty) return const [];
  if (json.length < minParts || json.length > maxParts) {
    throw FormatException(
      'split must have $minParts to $maxParts parts, got ${json.length}',
    );
  }
  final parts = <Part>[];
  final titles = <String>{};
  for (var i = 0; i < json.length; i++) {
    final n = i + 1;
    final raw = json[i];
    if (raw is! Map) throw FormatException('part $n is not an object');
    final title = raw['title'];
    final body = raw['body'];
    final deps = raw['depends_on'] ?? const [];
    final manual = raw['manual'] ?? false;
    if (title is! String || title.trim().isEmpty) {
      throw FormatException('part $n has no title');
    }
    if (title.contains('\n') || title.length > _maxTitle) {
      throw FormatException(
        'part $n title must be one line of at most $_maxTitle characters',
      );
    }
    if (!titles.add(title.trim().toLowerCase())) {
      throw FormatException('part $n repeats the title "$title"');
    }
    if (body is! String || body.trim().isEmpty) {
      throw FormatException('part $n has no body');
    }
    if (body.length > _maxBody) {
      throw FormatException('part $n body is longer than $_maxBody characters');
    }
    if (manual is! bool) throw FormatException('part $n manual is not a bool');
    if (deps is! List || deps.any((d) => d is! int)) {
      throw FormatException('part $n depends_on must be a list of integers');
    }
    // Only earlier parts: this keeps the plan acyclic and the creation order
    // valid (a dependency's issue number exists when its dependant is made).
    for (final d in deps.cast<int>()) {
      if (d < 1 || d >= n) {
        throw FormatException(
          'part $n depends on $d; it may only depend on parts 1 to ${n - 1}',
        );
      }
    }
    parts.add(
      Part(
        title: title.trim(),
        body: body.trim(),
        dependsOn: deps.cast<int>().toSet().toList()..sort(),
        manual: manual,
      ),
    );
  }
  return parts;
}

/// The proposal comment posted to the parent issue.
String renderProposal(List<Part> parts) {
  final b = StringBuffer()
    ..writeln(splitMarker)
    ..writeln('## Proposed split')
    ..writeln()
    ..writeln(
      'Research found this issue too large for one reviewable pull request '
      'and proposes these sub-issues:',
    )
    ..writeln()
    ..writeln('| # | Sub-issue | Depends on | Pipeline |')
    ..writeln('|---|---|---|---|');
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    final deps = p.dependsOn.isEmpty ? '' : p.dependsOn.join(', ');
    final mode = p.manual ? 'maintainer (`ai:manual`)' : 'AI';
    b.writeln('| ${i + 1} | ${_cell(p.title)} | $deps | $mode |');
  }
  b
    ..writeln()
    ..writeln(
      'To accept, add `split:approved`: the pipeline creates the sub-issues, '
      'links them to this one, and labels this issue `ai:tracking`. Each '
      'sub-issue then goes through its own Gate 1 (`ai:approved`). To change '
      'the parts first, edit the JSON below. To implement as a single PR '
      'instead, remove `split:review` and add `ai:retry`.',
    )
    ..writeln()
    ..writeln('<details><summary>Plan (JSON)</summary>')
    ..writeln()
    ..writeln('```json')
    ..writeln(
      const JsonEncoder.withIndent('  ')
          .convert([for (final p in parts) p.toJson()]),
    )
    ..writeln('```')
    ..writeln()
    ..writeln('</details>');
  return b.toString();
}

/// Reads the plan back from a proposal comment.
List<Part> parseProposal(String comment) {
  if (!comment.trimLeft().startsWith(splitMarker)) {
    throw const FormatException('not a split proposal comment');
  }
  final m = RegExp(r'```json\s*\n([\s\S]*?)\n```').firstMatch(comment);
  if (m == null) throw const FormatException('proposal has no JSON block');
  final Object? json;
  try {
    json = jsonDecode(m.group(1)!);
  } on FormatException catch (e) {
    throw FormatException('proposal JSON is invalid: ${e.message}');
  }
  final parts = parsePlan(json);
  if (parts.isEmpty) throw const FormatException('proposal has no parts');
  return parts;
}

String _cell(String s) => s.replaceAll('|', r'\|');
