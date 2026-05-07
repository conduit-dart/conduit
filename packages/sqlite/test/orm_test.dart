/// Portable subset of the postgresql ORM regression tests, ported to
/// run against `SqlitePersistentStore.memory()`. Exercises the
/// dialect-agnostic query builders that were lifted out of the
/// postgresql package.
///
/// Coverage selected from `packages/postgresql/test/`:
///  - basic CRUD (insert, fetch, update, delete) — equivalents of
///    fragments of `insert_test.dart`, `fetch_test.dart`,
///    `update_test.dart`, `delete_test.dart`.
///  - simple predicates (equalTo, lessThan, contains, isNull) — see
///    `matcher_test.dart`.
///  - belongs-to relationship insert + join — see
///    `belongs_to_fetch_test.dart`.
///  - reduce.count — see `aggregate_function_test.dart`.
///
/// Tests known to be Postgres-specific (e.g. Document/jsonb,
/// ManagedSet eager-fetch with set-aware joins) are skipped here;
/// SQLite has no native JSON binding and the set-join behavior
/// currently leans on Postgres's ROWS quirks. Track them in a
/// follow-up pass once we add a fuller portable matrix.
library;

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_sqlite/conduit_sqlite.dart';
import 'package:test/test.dart';

Future<ManagedContext> _bootstrap(List<Type> instanceTypes) async {
  final store = SqlitePersistentStore.memory();
  final dm = ManagedDataModel(instanceTypes);
  final ctx = ManagedContext(dm, store);

  // Build CREATE TABLE statements off the schema and run them. We
  // skip `temporary: true` because SQLite has its own semantics for
  // TEMP TABLES; for test isolation, an in-memory store is already
  // ephemeral.
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

  group('SqlitePersistentStore.newQuery — basic CRUD', () {
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

    test('insertMany inserts each row in order', () async {
      context = await _bootstrap([Simple]);
      final rows = await Query<Simple>(context!).insertMany([
        Simple()..name = 'a',
        Simple()..name = 'b',
        Simple()..name = 'c',
      ]);
      expect(rows.map((r) => r.name).toList(), ['a', 'b', 'c']);
    });

    test('fetchOne returns null when no rows match', () async {
      context = await _bootstrap([Simple]);
      final q = Query<Simple>(context!)..where((s) => s.id).equalTo(99999);
      expect(await q.fetchOne(), isNull);
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

    test('updateOne returns the single updated row', () async {
      context = await _bootstrap([Simple]);
      final inserted =
          await (Query<Simple>(context!)..values.name = 'first').insert();
      final updated = await (Query<Simple>(context!)
            ..values.name = 'second'
            ..where((s) => s.id).equalTo(inserted.id))
          .updateOne();
      expect(updated, isNotNull);
      expect(updated!.name, 'second');
    });

    test('delete returns the affected row count', () async {
      context = await _bootstrap([Simple]);
      await (Query<Simple>(context!)..values.name = 'doomed').insert();
      await (Query<Simple>(context!)..values.name = 'survives').insert();

      final n = await (Query<Simple>(context!)
            ..where((s) => s.name).equalTo('doomed'))
          .delete();
      expect(n, 1);

      final remaining = await Query<Simple>(context!).fetch();
      expect(remaining, hasLength(1));
      expect(remaining.first.name, 'survives');
    });
  });

  group('SqlitePersistentStore.newQuery — simple predicates', () {
    test('equalTo + notEqualTo filters', () async {
      context = await _bootstrap([Simple]);
      for (final n in ['a', 'b', 'c']) {
        await (Query<Simple>(context!)..values.name = n).insert();
      }
      final eq = await (Query<Simple>(context!)
            ..where((s) => s.name).equalTo('b'))
          .fetch();
      expect(eq.map((r) => r.name).toList(), ['b']);

      final neq = await (Query<Simple>(context!)
            ..where((s) => s.name).notEqualTo('b'))
          .fetch();
      expect(neq.map((r) => r.name).toSet(), {'a', 'c'});
    });

    test('lessThan + greaterThan on integer column', () async {
      context = await _bootstrap([Simple]);
      for (final n in ['a', 'b', 'c', 'd']) {
        await (Query<Simple>(context!)..values.name = n).insert();
      }
      final all = await Query<Simple>(context!).fetch();
      final mid = all[1].id!;
      final lt = await (Query<Simple>(context!)
            ..where((s) => s.id).lessThan(mid))
          .fetch();
      expect(lt, hasLength(1));
      final gt = await (Query<Simple>(context!)
            ..where((s) => s.id).greaterThan(mid))
          .fetch();
      expect(gt, hasLength(2));
    });

    test('oneOf (IN) predicate', () async {
      context = await _bootstrap([Simple]);
      for (final n in ['a', 'b', 'c']) {
        await (Query<Simple>(context!)..values.name = n).insert();
      }
      final res = await (Query<Simple>(context!)
            ..where((s) => s.name).oneOf(['a', 'c']))
          .fetch();
      expect(res.map((r) => r.name).toSet(), {'a', 'c'});
    });

    test('isNull + isNotNull predicates on nullable column', () async {
      context = await _bootstrap([Simple]);
      await (Query<Simple>(context!)..values.name = 'has').insert();
      await (Query<Simple>(context!)
            ..values.name = 'also'
            ..values.note = 'present')
          .insert();
      final missing = await (Query<Simple>(context!)
            ..where((s) => s.note).isNull())
          .fetch();
      expect(missing.map((r) => r.name).toList(), ['has']);
      final present = await (Query<Simple>(context!)
            ..where((s) => s.note).isNotNull())
          .fetch();
      expect(present.map((r) => r.name).toList(), ['also']);
    });

    test('LIKE-style contains on string column', () async {
      context = await _bootstrap([Simple]);
      for (final n in ['alpha', 'beta', 'gamma']) {
        await (Query<Simple>(context!)..values.name = n).insert();
      }
      final res = await (Query<Simple>(context!)
            ..where((s) => s.name).contains('a'))
          .fetch();
      // SQLite's default LIKE is ASCII-case-insensitive — both alpha
      // and gamma contain 'a', and beta contains 'a' too.
      expect(res.map((r) => r.name).toSet(), {'alpha', 'beta', 'gamma'});
    });
  });

  group('SqlitePersistentStore.newQuery — sorting + paging', () {
    test('sortBy ascending', () async {
      context = await _bootstrap([Simple]);
      for (final n in ['c', 'a', 'b']) {
        await (Query<Simple>(context!)..values.name = n).insert();
      }
      final res = await (Query<Simple>(context!)
            ..sortBy((s) => s.name, QuerySortOrder.ascending))
          .fetch();
      expect(res.map((r) => r.name).toList(), ['a', 'b', 'c']);
    });

    test('fetchLimit + offset', () async {
      context = await _bootstrap([Simple]);
      for (final n in ['a', 'b', 'c', 'd', 'e']) {
        await (Query<Simple>(context!)..values.name = n).insert();
      }
      final page = await (Query<Simple>(context!)
            ..sortBy((s) => s.name, QuerySortOrder.ascending)
            ..fetchLimit = 2
            ..offset = 1)
          .fetch();
      expect(page.map((r) => r.name).toList(), ['b', 'c']);
    });
  });

  group('SqlitePersistentStore.newQuery — relationships', () {
    test('belongsTo insert + join', () async {
      context = await _bootstrap([Owner, Pet]);
      final owner =
          await (Query<Owner>(context!)..values.name = 'Bob').insert();
      await (Query<Pet>(context!)
            ..values.name = 'Rex'
            ..values.owner = (Owner()..id = owner.id))
          .insert();

      final pet = await (Query<Pet>(context!)..join(object: (p) => p.owner))
          .fetchOne();
      expect(pet, isNotNull);
      expect(pet!.name, 'Rex');
      expect(pet.owner!.name, 'Bob');
    });
  });

  group('SqlitePersistentStore.newQuery — reduce', () {
    test('count', () async {
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

  @Column(nullable: true)
  String? note;
}

class Owner extends ManagedObject<_Owner> implements _Owner {}

class _Owner {
  @primaryKey
  int? id;

  @Column()
  String? name;

  ManagedSet<Pet>? pets;
}

class Pet extends ManagedObject<_Pet> implements _Pet {}

class _Pet {
  @primaryKey
  int? id;

  @Column()
  String? name;

  @Relate(#pets)
  Owner? owner;
}
