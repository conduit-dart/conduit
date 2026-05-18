import 'package:conduit_core/conduit_core.dart';

/// A factory that produces a fresh [PersistentStore] for a test run.
///
/// The factory is invoked once per harness lifecycle (typically at
/// [TestHarnessORMMixin.resetData] time, or when first wiring the
/// channel's [ManagedContext]). Each call should return a new,
/// disconnected store — the harness will swap any existing store on
/// the application's [ManagedContext] for the one this factory
/// returns, then call [SchemaBuilder.toSchema] against it to recreate
/// the schema.
///
/// **Why a factory and not a single store?** SQLite's in-memory mode
/// loses all data when the connection closes (which `resetData` does
/// between tests), so the harness needs to be able to mint a fresh
/// store on each reset. Postgres works equally well with a single
/// long-lived store, but having one shape that fits both backends
/// keeps the harness API uniform.
typedef PersistenceFactory = PersistentStore Function();

/// Holder used by [TestHarnessORMMixin] to find a configured
/// [PersistenceFactory] without taking a hard dependency on any
/// specific backend package.
///
/// The harness checks this for an override before falling back to
/// whatever store the channel's [ManagedContext] was wired with. The
/// default behaviour (no override) is the legacy Postgres-from-channel
/// path — set [factory] to override.
///
/// Per-test usage:
///
/// ```dart
/// final harness = MyHarness();
/// PersistenceConfig.factory = () => SqlitePersistentStore.memory();
/// harness.install();
/// ```
///
/// Or scoped via a setter on the harness subclass — see the helper
/// methods on `TestHarnessORMMixin` for the recommended shape.
class PersistenceConfig {
  PersistenceConfig._();

  /// The currently registered factory, or `null` to use the channel's
  /// own store. Reset between test files in CI by setting back to
  /// `null` in `tearDownAll`.
  static PersistenceFactory? factory;

  /// Convenience: clear any registered factory. Equivalent to
  /// `PersistenceConfig.factory = null`.
  static void reset() {
    factory = null;
  }
}
