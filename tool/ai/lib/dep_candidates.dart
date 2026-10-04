/// Vets dependency candidates for the AI pipeline against pub.dev.
///
/// The research agent only *names* candidate packages. Every fact in the
/// comparison posted to the issue (version, publish date, license, SDK
/// constraint, points, likes, downloads, publisher) comes from the pub.dev
/// API, never from the model. A name the model invents shows up as
/// "not found on pub.dev" instead of as a recommendation.
library;

import 'dart:convert';

import 'package:pub_semver/pub_semver.dart';

/// Marks the issue comment that carries the candidate checklist, so the
/// implementation stage can find it and read the maintainer's choice.
const candidatesMarker = '<!-- conduit-ai:deps-candidates -->';

/// Option a maintainer ticks to implement without a new dependency.
const inHouseOption = 'in-house';

/// Licenses compatible with conduit's posture (BSD upstream packages, MIT
/// new packages; see license-audit.md). Anything else is excluded.
const permissiveLicenses = {
  'mit',
  'bsd-2-clause',
  'bsd-3-clause',
  'apache-2.0',
  'isc',
  'zlib',
  '0bsd',
};

/// Fetches a pub.dev API path (e.g. `/api/packages/http`) and returns the
/// decoded JSON, or `null` when the package does not exist (HTTP 404).
typedef PubFetcher = Future<Map<String, dynamic>?> Function(String path);

/// pub.dev facts about one package, plus the eligibility verdict.
class Candidate {
  new({
    required this.name,
    this.version,
    this.published,
    this.sdkConstraint,
    this.licenses = const [],
    this.publisher,
    this.grantedPoints,
    this.maxPoints,
    this.likes,
    this.downloads30Days,
    this.discontinued = false,
    this.found = true,
    this.exclusions = const [],
  });

  final String name;
  final String? version;
  final DateTime? published;
  final String? sdkConstraint;
  final List<String> licenses;
  final String? publisher;
  final int? grantedPoints;
  final int? maxPoints;
  final int? likes;
  final int? downloads30Days;
  final bool discontinued;
  final bool found;

  /// Why the candidate is not eligible; empty when it is.
  final List<String> exclusions;

  bool get eligible => found && exclusions.isEmpty;
}

/// Looks up [name] on pub.dev and applies the eligibility rules.
///
/// A candidate is excluded when it is missing, discontinued, has had no
/// release within [maxAge] of [now], has no permissive license, or its
/// latest version's SDK constraint does not allow [sdkFloor].
Future<Candidate> evaluate(
  String name, {
  required PubFetcher fetch,
  required DateTime now,
  required Version sdkFloor,
  Duration maxAge = const Duration(days: 365),
}) async {
  final info = await fetch('/api/packages/$name');
  if (info == null) {
    return Candidate(
      name: name,
      found: false,
      exclusions: const ['not found on pub.dev'],
    );
  }
  final score = await fetch('/api/packages/$name/score') ?? const {};

  final latest = info['latest'] as Map<String, dynamic>? ?? const {};
  final pubspec = latest['pubspec'] as Map<String, dynamic>? ?? const {};
  final environment =
      pubspec['environment'] as Map<String, dynamic>? ?? const {};
  final tags = (score['tags'] as List<dynamic>? ?? const []).cast<String>();

  final licenses = [
    for (final t in tags)
      if (t.startsWith('license:')) t.substring('license:'.length),
  ];
  final publisher = tags
      .where((t) => t.startsWith('publisher:'))
      .map((t) => t.substring('publisher:'.length))
      .firstOrNull;
  final published = DateTime.tryParse(latest['published'] as String? ?? '');
  final sdkConstraint = environment['sdk'] as String?;
  final discontinued = info['isDiscontinued'] == true;

  final exclusions = <String>[
    if (discontinued)
      'discontinued'
          '${info['replacedBy'] != null ? ' (replaced by ${info['replacedBy']})' : ''}',
    if (published == null)
      'no publish date'
    else if (now.difference(published) > maxAge)
      'no release in ${maxAge.inDays} days (last ${_date(published)})',
    if (!licenses.any(permissiveLicenses.contains))
      'license not permissive (${licenses.isEmpty ? 'unknown' : licenses.join(', ')})',
    if (!_allowsSdk(sdkConstraint, sdkFloor))
      'SDK constraint ${sdkConstraint ?? '(none)'} does not allow $sdkFloor',
  ];

  return Candidate(
    name: name,
    version: latest['version'] as String?,
    published: published,
    sdkConstraint: sdkConstraint,
    licenses: licenses,
    publisher: publisher,
    grantedPoints: score['grantedPoints'] as int?,
    maxPoints: score['maxPoints'] as int?,
    likes: score['likeCount'] as int?,
    downloads30Days: score['downloadCount30Days'] as int?,
    discontinued: discontinued,
    exclusions: exclusions,
  );
}

bool _allowsSdk(String? constraint, Version floor) {
  if (constraint == null) return false;
  try {
    return VersionConstraint.parse(constraint).allows(floor);
  } on FormatException {
    return false;
  }
}

String _date(DateTime d) => d.toIso8601String().substring(0, 10);

/// Renders the issue comment: a comparison table of eligible candidates, a
/// checklist for the maintainer (Gate 2), and the excluded candidates with
/// reasons. [rationale] maps package names to the agent's one-line reason
/// for proposing them; it is labelled as model output.
String renderComment(
  List<Candidate> candidates, {
  required Version sdkFloor,
  Map<String, String> rationale = const {},
}) {
  final eligible = candidates.where((c) => c.eligible).toList();
  final excluded = candidates.where((c) => !c.eligible).toList();
  final b = StringBuffer()
    ..writeln(candidatesMarker)
    ..writeln('## Dependency candidates')
    ..writeln()
    ..writeln(
      'The facts below come from the pub.dev API. Only the "Why" column '
      'is model output. Eligibility: on pub.dev, not discontinued, '
      'released within 12 months, permissive license, SDK constraint '
      'allows Dart $sdkFloor.',
    )
    ..writeln();

  if (eligible.isNotEmpty) {
    b
      ..writeln(
        '| Package | Version | Released | License | Publisher | Points | Likes | Downloads (30d) | Why |',
      )
      ..writeln('|---|---|---|---|---|---|---|---|---|');
    for (final c in eligible) {
      b.writeln(
        '| [`${c.name}`](https://pub.dev/packages/${c.name}) '
        '| ${c.version} '
        '| ${_date(c.published!)} '
        '| ${c.licenses.where(permissiveLicenses.contains).join(', ')} '
        '| ${c.publisher ?? 'unverified'} '
        '| ${c.grantedPoints ?? '?'}/${c.maxPoints ?? '?'} '
        '| ${c.likes ?? '?'} '
        '| ${c.downloads30Days ?? '?'} '
        '| ${_cell(rationale[c.name])} |',
      );
    }
    b.writeln();
  } else {
    b
      ..writeln('No proposed package passed the eligibility checks.')
      ..writeln();
  }

  b
    ..writeln('### Choose one (maintainer)')
    ..writeln()
    ..writeln(
      'Tick exactly one box, then add the `deps:approved` label to start '
      'implementation.',
    )
    ..writeln();
  for (final c in eligible) {
    b.writeln('- [ ] `${c.name}`');
  }
  b
    ..writeln('- [ ] `$inHouseOption` (no new dependency)')
    ..writeln();

  if (excluded.isNotEmpty) {
    b
      ..writeln('<details><summary>Excluded candidates</summary>')
      ..writeln();
    for (final c in excluded) {
      b.writeln('- `${c.name}`: ${c.exclusions.join('; ')}');
    }
    b
      ..writeln()
      ..writeln('</details>');
  }
  return b.toString();
}

String _cell(String? s) =>
    (s ?? '').replaceAll('|', r'\|').replaceAll('\n', ' ').trim();

/// Reads the maintainer's choice from a candidates comment body.
///
/// Returns the ticked package name (or [inHouseOption]). Throws
/// [FormatException] unless exactly one box is ticked.
String parseChoice(String commentBody) {
  final ticked = RegExp(
    r'^- \[[xX]\] `([^`]+)`',
    multiLine: true,
  ).allMatches(commentBody).map((m) => m.group(1)!).toList();
  if (ticked.length != 1) {
    throw FormatException(
      'expected exactly one ticked option, found ${ticked.length}',
    );
  }
  return ticked.single;
}

/// Parses a `{"name": "reason", ...}` rationale file written by the agent.
Map<String, String> parseRationale(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map) return const {};
  return {
    for (final e in decoded.entries)
      if (e.key is String && e.value is String)
        e.key as String: e.value as String,
  };
}
