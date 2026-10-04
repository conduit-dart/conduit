import 'dart:convert';
import 'dart:io';

import 'package:conduit_ai_tool/dep_candidates.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

// `http` and `dio` are recorded pub.dev responses (2026-10-04). The other
// packages are synthetic, built to hit one exclusion rule each.
final now = DateTime.utc(2026, 10, 4);
final floor = Version(3, 13, 0);

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> _pkg({
  required String version,
  required String published,
  String? sdk = '^3.0.0',
  bool discontinued = false,
  String? replacedBy,
}) => {
  'isDiscontinued': discontinued,
  'replacedBy': replacedBy,
  'latest': {
    'version': version,
    'published': published,
    'pubspec': {
      'environment': {'sdk': ?sdk},
    },
  },
};

Map<String, dynamic> _score(List<String> tags) => {
  'grantedPoints': 140,
  'maxPoints': 160,
  'likeCount': 10,
  'downloadCount30Days': 1000,
  'tags': tags,
};

final synthetic = <String, Map<String, dynamic>>{
  '/api/packages/stale_pkg': _pkg(
    version: '1.0.0',
    published: '2024-01-01T00:00:00Z',
  ),
  '/api/packages/stale_pkg/score': _score(['license:mit']),
  '/api/packages/gpl_pkg': _pkg(
    version: '2.0.0',
    published: '2026-09-01T00:00:00Z',
  ),
  '/api/packages/gpl_pkg/score': _score(['license:gpl-3.0']),
  '/api/packages/old_sdk_pkg': _pkg(
    version: '0.9.0',
    published: '2026-08-01T00:00:00Z',
    sdk: '>=2.12.0 <3.0.0',
  ),
  '/api/packages/old_sdk_pkg/score': _score(['license:bsd-3-clause']),
  '/api/packages/gone_pkg': _pkg(
    version: '3.0.0',
    published: '2026-08-01T00:00:00Z',
    discontinued: true,
    replacedBy: 'new_pkg',
  ),
  '/api/packages/gone_pkg/score': _score(['license:mit']),
};

Future<Map<String, dynamic>?> fetch(String path) async {
  for (final name in ['http', 'dio']) {
    if (path == '/api/packages/$name') return _fixture(name);
    if (path == '/api/packages/$name/score') return _fixture('$name.score');
  }
  return synthetic[path];
}

Future<Candidate> eval(String name) =>
    evaluate(name, fetch: fetch, now: now, sdkFloor: floor);

void main() {
  group('evaluate', () {
    test('recorded http passes every rule, facts come from the API', () async {
      final c = await eval('http');
      expect(c.eligible, isTrue, reason: '${c.exclusions}');
      expect(c.version, '1.6.0');
      expect(c.sdkConstraint, '^3.4.0');
      expect(c.licenses, contains('bsd-3-clause'));
      expect(c.publisher, 'dart.dev');
      expect(c.grantedPoints, 160);
    });

    test('recorded dio passes (MIT, wide SDK range)', () async {
      final c = await eval('dio');
      expect(c.eligible, isTrue, reason: '${c.exclusions}');
      expect(c.licenses, contains('mit'));
    });

    test('a name pub.dev does not know is excluded, not invented', () async {
      final c = await eval('made_up_by_the_model');
      expect(c.found, isFalse);
      expect(c.eligible, isFalse);
      expect(c.exclusions, ['not found on pub.dev']);
      expect(c.version, isNull);
    });

    test('no release in 12 months is excluded', () async {
      final c = await eval('stale_pkg');
      expect(c.eligible, isFalse);
      expect(c.exclusions.single, contains('no release in 365 days'));
    });

    test('copyleft license is excluded', () async {
      final c = await eval('gpl_pkg');
      expect(c.exclusions.single, contains('license not permissive (gpl-3.0)'));
    });

    test('SDK constraint that rejects the floor is excluded', () async {
      final c = await eval('old_sdk_pkg');
      expect(c.exclusions.single, contains('does not allow 3.13.0'));
    });

    test('discontinued package is excluded with its replacement', () async {
      final c = await eval('gone_pkg');
      expect(c.exclusions.single, 'discontinued (replaced by new_pkg)');
    });

    test('missing SDK constraint is excluded', () async {
      final c = await evaluate(
        'x',
        fetch: (p) async => p.endsWith('/score')
            ? _score(['license:mit'])
            : _pkg(
                version: '1.0.0',
                published: '2026-09-01T00:00:00Z',
                sdk: null,
              ),
        now: now,
        sdkFloor: floor,
      );
      expect(c.exclusions.single, contains('SDK constraint (none)'));
    });
  });

  group('renderComment', () {
    test(
      'lists eligible candidates as options and explains exclusions',
      () async {
        final candidates = [
          await eval('http'),
          await eval('gpl_pkg'),
          await eval('made_up_by_the_model'),
        ];
        final body = renderComment(
          candidates,
          sdkFloor: floor,
          rationale: {'http': 'first-party | maintained'},
        );
        expect(body, startsWith(candidatesMarker));
        expect(
          body,
          contains(
            '| [`http`](https://pub.dev/packages/http) | 1.6.0 | 2025-11-10 |',
          ),
        );
        expect(body, contains(r'first-party \| maintained'));
        expect(body, contains('- [ ] `http`'));
        expect(body, contains('- [ ] `in-house` (no new dependency)'));
        expect(body, isNot(contains('- [ ] `gpl_pkg`')));
        expect(body, contains('- `gpl_pkg`: license not permissive'));
        expect(
          body,
          contains('- `made_up_by_the_model`: not found on pub.dev'),
        );
      },
    );

    test('with nothing eligible, only the in-house option remains', () async {
      final body = renderComment([await eval('stale_pkg')], sdkFloor: floor);
      expect(body, contains('No proposed package passed'));
      expect(RegExp(r'^- \[ \]', multiLine: true).allMatches(body).length, 1);
    });
  });

  group('parseChoice', () {
    test('reads the single ticked option', () {
      expect(parseChoice('- [ ] `http`\n- [x] `dio`\n- [ ] `in-house`'), 'dio');
      expect(
        parseChoice('- [X] `in-house` (no new dependency)'),
        inHouseOption,
      );
    });

    test('rejects zero or several ticks', () {
      expect(() => parseChoice('- [ ] `http`'), throwsFormatException);
      expect(
        () => parseChoice('- [x] `http`\n- [x] `dio`'),
        throwsFormatException,
      );
    });
  });

  group('parseRationale', () {
    test('keeps string entries, ignores the rest', () {
      expect(parseRationale('{"http": "ok", "n": 3}'), {'http': 'ok'});
      expect(parseRationale('[]'), isEmpty);
    });
  });
}
