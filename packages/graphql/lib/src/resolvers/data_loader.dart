import 'dart:async';

/// A per-request, per-key-type batched + cached loader.
///
/// Mirrors the semantics of Facebook's reference
/// [`dataloader`](https://github.com/graphql/dataloader) library: every
/// call to [load] enqueues a key into a pending batch; when the current
/// event-loop turn ends (the next microtask), the batch is flushed
/// through the user-supplied [batchLoadFn] and the resulting values are
/// dispatched back to all waiters.
///
/// Two invariants make this useful for GraphQL:
///
///   1. **Batching.** Resolving a hasMany list (e.g. `Post.author` for
///      100 posts) inside a single tick produces *one* `IN (...)` round
///      trip rather than 100 single-row fetches.
///   2. **Caching.** Within the lifetime of the loader, a key is fetched
///      at most once. Subsequent [load]s for the same key reuse the
///      cached future. This makes nested queries that re-traverse the
///      same parent free.
///
/// The lifetime of a loader is **per request** — the controller's
/// `DataLoaderRegistry` allocates fresh loaders on each invocation of
/// the GraphQL endpoint so cached values can't leak across requests
/// (and so authorization decisions made by one request don't impact
/// another).
///
/// ### Why hand-rolled
///
/// The plan rejects external dataloader packages (the active-libraries
/// reminder in the project memory). The required surface — load,
/// loadMany, clear, clearAll, plus batch-on-microtask + cache-by-key —
/// fits in well under 200 lines of Dart, including doc comments. We
/// keep the dependency surface tight and the semantics directly under
/// our control (e.g. propagating a thrown batch error to every waiting
/// caller, which the JS reference does but some Dart ports omit).
class DataLoader<K, V> {
  /// Builds a loader that flushes accumulated keys through [batchLoadFn].
  ///
  /// The contract on [batchLoadFn] (mirrored from the JS reference):
  ///
  ///   * The returned list MUST be the same length as the input list.
  ///   * The returned list MUST be in the same order as the input list
  ///     — `result[i]` is the value for `keys[i]`.
  ///   * A `null` entry signals "no value for this key" (a missing row,
  ///     a soft delete, etc.). The future returned by [load] for that
  ///     key resolves to `null` rather than throwing.
  ///   * If the batch fn throws, every pending [load] for that batch
  ///     completes with the same error.
  ///
  /// Violating the length invariant produces a [StateError] that
  /// propagates to every awaiting caller — early, loud failure beats
  /// silent corruption of the result map.
  DataLoader(this._batchLoadFn);

  final Future<List<V?>> Function(List<K> keys) _batchLoadFn;

  /// Cache of resolved (and in-flight) futures, keyed by user key.
  ///
  /// This map serves three purposes:
  ///
  ///   1. **Dedup.** If two callers ask for the same key in the same
  ///      tick, they get the same future and the key only goes into
  ///      the batch once.
  ///   2. **Cache.** A key fetched on tick N is reused unchanged on
  ///      tick N+1.
  ///   3. **Error stickiness.** If the batch fn throws, every key in
  ///      that batch caches the error future, so a retry must go
  ///      through [clear] / [clearAll] first. (Same as the JS ref.)
  final Map<K, Future<V?>> _cache = {};

  /// Pending keys + completers, drained on the next microtask.
  final List<_PendingLoad<K, V>> _queue = [];

  /// True between the moment the first key is enqueued in a tick and
  /// the moment the batch flushes. Prevents duplicate microtasks.
  bool _flushScheduled = false;

  /// Loads [key], batching with any other [load] calls in the same
  /// event-loop tick.
  ///
  /// Returns `null` if [batchLoadFn] returned `null` for that key (a
  /// missing row).
  Future<V?> load(K key) {
    final cached = _cache[key];
    if (cached != null) return cached;

    final completer = Completer<V?>();
    _cache[key] = completer.future;
    _queue.add(_PendingLoad(key, completer));
    _scheduleFlush();
    return completer.future;
  }

  /// Convenience: loads every key in [keys] in parallel, preserving
  /// order. Equivalent to `Future.wait(keys.map(load))`.
  Future<List<V?>> loadMany(List<K> keys) {
    if (keys.isEmpty) return Future.value(const []);
    return Future.wait(keys.map(load));
  }

  /// Drops [key] from the cache. The next [load] of [key] will trigger
  /// a fresh batch fetch.
  void clear(K key) {
    _cache.remove(key);
  }

  /// Drops every cached entry. Use sparingly inside a request — the
  /// cache lifetime is already request-scoped.
  void clearAll() {
    _cache.clear();
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    // `scheduleMicrotask` runs at the END of the current synchronous
    // chunk, after every other `await`-resumed code in the tick has
    // had a chance to call [load]. This is the same primitive Apollo's
    // dataloader uses (`process.nextTick` in Node.js, microtask here).
    scheduleMicrotask(_flush);
  }

  Future<void> _flush() async {
    // Snapshot the queue: any [load] calls that arrive after this
    // line (e.g. resolvers awoken by completion of *this* batch) start
    // a fresh queue and a fresh microtask.
    final batch = List<_PendingLoad<K, V>>.from(_queue);
    _queue.clear();
    _flushScheduled = false;

    if (batch.isEmpty) return;

    final keys = batch.map((p) => p.key).toList();

    List<V?> results;
    try {
      results = await _batchLoadFn(keys);
    } on Object catch (e, st) {
      for (final p in batch) {
        p.completer.completeError(e, st);
      }
      return;
    }

    if (results.length != keys.length) {
      final err = StateError(
        'DataLoader batchLoadFn must return a List of the same length '
        'as the keys list (expected ${keys.length}, got ${results.length}).',
      );
      for (final p in batch) {
        p.completer.completeError(err);
      }
      return;
    }

    for (var i = 0; i < batch.length; i++) {
      batch[i].completer.complete(results[i]);
    }
  }
}

/// Internal record bundling a pending key with its completer. Avoids
/// allocating a `MapEntry` (which would force `K` and `V` covariance
/// games we don't need).
class _PendingLoad<K, V> {
  _PendingLoad(this.key, this.completer);
  final K key;
  final Completer<V?> completer;
}

/// Per-request bag of loaders.
///
/// Resolvers ask the registry for a typed loader keyed by an arbitrary
/// stable identifier (the destination entity, a (entity, fk-name)
/// tuple, etc.). The registry mints a loader on first ask and caches
/// it for the request's lifetime. The controller drops the registry
/// at request end so nothing leaks.
///
/// The [register] helper exists for test setup (or future caching
/// strategies that pre-register all loaders at request start). Most
/// callers will only use [getOrAdd].
class DataLoaderRegistry {
  /// The registry's loaders, keyed by an arbitrary identifier supplied
  /// by the resolver. A `dynamic` key is intentional — resolvers may
  /// key on a `ManagedEntity`, a `(ManagedEntity, String)` record, or a
  /// custom symbol; uniformly forcing a string key would force
  /// stringification of the entity name and lose strong typing.
  final Map<Object, DataLoader<dynamic, dynamic>> _loaders = {};

  /// Returns the loader registered against [key], creating it via
  /// [factory] on first call.
  DataLoader<K, V> getOrAdd<K, V>(
    Object key,
    DataLoader<K, V> Function() factory,
  ) {
    final existing = _loaders[key];
    if (existing != null) {
      return existing as DataLoader<K, V>;
    }
    final created = factory();
    _loaders[key] = created;
    return created;
  }

  /// Pre-registers a loader against [key]. Throws if a loader already
  /// exists — prefer [getOrAdd] in resolver code; this is for setup
  /// where the registration order matters.
  void register<K, V>(Object key, DataLoader<K, V> loader) {
    if (_loaders.containsKey(key)) {
      throw StateError(
        'DataLoaderRegistry already contains a loader for key $key.',
      );
    }
    _loaders[key] = loader;
  }

  /// Looks up a loader without creating one. Returns `null` if none
  /// is registered. Useful for tests.
  DataLoader<K, V>? lookup<K, V>(Object key) {
    final found = _loaders[key];
    if (found == null) return null;
    return found as DataLoader<K, V>;
  }

  /// Drops every loader. Called by the controller at request end.
  void clear() {
    _loaders.clear();
  }
}
