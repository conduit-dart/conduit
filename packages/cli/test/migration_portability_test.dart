/// Verifies the Phase 5 portability claim: `Migration.sourceForSchemaUpgrade`
/// emits pure Dart `SchemaBuilder` calls — no dialect-specific SQL. This is
/// what makes `conduit db generate` output portable across the
/// postgres/sqlite/mysql backends.
library;

import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

void main() {
  test('generated migration source contains no SQL dialect tokens', () {
    final newSchema = Schema([
      SchemaTable('widgets', [
        SchemaColumn(
          'id',
          ManagedPropertyType.bigInteger,
          isPrimaryKey: true,
          autoincrement: true,
        ),
        SchemaColumn('name', ManagedPropertyType.string),
        SchemaColumn('weight', ManagedPropertyType.integer, isNullable: true),
      ]),
    ]);

    final source = Migration.sourceForSchemaUpgrade(
      Schema.empty(),
      newSchema,
      1,
    );

    // The source should exclusively be SchemaBuilder.* calls. SQL DDL
    // strings (CREATE TABLE, INSERT INTO, SERIAL, AUTO_INCREMENT, etc.)
    // are emitted only when a SchemaBuilder is constructed with a
    // store, which the generator does not do. We check for multi-word
    // tokens to avoid false positives on parameter names like
    // `autoincrement:`.
    final dialectTokens = [
      'CREATE TABLE',
      'INSERT INTO',
      'BIGSERIAL',
      'AUTO_INCREMENT',
      'PRIMARY KEY',
      'INTEGER NOT NULL',
      'NOT NULL',
    ];
    for (final tok in dialectTokens) {
      expect(source.toUpperCase(), isNot(contains(tok.toUpperCase())),
          reason: 'unexpected dialect token "$tok" in generated migration');
    }

    // Sanity: the generated migration is actually invoking the
    // SchemaBuilder API (via the `database` field on `Migration`) and
    // names the version class.
    expect(source, contains('database.createTable'));
    expect(source, contains('Migration1'));
    expect(source, contains('SchemaTable'));
  });
}
