// MySQL-backed integration test for the G3 resolver factory.
//
// Tagged `integration` so the default `dart test` run skips it; the
// CI matrix that has MySQL available runs it via
// `CONDUIT_TEST_DIALECT=mysql dart test -t integration`. Locally:
//
//   docker run --rm -d --name conduit-mysql-test \
//     -e MYSQL_ROOT_PASSWORD=conduit! \
//     -e MYSQL_DATABASE=conduit_test_db \
//     -e MYSQL_USER=conduit_test_user \
//     -e MYSQL_PASSWORD=conduit! \
//     -p 13306:3306 mysql:8
//   CONDUIT_TEST_DIALECT=mysql MYSQL_PORT=13306 \
//     dart test -t integration test/integration/sql_resolver_mysql_test.dart
//
// **Status: gated to skip on the active matrix.** As of the v0
// `package:conduit_mysql` rollout, the MySQL store ships schema +
// raw execute only; its `newQuery<T>` path is deferred for the same
// reason as SQLite (see notes in `sql_resolver_sqlite_test.dart`).
// The `@OnlyOn([Dialect.mysql])` gate keeps the test off the
// postgres matrix; the body skips with a clear reason so the
// suite is ready to light up the moment the MySQL ORM path lands.

@Tags(['integration'])
library;

import 'package:conduit_test/conduit_test.dart';
import 'package:test/test.dart';

void main() {
  final dialect = resolveActiveDialect();
  final decision = evaluateAnnotations(
    active: dialect,
    onlyOn: const OnlyOn([Dialect.mysql]),
  );
  final dialectSkip = decision.skipReason;

  test(
    'placeholder — MySQL resolver suite waits on MySQL ORM newQuery path',
    () {
      markTestSkipped(
        'conduit_mysql.newQuery is not yet wired in the v0 rollout. The '
        'MySQL fixtures mirror the postgres suite once the ORM path '
        'lands; see the multi-backend roadmap for status.',
      );
    },
    skip: dialectSkip,
  );
}
