import 'dart:async';

import 'package:conduit_common/conduit_common.dart';
import 'package:conduit_core/src/db/managed/data_model_manager.dart' as mm;
import 'package:conduit_core/src/db/managed/managed.dart';
import 'package:conduit_core/src/db/persistent_store/persistent_store.dart';
import 'package:conduit_core/src/db/query/query.dart';

/// A service object that handles connecting to and sending queries to a database.
///
/// You create objects of this type to use the Conduit ORM. Create instances in [ApplicationChannel.prepare]
/// and inject them into controllers that execute database queries.
///
/// A context contains two types of objects:
///
/// - [PersistentStore] : Maintains a connection to a specific database. Transfers data between your application and the database.
/// - [ManagedDataModel] : Contains information about the [ManagedObject] subclasses in your application.
///
/// Example usage:
///
///         class Channel extends ApplicationChannel {
///            ManagedContext context;
///
///            @override
///            Future prepare() async {
///               var store = new PostgreSQLPersistentStore(...);
///               var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
///               context = new ManagedContext(dataModel, store);
///            }
///
///            @override
///            Controller get entryPoint {
///              final router = new Router();
///              router.route("/path").link(() => new DBController(context));
///              return router;
///            }
///         }
class ManagedContext implements APIComponentDocumenter {
  /// Creates an instance of [ManagedContext] from a [ManagedDataModel] and [PersistentStore].
  ///
  /// This is the default constructor.
  ///
  /// A [Query] is sent to the database described by [persistentStore]. A [Query] may only be executed
  /// on this context if its type is in [dataModel].
  ManagedContext(this.dataModel, this.persistentStore) {
    mm.add(dataModel!);
    _finalizer.attach(this, persistentStore, detach: this);
  }

  /// Creates a child context from [parentContext].
  ManagedContext.childOf(ManagedContext parentContext)
      : persistentStore = parentContext.persistentStore,
        dataModel = parentContext.dataModel;

  static final Finalizer<PersistentStore> _finalizer =
      Finalizer((store) async => store.close());

  /// The persistent store that [Query]s on this context are executed through.
  PersistentStore persistentStore;

  /// The data model containing the [ManagedEntity]s that describe the [ManagedObject]s this instance works with.
  final ManagedDataModel? dataModel;

  /// Runs all [Query]s in [transactionBlock] within a database transaction.
  ///
  /// Queries executed within [transactionBlock] will be executed as a database transaction.
  /// A [transactionBlock] is passed a [ManagedContext] that must be the target of all queries
  /// within the block. The context passed to the [transactionBlock] is *not* the same as
  /// the context the transaction was created from.
  ///
  /// *You must not use the context this method was invoked on inside the transactionBlock.
  /// Doing so will deadlock your application.*
  ///
  /// If an exception is encountered in [transactionBlock], any query that has already been
  /// executed will be rolled back and this method will rethrow the exception.
  ///
  /// You may manually rollback a query by throwing a [Rollback] object. This will exit the
  /// [transactionBlock], roll back any changes made in the transaction, but this method will not
  /// throw.
  ///
  /// TODO: the following statement is not true.
  /// Rollback takes a string but the transaction
  /// returns <T>.  It would seem to be a better idea to still throw the manual Rollback
  /// so the user has a consistent method of handling the rollback. We could add a property
  /// to the Rollback class 'manual' which would be used to indicate a manual rollback.
  /// For the moment I've changed the return type to Future<void> as
  /// The parameter passed to [Rollback]'s constructor will be returned from this method
  /// so that the caller can determine why the transaction was rolled back.
  ///
  /// Example usage:
  ///
  ///         await context.transaction((transaction) async {
  ///            final q = new Query<Model>(transaction)
  ///             ..values = someObject;
  ///            await q.insert();
  ///            ...
  ///         });
  Future<T?> transaction<T>(
    Future<T?> Function(ManagedContext transaction) transactionBlock,
  ) {
    return persistentStore.transaction(
      ManagedContext.childOf(this),
      transactionBlock,
    );
  }

  /// Closes this context and release its underlying resources.
  ///
  /// This method closes the connection to [persistentStore] and releases [dataModel].
  /// A context may not be reused once it has been closed.
  Future close() async {
    await persistentStore.close();
    _finalizer.detach(this);
    mm.remove(dataModel!);
  }

  /// Returns an entity for a type from [dataModel].
  ///
  /// See [ManagedDataModel.entityForType].
  ManagedEntity entityForType(Type type) {
    return dataModel!.entityForType(type);
  }

  /// Inserts a single [object] into this context.
  ///
  /// This method is equivalent shorthand for [Query.insert].
  Future<T> insertObject<T extends ManagedObject>(T object) {
    final query = Query<T>(this)..values = object;
    return query.insert();
  }

  /// Inserts each object in [objects] into this context.
  ///
  /// If any insertion fails, no objects will be inserted into the database and an exception
  /// is thrown.
  Future<List<T>> insertObjects<T extends ManagedObject>(
    List<T> objects,
  ) async {
    return Query<T>(this).insertMany(objects);
  }

  /// Returns an object of type [T] from this context if it exists, otherwise returns null.
  ///
  /// If [T] cannot be inferred, an error is thrown. If [identifier] is not the same type as [T]'s primary key,
  /// null is returned.
  Future<T?> fetchObjectWithID<T extends ManagedObject>(
    dynamic identifier,
  ) async {
    final entity = dataModel!.tryEntityForType(T);
    if (entity == null) {
      throw ArgumentError("Unknown entity '$T' in fetchObjectWithID. "
          "Provide a type to this method and ensure it is in this context's data model.");
    }

    final primaryKey = entity.primaryKeyAttribute!;
    if (!primaryKey.type!.isAssignableWith(identifier)) {
      return null;
    }

    final query = Query<T>(this)
      ..where((o) => o[primaryKey.name]).equalTo(identifier);
    return query.fetchOne();
  }

  @override
  void documentComponents(APIDocumentContext context) =>
      dataModel!.documentComponents(context);
}

/// Throw this object to roll back a [ManagedContext.transaction].
///
/// When thrown in a transaction, it will cancel an in-progress transaction and rollback
/// any changes it has made.
class Rollback {
  /// Default constructor, takes a [reason] object that can be anything.
  ///
  /// The parameter [reason] will be returned by [ManagedContext.transaction].
  Rollback(this.reason);

  /// The reason this rollback occurred.
  ///
  /// This value is returned from [ManagedContext.transaction] when this instance is thrown.
  final String reason;
}
