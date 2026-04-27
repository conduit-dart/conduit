// Unit tests for `MigrationSource.fromFile`. The factory parses a
// migration file, locates the single `extends Migration` class, and
// produces a `MigrationSource` with a hashed-name copy of its source.
//
// Regression: github.com/conduit-dart/conduit/issues/213 — adding a
// docstring to the migration class made the offset arithmetic
// over-run `klass.toSource()` and threw RangeError.
import 'dart:io';

import 'package:conduit/src/migration_source.dart';
import 'package:test/test.dart';

late Directory tmp;

Uri _writeMigration(String content) {
  final file = File('${tmp.path}/${DateTime.now().microsecondsSinceEpoch}.dart');
  file.writeAsStringSync(content);
  return file.uri;
}

void main() {
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('conduit_migration_source_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('parses a plain migration class', () {
    final uri = _writeMigration('''
import 'dart:async';
import 'package:conduit_core/conduit_core.dart';

class Migration1 extends Migration {
  @override
  Future upgrade() async {}
  @override
  Future downgrade() async {}
  @override
  Future seed() async {}
}
''');

    final src = MigrationSource.fromFile(uri);
    expect(src.originalName, equals('Migration1'));
    expect(src.source, isNot(contains('Migration1 extends')));
    expect(src.source, contains('${src.name} extends'));
  });

  test('parses a migration class with a doc-comment (regression #213)', () {
    final uri = _writeMigration('''
import 'dart:async';
import 'package:conduit_core/conduit_core.dart';

/// A nicely documented migration that adds users.
///
/// Multi-line doc comments used to throw RangeError because the
/// offset math in `MigrationSource.fromFile` confused file offsets
/// with `klass.toSource()` offsets.
class Migration1 extends Migration {
  @override
  Future upgrade() async {}
  @override
  Future downgrade() async {}
  @override
  Future seed() async {}
}
''');

    // The bug manifested as RangeError thrown from `String.substring`.
    final src = MigrationSource.fromFile(uri);
    expect(src.originalName, equals('Migration1'));
    expect(src.source, isNot(contains('class Migration1 ')));
    expect(src.source, contains('class ${src.name} '));
  });

  test('parses a migration class with regular line comments above', () {
    final uri = _writeMigration('''
import 'dart:async';
import 'package:conduit_core/conduit_core.dart';

// One-line non-doc comment.
// Another one.
class Migration1 extends Migration {
  @override
  Future upgrade() async {}
  @override
  Future downgrade() async {}
  @override
  Future seed() async {}
}
''');

    final src = MigrationSource.fromFile(uri);
    expect(src.originalName, equals('Migration1'));
  });

  test('throws when the file has no Migration subclass', () {
    final uri = _writeMigration('''
class NotAMigration {}
''');
    expect(() => MigrationSource.fromFile(uri), throwsStateError);
  });
}
