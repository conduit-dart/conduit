import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_test/conduit_test.dart';
import 'package:test/test.dart';

void main() {
  tearDown(PersistenceConfig.reset);

  test('PersistenceConfig.factory defaults to null', () {
    expect(PersistenceConfig.factory, isNull);
  });

  test('PersistenceConfig.factory round-trips a closure', () {
    final store = _StubPersistentStore();
    PersistenceConfig.factory = () => store;
    expect(PersistenceConfig.factory!(), same(store));
  });

  test('PersistenceConfig.reset clears the factory', () {
    PersistenceConfig.factory = _StubPersistentStore.new;
    PersistenceConfig.reset();
    expect(PersistenceConfig.factory, isNull);
  });

  test('TestHarnessORMMixin.persistence is independent per instance', () {
    final h1 = _MiniHarness()..persistence = _StubPersistentStore.new;
    final h2 = _MiniHarness();
    expect(h1.persistence, isNotNull);
    expect(h2.persistence, isNull);
  });

  test('resetData throws StateError when context is null', () async {
    final h = _MiniHarness();
    await expectLater(h.resetData(), throwsA(isA<StateError>()));
  });
}

class _MiniHarness with TestHarnessORMMixin {
  @override
  ManagedContext? get context => null;
}

/// Stub `PersistentStore` that ignores all schema-op calls. Just enough
/// surface to round-trip through a `PersistenceFactory` reference.
class _StubPersistentStore implements PersistentStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
