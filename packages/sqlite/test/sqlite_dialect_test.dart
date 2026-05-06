import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_sqlite/conduit_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('SqliteSqlDialect', () {
    const d = SqliteSqlDialect();

    test('overrides parameter placeholder to :name', () {
      expect(d.parameterPlaceholder('foo'), ':foo');
    });

    test('column types map to SQLite storage classes', () {
      expect(d.columnDefinitionType('integer', autoincrement: false), 'INTEGER');
      expect(d.columnDefinitionType('integer', autoincrement: true), 'INTEGER');
      expect(d.columnDefinitionType('bigInteger', autoincrement: false), 'INTEGER');
      expect(d.columnDefinitionType('string', autoincrement: false), 'TEXT');
      expect(d.columnDefinitionType('datetime', autoincrement: false), 'TEXT');
      expect(d.columnDefinitionType('boolean', autoincrement: false), 'INTEGER');
      expect(d.columnDefinitionType('double', autoincrement: false), 'REAL');
      expect(d.columnDefinitionType('document', autoincrement: false), 'TEXT');
      expect(d.columnDefinitionType('unknownType', autoincrement: false), isNull);
    });

    test('LIKE is the only matching operator', () {
      expect(d.caseSensitiveLikeOperator, 'LIKE');
      expect(d.caseInsensitiveLikeOperator, 'LIKE');
    });

    test('IS NULL uses standard SQL form', () {
      expect(d.isNullOperator, 'IS NULL');
      expect(d.isNotNullOperator, 'IS NOT NULL');
    });

    test('alter-table form is the standard ALTER TABLE', () {
      expect(d.alterTableForConstraintModification, 'ALTER TABLE');
    });

    test('version table is suffixed with backend name', () {
      expect(d.versionTableName, '_conduit_version_sqlite');
    });

    test('table-existence query reads sqlite_master', () {
      expect(d.tableExistsQuery(), contains('sqlite_master'));
      expect(d.tableExistsQuery(), contains(':tableName'));
    });
  });

  group('SqliteSchemaGenerator', () {
    final gen = _Gen();

    test('createTable emits INTEGER PRIMARY KEY for auto-incremented PK', () {
      final t = SchemaTable('users', [
        SchemaColumn.empty()
          ..name = 'id'
          ..type = ManagedPropertyType.integer
          ..isPrimaryKey = true
          ..autoincrement = true
          ..isNullable = false
          ..isIndexed = false
          ..isUnique = false,
      ]);
      final cmds = gen.createTable(t);
      expect(cmds, hasLength(1));
      expect(cmds.first, contains('CREATE TABLE users'));
      expect(cmds.first, contains('id INTEGER PRIMARY KEY'));
    });

    test('createTable emits NOT NULL for non-nullable non-PK', () {
      final t = SchemaTable('users', [
        SchemaColumn.empty()
          ..name = 'id'
          ..type = ManagedPropertyType.integer
          ..isPrimaryKey = true
          ..autoincrement = true
          ..isNullable = false
          ..isIndexed = false
          ..isUnique = false,
        SchemaColumn.empty()
          ..name = 'email'
          ..type = ManagedPropertyType.string
          ..isPrimaryKey = false
          ..autoincrement = false
          ..isNullable = false
          ..isIndexed = true
          ..isUnique = true,
      ]);
      final cmds = gen.createTable(t);
      expect(cmds.first, contains('email TEXT NOT NULL UNIQUE'));
      // Index command emitted separately (only non-PK indexed columns).
      expect(cmds.length, 2);
      expect(cmds.last, contains('CREATE INDEX users_email_idx ON users (email)'));
    });

    test('alterColumnNullability throws (table-rebuild not implemented)', () {
      final t = SchemaTable('users', [
        SchemaColumn.empty()
          ..name = 'email'
          ..type = ManagedPropertyType.string
          ..isPrimaryKey = false
          ..autoincrement = false
          ..isNullable = true
          ..isIndexed = false
          ..isUnique = false,
      ]);
      expect(
        () => gen.alterColumnNullability(t, t.columns.first, null),
        throwsUnsupportedError,
      );
    });

    test('renameColumn uses SQLite ALTER TABLE RENAME COLUMN', () {
      final t = SchemaTable('users', [
        SchemaColumn.empty()
          ..name = 'email'
          ..type = ManagedPropertyType.string
          ..isPrimaryKey = false
          ..autoincrement = false
          ..isNullable = true
          ..isIndexed = false
          ..isUnique = false,
      ]);
      final cmds = gen.renameColumn(t, t.columns.first, 'address');
      expect(cmds, hasLength(1));
      expect(cmds.first, 'ALTER TABLE users RENAME COLUMN email TO address');
    });
  });

  group('SqlitePersistentStore (in-memory)', () {
    late SqlitePersistentStore store;

    setUp(() {
      store = SqlitePersistentStore.memory();
    });

    tearDown(() async {
      await store.close();
    });

    test('execute creates a table and round-trips data', () async {
      await store.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, n TEXT)');
      await store.execute(
        'INSERT INTO t (n) VALUES (:n)',
        substitutionValues: {'n': 'alice'},
      );
      // sqlite3's ResultSet.rows is List<List<Object?>>; positional
      // access matches the PostgreSQL store's `mappedRows` shape so the
      // surface is uniform.
      final rows = await store.execute('SELECT n FROM t') as List;
      expect(rows, hasLength(1));
      expect(rows.first[0], 'alice');
    });

    // newQuery's throwsUnimplementedError contract is documented in the
    // source and asserted by the type system (the override exists). A
    // direct test would require constructing a ManagedDataModel + entity,
    // which is heavier than the contract is worth at this layer; skip
    // here, cover end-to-end once the ORM path is wired.

    test('schemaVersion returns 0 when version table missing', () async {
      expect(await store.schemaVersion, 0);
    });

    test('transaction commits on success', () async {
      await store.execute('CREATE TABLE t (n INTEGER)');
      await store.transaction(
        ManagedContext(ManagedDataModel(const []), store),
        (txn) async {
          await store.execute(
            'INSERT INTO t (n) VALUES (:n)',
            substitutionValues: {'n': 1},
          );
          await store.execute(
            'INSERT INTO t (n) VALUES (:n)',
            substitutionValues: {'n': 2},
          );
        },
      );
      final rows = await store.execute('SELECT count(*) FROM t') as List;
      expect(rows.first[0], 2);
    });

    test('transaction rolls back on Rollback', () async {
      await store.execute('CREATE TABLE t (n INTEGER)');
      await expectLater(
        store.transaction(
          ManagedContext(ManagedDataModel(const []), store),
          (txn) async {
            await store.execute(
              'INSERT INTO t (n) VALUES (:n)',
              substitutionValues: {'n': 1},
            );
            throw Rollback('user-triggered');
          },
        ),
        throwsA(isA<Rollback>()),
      );
      final rollbackRows =
          await store.execute('SELECT count(*) FROM t') as List;
      expect(rollbackRows.first[0], 0);
    });
  });
}

/// Bare adapter so test cases can call mixin methods without instantiating
/// a full SqlitePersistentStore.
class _Gen with SqliteSchemaGenerator {}
