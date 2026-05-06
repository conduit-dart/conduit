import 'dart:async';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_test/conduit_test.dart';
import 'package:test/test.dart';

/// Use methods from this class to test applications that use the Conduit ORM.
///
/// This class is mixed in to your [TestHarness] subclass to provide test
/// utilities for applications that use use the Conduit ORM. Methods from this class
/// manage setting up and tearing down your application's data model in a temporary database
/// for the purpose of testing.
///
/// You must override [context] to return your application's [ManagedContext] service.
/// You must override [seed] to insert static data in your database, as data is typically
/// cleared between tests.
///
/// You invoke [resetData] in your harness' [TestHarness.afterStart] method,
/// and typically in your test suite's [tearDown] method.
///
///         class Harness extends TestHarness<MyChannel> with TestHarnessORMMixin {
///             @override
///             ManagedContext get context => channel.context;
///
///             Future seed() async {
///               await Query.insertObject(...);
///             }
///         }
///
/// ## Multi-backend persistence
///
/// By default the harness uses whatever [PersistentStore] the channel
/// wired into its [ManagedContext] — historically a
/// `PostgreSQLPersistentStore`. To run the same harness against a
/// different backend (in-memory SQLite, MySQL, …) without modifying
/// the channel, register a factory:
///
/// ```dart
/// class Harness extends TestHarness<MyChannel> with TestHarnessORMMixin {
///   Harness() {
///     persistence = () => SqlitePersistentStore.memory();
///   }
///   @override
///   ManagedContext? get context => channel?.context;
/// }
/// ```
///
/// The factory is invoked on each [resetData], the channel's
/// `context.persistentStore` is swapped to the freshly-minted store,
/// and the schema is rebuilt against it. This keeps the existing
/// channel code dialect-agnostic — the channel wires up its
/// `ManagedDataModel` and the harness owns the store.
///
/// **Backwards compatibility.** If [persistence] is left null, the
/// harness behaves exactly as before: it uses
/// `context!.persistentStore` and re-applies the schema against it.
mixin TestHarnessORMMixin {
  /// Must override to return [ManagedContext] of application under test.
  ///
  /// An [ApplicationChannel] should expose its [ManagedContext] service as a property.
  /// Return the context from this method.
  ManagedContext? get context;

  /// Optional persistence factory. When set, every [resetData] call
  /// will close the currently-active store, invoke this factory to
  /// produce a fresh store, swap it onto the channel's
  /// [ManagedContext], and re-apply the schema against it.
  ///
  /// When null (the default), the harness uses the store the channel
  /// constructed and re-applies the schema against it — preserving
  /// the legacy Postgres-only behaviour.
  ///
  /// Callers can set this in their harness subclass constructor, or
  /// at install time:
  ///
  /// ```dart
  /// final harness = MyHarness()
  ///   ..persistence = () => SqlitePersistentStore.memory();
  /// ```
  PersistentStore Function()? persistence;

  /// Override this method to insert static data for each test run.
  ///
  /// This method gets invoked after [resetData] is called to re-provisioning static
  /// data in your application's database.
  ///
  /// For example, an application might have a table that contains country codes for
  /// every country in the world; this data would be cleared between each test case
  /// when [resetData] is called. By implementing this method, that data is recreated
  /// after the database is reset.
  Future seed() async {}

  /// Restores the initial database state of the application under test.
  ///
  /// This method destroys the connection to the application's database, deleting tables
  /// and data created during a test running. After the database is cleared,
  /// the application schema is reloaded and [seed] is invoked to re-provision
  /// static data.
  ///
  /// This method should be invoked in [TestHarness.afterStart] and typically is invoked
  /// in [tearDown] for your test suite.
  Future resetData({Logger? logger}) async {
    final ctx = context;
    if (ctx == null) {
      throw StateError(
          'TestHarnessORMMixin.resetData called before context is available; '
          'override `context` to return the application channel\'s '
          'ManagedContext.');
    }
    await ctx.persistentStore.close();

    if (persistence != null) {
      // Swap the store on the channel's context so subsequent Query<T>
      // calls and the channel's own code go through the new backend.
      ctx.persistentStore = persistence!();
    }

    await addSchema(logger: logger);
    await seed();
  }

  /// Adds the database tables in [context] to the database for the application under test.
  ///
  /// This method executes database commands to create temporary tables in the test database.
  /// It is invoked by [resetData].
  Future addSchema({Logger? logger}) async {
    final builder = SchemaBuilder.toSchema(
        context!.persistentStore, Schema.fromDataModel(context!.dataModel!),
        isTemporary: true);

    for (var cmd in builder.commands) {
      logger?.info(cmd);
      await context!.persistentStore.execute(cmd);
    }
  }
}
