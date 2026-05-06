Test framework for [conduit](https://www.theconduit.dev/) applications. This package is included as a `dev_dependency` of `conduit` applications.

The documentation for this package is available at [https://www.theconduit.dev/docs/testing/](https://www.theconduit.dev/docs/testing/).

## Multi-backend testing

`conduit_test` ships a per-dialect annotation system (`@OnlyOn` / `@SkipOn`) and a
`PersistenceFactory` hook so the same test harness can run against postgres,
sqlite, mysql, or cockroach. Per-backend stores live in opt-in packages
(`conduit_postgresql`, `conduit_sqlite`, `conduit_mysql`) — `conduit_test`
itself does not depend on them.

### Configure a non-postgres backend

```dart
import 'package:conduit_test/conduit_test.dart';
import 'package:conduit_sqlite/conduit_sqlite.dart';

class MyHarness extends TestHarness<MyChannel> with TestHarnessORMMixin {
  MyHarness() {
    // Optional: swap the channel's PersistentStore on every resetData.
    persistence = () => SqlitePersistentStore.memory();
  }
  @override
  ManagedContext? get context => channel?.context;
}
```

When `persistence` is null (the default), the harness uses whatever store the
channel set up — preserving the legacy postgres-only flow.

### Annotate dialect-specific tests

```dart
import 'package:conduit_test/conduit_test.dart';
import 'package:test/test.dart';

void main() {
  group('jsonb operators', () {
    setUpAll(() => skipIfDialectMismatch(
          onlyOn: const OnlyOn([Dialect.postgres]),
        ));

    test('@> round-trips a Document', () async {
      // Only runs when CONDUIT_TEST_DIALECT=postgres (the default).
    });
  });

  test('insert RETURNING captures the generated PK', () async {
    // Skip on MySQL — no RETURNING clause there.
    skipIfDialectMismatch(
      skipOn: const SkipOn([Dialect.mysql],
          reason: 'MySQL has no RETURNING'),
    );
    // …
  });
}
```

The active dialect is read from the `CONDUIT_TEST_DIALECT` environment variable
(`postgres` (default), `sqlite`, `mysql`, `cockroach`) — or you can override it
directly via `skipIfDialectMismatch(activeOverride: ...)`.

### How dispatch works

`evaluateAnnotations(active: ..., onlyOn: ..., skipOn: ...)` returns a
`DialectSkipDecision` — `null` reason means the test runs, a non-null reason
is the string passed to `package:test`'s `skip:` parameter. Annotation
precedence is `OnlyOn` first, `SkipOn` second.

For an end-to-end example see
`packages/test_harness/test/integration/multi_backend_test.dart`.
