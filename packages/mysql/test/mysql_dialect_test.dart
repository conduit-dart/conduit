import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_mysql/conduit_mysql.dart';
import 'package:test/test.dart';

void main() {
  group('MysqlSqlDialect', () {
    const d = MysqlSqlDialect();

    test('name is "mysql"', () {
      expect(d.name, 'mysql');
    });

    test('parameter style is positional', () {
      expect(d.parameterStyle, SqlParameterStyle.positional);
    });

    test('parameter placeholder uses :name (driver rewrites to ? internally)',
        () {
      expect(d.parameterPlaceholder('foo'), ':foo');
      expect(d.parameterPlaceholder('whatever'), ':whatever');
    });

    test('column types map to MySQL-flavored DDL', () {
      expect(d.columnDefinitionType('integer', autoincrement: false), 'INT');
      expect(d.columnDefinitionType('integer', autoincrement: true),
          'INT AUTO_INCREMENT');
      expect(d.columnDefinitionType('bigInteger', autoincrement: false),
          'BIGINT');
      expect(d.columnDefinitionType('bigInteger', autoincrement: true),
          'BIGINT AUTO_INCREMENT');
      expect(d.columnDefinitionType('string', autoincrement: false),
          'VARCHAR(255)');
      expect(d.columnDefinitionType('datetime', autoincrement: false),
          'DATETIME');
      expect(d.columnDefinitionType('boolean', autoincrement: false),
          'BOOLEAN');
      expect(d.columnDefinitionType('double', autoincrement: false), 'DOUBLE');
      expect(d.columnDefinitionType('document', autoincrement: false), 'JSON');
      expect(d.columnDefinitionType('unknownType', autoincrement: false),
          isNull);
    });

    test('case-sensitive LIKE uses LIKE BINARY', () {
      expect(d.caseSensitiveLikeOperator, 'LIKE BINARY');
    });

    test('case-insensitive LIKE collapses to LIKE (collation-driven)', () {
      expect(d.caseInsensitiveLikeOperator, 'LIKE');
    });

    test('IS NULL uses standard SQL form', () {
      expect(d.isNullOperator, 'IS NULL');
      expect(d.isNotNullOperator, 'IS NOT NULL');
    });

    test('alter-table form is the standard ALTER TABLE', () {
      expect(d.alterTableForConstraintModification, 'ALTER TABLE');
    });

    test('version-table name is suffixed with "mysql"', () {
      expect(d.versionTableName, '_conduit_version_mysql');
    });

    test('table-existence query reads information_schema.tables', () {
      final q = d.tableExistsQuery();
      expect(q, contains('information_schema.tables'));
      expect(q, contains('table_schema = DATABASE()'));
      expect(q, contains(':tableName'));
    });

    test('LIKE pattern escaping protects %, _, and \\', () {
      // Inherited default escaping. Documented as MySQL-compatible.
      expect(d.escapeLikePattern('100%'), r'100\%');
      expect(d.escapeLikePattern('a_b'), r'a\_b');
      expect(d.escapeLikePattern(r'c\d'), r'c\\d');
    });
  });

  group('MysqlSqlDialect AST rendering', () {
    const d = MysqlSqlDialect();

    test('comparison renders as ? and binds positionally', () {
      final r = d.renderExpression(
        BinaryOpExpression(
          '=',
          ColumnExpression('id', tableNamespace: 'users'),
          ParameterExpression('id_v', 42),
        ),
      );
      expect(r.sql, 'users.id = ?');
      expect(r.positionalParameters, [42]);
      expect(r.parameters, isEmpty);
    });

    test('AND combinator preserves positional ordering', () {
      final r = d.renderExpression(
        LogicalExpression('AND', [
          BinaryOpExpression('=', ColumnExpression('a'),
              ParameterExpression('av', 1)),
          BinaryOpExpression('<', ColumnExpression('b'),
              ParameterExpression('bv', 99)),
        ]),
      );
      expect(r.sql, '(a = ? AND b < ?)');
      expect(r.positionalParameters, [1, 99]);
    });

    test('IN expands to (?,?,?) and binds in order', () {
      final r = d.renderExpression(
        InExpression(
          ColumnExpression('id'),
          [
            ParameterExpression('a', 10),
            ParameterExpression('b', 20),
            ParameterExpression('c', 30),
          ],
        ),
      );
      expect(r.sql, 'id IN (?,?,?)');
      expect(r.positionalParameters, [10, 20, 30]);
    });

    test('LIKE BINARY emitted for case-sensitive string match', () {
      final r = d.renderExpression(
        LikeExpression(
          ColumnExpression('name'),
          ParameterExpression('p', 'Foo%'),
          caseSensitive: true,
        ),
      );
      expect(r.sql, 'name LIKE BINARY ?');
      expect(r.positionalParameters, ['Foo%']);
    });

    test('LIKE (no BINARY) for case-insensitive', () {
      final r = d.renderExpression(
        LikeExpression(
          ColumnExpression('name'),
          ParameterExpression('p', 'foo%'),
          caseSensitive: false,
        ),
      );
      expect(r.sql, 'name LIKE ?');
    });

    test('IS NULL renders without binding', () {
      final r = d.renderExpression(
        IsNullExpression(ColumnExpression('email')),
      );
      expect(r.sql, 'email IS NULL');
      expect(r.positionalParameters, isEmpty);
    });

    test('BETWEEN binds low then high', () {
      final r = d.renderExpression(
        BetweenExpression(
          ColumnExpression('n'),
          ParameterExpression('lo', 5),
          ParameterExpression('hi', 10),
        ),
      );
      expect(r.sql, 'n BETWEEN ? AND ?');
      expect(r.positionalParameters, [5, 10]);
    });
  });

  group('MysqlSchemaGenerator', () {
    final gen = _Gen();

    test('createTable emits INT AUTO_INCREMENT for serial PK', () {
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
      expect(cmds.first, contains('id INT AUTO_INCREMENT PRIMARY KEY'));
    });

    test('createTable emits VARCHAR(255) for string columns', () {
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
      expect(cmds.first, contains('email VARCHAR(255) NOT NULL UNIQUE'));
      // The indexed + non-PK column also generates an index command.
      expect(cmds.length, 2);
      expect(cmds.last, contains('CREATE INDEX users_email_idx ON users (email)'));
    });

    test('createTable emits BIGINT AUTO_INCREMENT for bigInteger serial', () {
      final t = SchemaTable('events', [
        SchemaColumn.empty()
          ..name = 'id'
          ..type = ManagedPropertyType.bigInteger
          ..isPrimaryKey = true
          ..autoincrement = true
          ..isNullable = false
          ..isIndexed = false
          ..isUnique = false,
      ]);
      final cmds = gen.createTable(t);
      expect(cmds.first, contains('id BIGINT AUTO_INCREMENT PRIMARY KEY'));
    });

    test('createTable emits JSON for document type', () {
      final t = SchemaTable('events', [
        SchemaColumn.empty()
          ..name = 'id'
          ..type = ManagedPropertyType.integer
          ..isPrimaryKey = true
          ..autoincrement = true
          ..isNullable = false
          ..isIndexed = false
          ..isUnique = false,
        SchemaColumn.empty()
          ..name = 'payload'
          ..type = ManagedPropertyType.document
          ..isPrimaryKey = false
          ..autoincrement = false
          ..isNullable = true
          ..isIndexed = false
          ..isUnique = false,
      ]);
      final cmds = gen.createTable(t);
      expect(cmds.first, contains('payload JSON NULL'));
    });

    test('renameColumn emits RENAME COLUMN', () {
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

    test('renameTable uses RENAME TABLE', () {
      final t = SchemaTable('a', const []);
      final cmds = gen.renameTable(t, 'b');
      expect(cmds, ['RENAME TABLE a TO b']);
    });

    test('alterColumnNullability uses MODIFY COLUMN with full type', () {
      final t = SchemaTable('users', [
        SchemaColumn.empty()
          ..name = 'email'
          ..type = ManagedPropertyType.string
          ..isPrimaryKey = false
          ..autoincrement = false
          ..isNullable = false
          ..isIndexed = false
          ..isUnique = false,
      ]);
      final cmds = gen.alterColumnNullability(t, t.columns.first, null);
      expect(cmds, hasLength(1));
      expect(cmds.first, contains('MODIFY COLUMN email VARCHAR(255) NOT NULL'));
    });

    test('deleteIndexFromColumn uses DROP INDEX ... ON table', () {
      final t = SchemaTable('users', [
        SchemaColumn.empty()
          ..name = 'email'
          ..type = ManagedPropertyType.string
          ..isPrimaryKey = false
          ..autoincrement = false
          ..isNullable = true
          ..isIndexed = true
          ..isUnique = false,
      ]);
      final cmds = gen.deleteIndexFromColumn(t, t.columns.first);
      expect(cmds, ['DROP INDEX users_email_idx ON users']);
    });
  });
}

/// Bare adapter so tests can call mixin methods without instantiating
/// a real MysqlPersistentStore (which would attempt a TCP connect).
class _Gen with MysqlSchemaGenerator {}
