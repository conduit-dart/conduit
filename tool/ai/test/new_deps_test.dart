import 'package:conduit_ai_tool/new_deps.dart';
import 'package:test/test.dart';

const base = '''
name: conduit_core
dependencies:
  collection: ^1.17.0
  meta: ^1.9.0
dev_dependencies:
  test: ^1.25.2
''';

void main() {
  test('reads dependencies and dev_dependencies', () {
    expect(declaredDependencies(base), {'collection', 'meta', 'test'});
    expect(declaredDependencies('name: x\n'), isEmpty);
  });

  test('a version bump is not an added dependency', () {
    final after = base.replaceFirst('^1.17.0', '^1.19.0');
    expect(
      addedDependencies(
        {'packages/core/pubspec.yaml': base},
        {'packages/core/pubspec.yaml': after},
      ),
      isEmpty,
    );
  });

  test('reports additions per package and flags unapproved ones', () {
    final after = base.replaceFirst(
      '  meta: ^1.9.0\n',
      '  meta: ^1.9.0\n  dio: ^5.11.0\n  left_pad: ^1.0.0\n',
    );
    final added = addedDependencies(
      {'packages/core/pubspec.yaml': base},
      {'packages/core/pubspec.yaml': after},
    );
    expect(added, {
      'packages/core/pubspec.yaml': {'dio', 'left_pad'},
    });
    expect(unapproved(added, {'dio'}), {'left_pad'});
    expect(unapproved(added, {'dio', 'left_pad'}), isEmpty);
  });

  test('every dependency of a brand-new package counts as added', () {
    final added = addedDependencies({}, {'tool/x/pubspec.yaml': base});
    expect(added['tool/x/pubspec.yaml'], {'collection', 'meta', 'test'});
  });
}
