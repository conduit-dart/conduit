/// Unit-level tests for the dialect-agnostic [QueryBuilder] driven
/// by [MysqlSqlDialect]. These don't need a live MySQL — they
/// exercise the SQL fragments + parameter map shape produced by the
/// builder family for a MySQL-flavored dialect.
library;

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_mysql/conduit_mysql.dart';
import 'package:test/test.dart';

void main() {
  group('QueryBuilder + MysqlSqlDialect', () {
    late ManagedContext context;
    setUp(() {
      // Use a real MysqlPersistentStore but never connect — the
      // QueryBuilder path doesn't touch the wire, only the dialect
      // and the data model.
      final store = MysqlPersistentStore(
        'unused', 'unused', 'localhost', 13306, 'unused',
      );
      context = ManagedContext(ManagedDataModel([Simple]), store);
    });

    test('placeholders use :name (driver rewrites to ?)', () {
      final q = Query<Simple>(context)
        ..where((s) => s.id).equalTo(42);
      final builder = QueryBuilder(q as QueryMixin<Simple>);
      expect(builder.sqlWhereClause, isNotNull);
      expect(builder.sqlWhereClause, contains(':_Simple_id'));
    });

    test('insert SQL contains :v_-prefixed bound names', () {
      final q = Query<Simple>(context)..values.name = 'alice';
      final builder = QueryBuilder(q as QueryMixin<Simple>);
      expect(builder.sqlValuesToInsert, contains(':v_name'));
      expect(builder.variables.keys, contains('v_name'));
    });

    test('update SET clause uses :v_-prefixed placeholders', () {
      final q = Query<Simple>(context)
        ..values.name = 'new'
        ..where((s) => s.id).equalTo(7);
      final builder = QueryBuilder(q as QueryMixin<Simple>);
      expect(builder.sqlColumnsAndValuesToUpdate, contains('name=:v_name'));
      expect(builder.sqlWhereClause, contains(':_Simple_id'));
    });
  });
}

class Simple extends ManagedObject<_Simple> implements _Simple {}

class _Simple {
  @primaryKey
  int? id;

  @Column()
  String? name;
}
