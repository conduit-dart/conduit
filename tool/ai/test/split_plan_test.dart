import 'package:conduit_ai_tool/split_plan.dart';
import 'package:test/test.dart';

Map<String, Object?> part(String title, {List<int>? deps, bool? manual}) => {
  'title': title,
  'body': 'Deliver $title, with tests.',
  'depends_on': ?deps,
  'manual': ?manual,
};

void main() {
  group('parsePlan', () {
    test('null or an empty list means no split', () {
      expect(parsePlan(null), isEmpty);
      expect(parsePlan(<Object>[]), isEmpty);
    });

    test('reads parts with defaults, dedupes and sorts dependencies', () {
      final parts = parsePlan([
        part('CI image', manual: true),
        part('GeoPoint type'),
        part('Distance filter', deps: [2, 1, 2]),
      ]);
      expect(parts.map((p) => p.title), [
        'CI image',
        'GeoPoint type',
        'Distance filter',
      ]);
      expect(parts[0].manual, isTrue);
      expect(parts[1].manual, isFalse);
      expect(parts[1].dependsOn, isEmpty);
      expect(parts[2].dependsOn, [1, 2]);
    });

    test('rejects too few or too many parts', () {
      expect(() => parsePlan([part('a')]), throwsFormatException);
      expect(
        () => parsePlan([for (var i = 0; i < 7; i++) part('p$i')]),
        throwsFormatException,
      );
    });

    test('rejects forward, self and out-of-range dependencies', () {
      expect(
        () => parsePlan([
          part('a', deps: [2]),
          part('b'),
        ]),
        throwsFormatException,
      );
      expect(
        () => parsePlan([
          part('a'),
          part('b', deps: [2]),
        ]),
        throwsFormatException,
      );
      expect(
        () => parsePlan([
          part('a'),
          part('b', deps: [0]),
        ]),
        throwsFormatException,
      );
    });

    test('rejects missing, multi-line, long or duplicate titles', () {
      expect(
        () => parsePlan([
          part('a'),
          {'body': 'x'},
        ]),
        throwsFormatException,
      );
      expect(() => parsePlan([part('a'), part('b\nc')]), throwsFormatException);
      expect(
        () => parsePlan([part('a'), part('x' * 101)]),
        throwsFormatException,
      );
      expect(
        () => parsePlan([part('Same'), part('same')]),
        throwsFormatException,
      );
    });

    test('rejects a missing body and wrong field types', () {
      expect(
        () => parsePlan([
          part('a'),
          {'title': 'b', 'body': ' '},
        ]),
        throwsFormatException,
      );
      expect(
        () => parsePlan([
          part('a'),
          {...part('b'), 'manual': 'yes'},
        ]),
        throwsFormatException,
      );
      expect(
        () => parsePlan([
          part('a'),
          {
            ...part('b'),
            'depends_on': ['1'],
          },
        ]),
        throwsFormatException,
      );
      expect(() => parsePlan({'title': 'a'}), throwsFormatException);
    });
  });

  group('proposal comment', () {
    final parts = parsePlan([
      part('CI | PostGIS image', manual: true),
      part('GeoPoint type', deps: [1]),
    ]);

    test('renders a table and round-trips through the JSON block', () {
      final comment = renderProposal(parts);
      expect(comment, startsWith(splitMarker));
      expect(comment, contains(r'| 1 | CI \| PostGIS image |  | maintainer'));
      expect(comment, contains('| 2 | GeoPoint type | 1 | AI |'));
      final back = parseProposal(comment);
      expect(
        back.map((p) => p.toJson()).toList(),
        parts.map((p) => p.toJson()).toList(),
      );
    });

    test('reads a maintainer edit of the JSON block', () {
      final edited = renderProposal(parts)
          .replaceFirst('"GeoPoint type"', '"GeoPoint column type"');
      expect(parseProposal(edited)[1].title, 'GeoPoint column type');
    });

    test('rejects other comments, missing or broken JSON, and empty plans', () {
      expect(() => parseProposal('hello'), throwsFormatException);
      expect(
        () => parseProposal('$splitMarker\nno json'),
        throwsFormatException,
      );
      expect(
        () => parseProposal('$splitMarker\n```json\n[{\n```'),
        throwsFormatException,
      );
      expect(
        () => parseProposal('$splitMarker\n```json\n[]\n```'),
        throwsFormatException,
      );
    });
  });
}
