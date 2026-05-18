/// MySQL ORM integration tests — exercise the dialect-agnostic
/// query builders against a live MySQL/MariaDB instance.
///
/// **Tagged `integration`** — skipped by default (`dart test` will
/// not run them unless you pass `--tags=integration`). They expect a
/// running MySQL on `MYSQL_HOST` / `MYSQL_PORT` (defaults below).
///
/// Run locally:
///
/// ```bash
/// docker run -d --rm --name conduit_mysql_test \
///   -e MYSQL_ROOT_PASSWORD=conduit! \
///   -e MYSQL_DATABASE=conduit_test_db \
///   -e MYSQL_USER=conduit_test_user \
///   -e MYSQL_PASSWORD=conduit! \
///   -p 13306:3306 mysql:8
///
/// dart test --tags=integration packages/mysql/test/orm_integration_test.dart
/// ```
@Tags(['integration'])
library;

import 'dart:io';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_mysql/conduit_mysql.dart';
import 'package:test/test.dart';

String _envOr(String key, String fallback) {
  final v = Platform.environment[key]?.trim();
  if (v == null || v.isEmpty) return fallback;
  return v;
}

int _envIntOr(String key, int fallback) {
  final v = Platform.environment[key]?.trim();
  if (v == null || v.isEmpty) return fallback;
  return int.tryParse(v) ?? fallback;
}

Future<ManagedContext> _bootstrap(List<Type> instanceTypes) async {
  final store = MysqlPersistentStore(
    _envOr('MYSQL_USER', 'conduit_test_user'),
    _envOr('MYSQL_PASSWORD', 'conduit!'),
    _envOr('MYSQL_HOST', 'localhost'),
    _envIntOr('MYSQL_PORT', 13306),
    _envOr('MYSQL_DB', 'conduit_test_db'),
  );

  final dm = ManagedDataModel(instanceTypes);
  final ctx = ManagedContext(dm, store);

  // Drop + recreate the per-test tables. MySQL doesn't have temp
  // tables that survive a connection close cleanly, so we use real
  // tables and tear them down on exit.
  for (final entityType in instanceTypes) {
    final entity = dm.entityForType(entityType);
    await store.execute('DROP TABLE IF EXISTS ${entity.tableName}');
  }
  final schema = Schema.fromDataModel(dm);
  final builder = SchemaBuilder.toSchema(store, schema);
  for (final cmd in builder.commands) {
    await store.execute(cmd);
  }
  return ctx;
}

void main() {
  ManagedContext? context;

  tearDown(() async {
    await context?.close();
    context = null;
  });

  group('MysqlPersistentStore.newQuery — basic CRUD', () {
    test('insert + fetch round-trips a row', () async {
      context = await _bootstrap([Simple]);
      final inserted = await (Query<Simple>(context!)..values.name = 'alice')
          .insert();
      expect(inserted.name, 'alice');
      expect(inserted.id, isNotNull);

      final all = await Query<Simple>(context!).fetch();
      expect(all, hasLength(1));
      expect(all.first.name, 'alice');
    });

    test('update returns the updated rows', () async {
      context = await _bootstrap([Simple]);
      await (Query<Simple>(context!)..values.name = 'old').insert();

      final updated = await (Query<Simple>(context!)
            ..values.name = 'new'
            ..where((s) => s.name).equalTo('old'))
          .update();
      expect(updated, hasLength(1));
      expect(updated.first.name, 'new');
    });

    test('delete returns the affected row count', () async {
      context = await _bootstrap([Simple]);
      await (Query<Simple>(context!)..values.name = 'doomed').insert();
      await (Query<Simple>(context!)..values.name = 'survives').insert();
      final n = await (Query<Simple>(context!)
            ..where((s) => s.name).equalTo('doomed'))
          .delete();
      expect(n, 1);
    });

    test('count via reduce', () async {
      context = await _bootstrap([Simple]);
      for (final n in ['a', 'b', 'c']) {
        await (Query<Simple>(context!)..values.name = n).insert();
      }
      expect(await Query<Simple>(context!).reduce.count(), 3);
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
