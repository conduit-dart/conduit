// SQLite-backed integration test for the G3 resolver factory.
//
// Run with the default `dart test` invocation (no integration tag) —
// SQLite is in-process, so CI runs this on every commit.
//
// **Status: gated to skip on the active matrix.** As of #275 the
// `SqlitePersistentStore` ships schema + raw `execute` only; its
// `newQuery<T>` path throws `UnimplementedError` because the ORM
// query builders are still postgres-only. The test is laid down
// here so it lights up automatically when the SQLite ORM lands —
// per the dialect-annotation contract from #267, the
// `@OnlyOn([Dialect.sqlite])` gate ensures the test only runs against
// the sqlite matrix (`CONDUIT_TEST_DIALECT=sqlite dart test`), and
// the body skips with a clear reason until the underlying store
// supports `newQuery`.

import 'package:conduit_test/conduit_test.dart';
import 'package:test/test.dart';

void main() {
  // Skip the entire suite when the active matrix isn't sqlite. We
  // could call `skipIfDialectMismatch` from a `setUpAll`, but it
  // throws a `TestSkipped` (a marker exception) — not a value
  // recognised by package:test as "skip the group". Compute the
  // skip reason once and feed it to test()/group()'s `skip:`
  // parameter for portable behavior.
  final dialect = resolveActiveDialect();
  final decision = evaluateAnnotations(
    active: dialect,
    onlyOn: const OnlyOn([Dialect.sqlite]),
  );
  final dialectSkip = decision.skipReason;

  test(
    'placeholder — SQLite resolver suite waits on Sqlite ORM newQuery path',
    () {
      // SqlitePersistentStore.newQuery<T> throws UnimplementedError as
      // of conduit_sqlite v0; the resolver factory exercises that path
      // through Query.forEntity, so this suite cannot run end-to-end
      // until the ORM extraction in the multi-backend roadmap lands.
      // See packages/sqlite/lib/src/sqlite_persistent_store.dart.
      markTestSkipped(
        'SqlitePersistentStore.newQuery is UnimplementedError; the SQLite '
        'fixtures will exercise the same shape as the postgres suite once '
        'the ORM path lands. See packages/sqlite/lib/src/sqlite_persistent_'
        'store.dart for the gating UnimplementedError.',
      );
    },
    skip: dialectSkip,
  );
}
