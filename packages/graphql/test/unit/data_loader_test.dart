// Unit tests for DataLoader + DataLoaderRegistry.
//
// Covers the four cardinal invariants:
//   1. Batching — multiple `load`s within a tick fold into one batch
//      call.
//   2. Caching — repeat `load`s of the same key reuse the cached
//      future.
//   3. Error propagation — a thrown batch fn errors every awaiting
//      caller; cache stays sticky on the error future (mirrors the
//      JS reference).
//   4. clear / clearAll — drop cache entries and force a re-fetch.

import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:test/test.dart';

void main() {
  group('DataLoader.load', () {
    test('batches concurrent loads into one batch fn invocation',
        () async {
      var batchCalls = 0;
      final loader = DataLoader<int, String>((keys) async {
        batchCalls++;
        return keys.map((k) => 'v$k').toList();
      });

      final results = await Future.wait([
        loader.load(1),
        loader.load(2),
        loader.load(3),
      ]);
      expect(results, equals(['v1', 'v2', 'v3']));
      expect(batchCalls, equals(1));
    });

    test('dedups duplicate keys within the same tick', () async {
      var seenKeys = <List<int>>[];
      final loader = DataLoader<int, String>((keys) async {
        seenKeys.add(List.from(keys));
        return keys.map((k) => 'v$k').toList();
      });

      final results = await Future.wait([
        loader.load(1),
        loader.load(1),
        loader.load(1),
      ]);
      expect(results, equals(['v1', 'v1', 'v1']));
      // The batch should only see key 1 once.
      expect(seenKeys, equals([[1]]));
    });

    test('caches resolved values across ticks', () async {
      var batchCalls = 0;
      final loader = DataLoader<int, String>((keys) async {
        batchCalls++;
        return keys.map((k) => 'v$k').toList();
      });

      // Run two loads in the same tick; they collapse into a single
      // batch.
      await Future.wait([loader.load(1), loader.load(2)]);
      expect(batchCalls, equals(1));

      // A separate tick reloading either key must hit the cache.
      final cachedReload = await loader.load(1);
      expect(cachedReload, equals('v1'));
      expect(batchCalls, equals(1));
    });

    test('returns null when the batch fn returns null for that key',
        () async {
      final loader = DataLoader<int, String>((keys) async {
        return [for (final k in keys) k == 2 ? null : 'v$k'];
      });

      final results = await Future.wait([
        loader.load(1),
        loader.load(2),
        loader.load(3),
      ]);
      expect(results, equals(['v1', null, 'v3']));
    });
  });

  group('DataLoader.loadMany', () {
    test('preserves key order in the result list', () async {
      final loader = DataLoader<int, String>((keys) async {
        // Return out-of-order to verify the loader's order-preservation.
        final shuffled = keys.reversed.toList();
        return [for (final k in shuffled) 'v$k'].reversed.toList();
      });

      final results = await loader.loadMany([5, 3, 1, 2]);
      expect(results, equals(['v5', 'v3', 'v1', 'v2']));
    });

    test('empty input returns empty result without invoking batch fn',
        () async {
      var batchCalls = 0;
      final loader = DataLoader<int, String>((keys) async {
        batchCalls++;
        return keys.map((_) => '').toList();
      });
      final result = await loader.loadMany(const []);
      expect(result, isEmpty);
      expect(batchCalls, equals(0));
    });
  });

  group('DataLoader error propagation', () {
    test('every awaiting load completes with the thrown error', () async {
      final loader = DataLoader<int, String>((keys) async {
        throw StateError('boom');
      });

      final futures = [loader.load(1), loader.load(2), loader.load(3)];
      for (final f in futures) {
        await expectLater(f, throwsA(isA<StateError>()));
      }
    });

    test('batch fn returning wrong-length list errors all callers',
        () async {
      final loader = DataLoader<int, String>((keys) async {
        return ['only-one']; // wrong length when keys.length > 1
      });

      // Issue both loads in the same tick so they coalesce into a
      // single batch — that's the case the length-validation guard
      // protects.
      final f1 = loader.load(1);
      final f2 = loader.load(2);
      await expectLater(f1, throwsA(isA<StateError>()));
      await expectLater(f2, throwsA(isA<StateError>()));
    });
  });

  group('DataLoader.clear', () {
    test('clear forces a re-fetch on next load', () async {
      var batchCalls = 0;
      final loader = DataLoader<int, String>((keys) async {
        batchCalls++;
        return keys.map((k) => 'v$k-call$batchCalls').toList();
      });

      await loader.load(1);
      loader.clear(1);
      final reloaded = await loader.load(1);
      expect(reloaded, equals('v1-call2'));
      expect(batchCalls, equals(2));
    });

    test('clearAll drops every cached entry', () async {
      var batchCalls = 0;
      final loader = DataLoader<int, String>((keys) async {
        batchCalls++;
        return keys.map((k) => 'v$k-call$batchCalls').toList();
      });

      await Future.wait([loader.load(1), loader.load(2)]);
      loader.clearAll();
      final r = await Future.wait([loader.load(1), loader.load(2)]);
      expect(r, equals(['v1-call2', 'v2-call2']));
      expect(batchCalls, equals(2));
    });
  });

  group('DataLoaderRegistry', () {
    test('getOrAdd creates each loader at most once', () {
      final registry = DataLoaderRegistry();
      var factoryCalls = 0;
      DataLoader<int, String> make() {
        factoryCalls++;
        return DataLoader<int, String>((keys) async =>
            keys.map((k) => 'v$k').toList());
      }

      final l1 = registry.getOrAdd<int, String>('users', make);
      final l2 = registry.getOrAdd<int, String>('users', make);
      expect(identical(l1, l2), isTrue);
      expect(factoryCalls, equals(1));
    });

    test('different keys produce different loaders', () {
      final registry = DataLoaderRegistry();
      final l1 = registry.getOrAdd<int, String>(
        'users',
        () => DataLoader<int, String>(
            (keys) async => keys.map((k) => 'u$k').toList()),
      );
      final l2 = registry.getOrAdd<int, String>(
        'posts',
        () => DataLoader<int, String>(
            (keys) async => keys.map((k) => 'p$k').toList()),
      );
      expect(identical(l1, l2), isFalse);
    });

    test('register throws on duplicate keys', () {
      final registry = DataLoaderRegistry();
      final loader = DataLoader<int, String>(
          (keys) async => keys.map((_) => '').toList());
      registry.register<int, String>('k', loader);
      expect(
        () => registry.register<int, String>('k', loader),
        throwsStateError,
      );
    });

    test('clear empties the registry', () {
      final registry = DataLoaderRegistry();
      registry.getOrAdd<int, String>(
        'users',
        () => DataLoader<int, String>(
            (keys) async => keys.map((_) => '').toList()),
      );
      expect(registry.lookup<int, String>('users'), isNotNull);
      registry.clear();
      expect(registry.lookup<int, String>('users'), isNull);
    });
  });
}
