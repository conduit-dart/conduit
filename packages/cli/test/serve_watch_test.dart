import 'dart:async';
import 'dart:io';

import 'package:conduit/src/commands/serve_watch.dart';
import 'package:conduit/src/running_process.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

void main() {
  group('WatchedServer (unit)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('conduit_watch_test_');
      await Directory(p.join(tmp.path, 'lib')).create(recursive: true);
      await File(p.join(tmp.path, 'lib', 'app.dart')).writeAsString('// stub');
      await File(p.join(tmp.path, 'pubspec.yaml')).writeAsString('name: x');
    });

    tearDown(() async {
      if (tmp.existsSync()) {
        await tmp.delete(recursive: true);
      }
    });

    /// Builds a fake [ServerStarter] that hands out [StoppableProcess]
    /// instances and tracks how many times it was invoked. Each handed-out
    /// process records when it was stopped.
    ({ServerStarter starter, _Probe probe}) fakeStarter() {
      final probe = _Probe();
      Future<StoppableProcess> starter() async {
        probe.startCount++;
        late StoppableProcess sp;
        sp = StoppableProcess((reason) async {
          probe.stopCount++;
        });
        probe.lastProcess = sp;
        return sp;
      }

      return (starter: starter, probe: probe);
    }

    test('start() boots child once and emits "started"', () async {
      final f = fakeStarter();
      final logs = <String>[];
      final ws = WatchedServer(
        starter: f.starter,
        projectDirectory: tmp,
        watchPaths: const ['lib'],
        debounce: const Duration(milliseconds: 20),
        onLog: logs.add,
        watcherFactory: (_) => _NoopWatcher(),
      );

      final firstEvent = ws.events.first;
      await ws.start();
      final ev = await firstEvent;

      expect(ev.kind, WatchedServerEventKind.started);
      expect(f.probe.startCount, 1);
      expect(ws.restartCount, 0);

      await ws.stop();
      expect(f.probe.stopCount, greaterThanOrEqualTo(1));
    });

    test('a single change triggers exactly one restart', () async {
      final f = fakeStarter();
      final ws = WatchedServer(
        starter: f.starter,
        projectDirectory: tmp,
        watchPaths: const ['lib'],
        debounce: const Duration(milliseconds: 20),
        watcherFactory: (_) => _NoopWatcher(),
      );

      await ws.start();
      final restarted =
          ws.events.firstWhere((e) => e.kind == WatchedServerEventKind.restarted);

      ws.simulateChange(p.join(tmp.path, 'lib', 'app.dart'));

      final ev = await restarted.timeout(const Duration(seconds: 2));
      expect(ev.changedPaths, contains(p.join(tmp.path, 'lib', 'app.dart')));
      expect(ws.restartCount, 1);
      expect(f.probe.startCount, 2);
      expect(f.probe.stopCount, 1);

      await ws.stop();
    });

    test(
        'multiple changes within the debounce window collapse into one restart',
        () async {
      final f = fakeStarter();
      final ws = WatchedServer(
        starter: f.starter,
        projectDirectory: tmp,
        watchPaths: const ['lib'],
        debounce: const Duration(milliseconds: 80),
        watcherFactory: (_) => _NoopWatcher(),
      );

      await ws.start();
      final restarted =
          ws.events.firstWhere((e) => e.kind == WatchedServerEventKind.restarted);

      // Simulate an IDE multi-file save burst.
      ws.simulateChange(p.join(tmp.path, 'lib', 'a.dart'));
      ws.simulateChange(p.join(tmp.path, 'lib', 'b.dart'));
      ws.simulateChange(p.join(tmp.path, 'lib', 'c.dart'));

      final ev = await restarted.timeout(const Duration(seconds: 2));
      expect(ev.changedPaths, hasLength(3));
      expect(ws.restartCount, 1);
      expect(f.probe.startCount, 2);

      await ws.stop();
    });

    test('non-Dart, non-pubspec changes are ignored', () async {
      final f = fakeStarter();
      final ws = WatchedServer(
        starter: f.starter,
        projectDirectory: tmp,
        watchPaths: const ['lib'],
        debounce: const Duration(milliseconds: 30),
        watcherFactory: (_) => _NoopWatcher(),
      );

      // Capture every restart event the watcher emits across its lifetime.
      // The list completes when the events stream closes via stop().
      final restartedFuture = ws.events
          .where((e) => e.kind == WatchedServerEventKind.restarted)
          .toList();

      await ws.start();
      ws.simulateChange(p.join(tmp.path, 'lib', 'README.md'));
      ws.simulateChange(p.join(tmp.path, 'lib', 'logo.png'));

      await ws.stop();
      expect(await restartedFuture, isEmpty);
      expect(ws.restartCount, 0);
      expect(f.probe.startCount, 1);
    });

    test('pubspec.yaml changes do trigger a restart', () async {
      final f = fakeStarter();
      final ws = WatchedServer(
        starter: f.starter,
        projectDirectory: tmp,
        watchPaths: const ['pubspec.yaml'],
        debounce: const Duration(milliseconds: 20),
        watcherFactory: (_) => _NoopWatcher(),
      );

      await ws.start();
      final restarted =
          ws.events.firstWhere((e) => e.kind == WatchedServerEventKind.restarted);

      ws.simulateChange(p.join(tmp.path, 'pubspec.yaml'));
      final ev = await restarted.timeout(const Duration(seconds: 2));
      expect(ev.changedPaths.single, endsWith('pubspec.yaml'));

      await ws.stop();
    });

    test('stop() is idempotent and tears down the current child', () async {
      final f = fakeStarter();
      final ws = WatchedServer(
        starter: f.starter,
        projectDirectory: tmp,
        watchPaths: const ['lib'],
        debounce: const Duration(milliseconds: 20),
        watcherFactory: (_) => _NoopWatcher(),
      );

      await ws.start();
      await ws.stop();
      await ws.stop(); // must not throw

      expect(ws.isShuttingDown, isTrue);
      expect(f.probe.stopCount, 1);
    });

    test('a starter that throws yields restartFailed but keeps watching',
        () async {
      var first = true;
      var startedCount = 0;
      final probe = _Probe();
      Future<StoppableProcess> starter() async {
        startedCount++;
        if (!first) {
          throw StateError('boom');
        }
        first = false;
        late StoppableProcess sp;
        sp = StoppableProcess((reason) async {
          probe.stopCount++;
        });
        return sp;
      }

      final ws = WatchedServer(
        starter: starter,
        projectDirectory: tmp,
        watchPaths: const ['lib'],
        debounce: const Duration(milliseconds: 20),
        watcherFactory: (_) => _NoopWatcher(),
      );

      await ws.start();
      final failed =
          ws.events.firstWhere((e) => e.kind == WatchedServerEventKind.restartFailed);

      ws.simulateChange(p.join(tmp.path, 'lib', 'broken.dart'));
      final ev = await failed.timeout(const Duration(seconds: 2));
      expect(ev.error, isA<StateError>());
      expect(ws.restartCount, 0); // failed restart must not bump the counter
      expect(startedCount, 2);
      expect(ws.isShuttingDown, isFalse);

      await ws.stop();
    });
  });
}

/// Lightweight test double for `Watcher` — never emits its own events; the
/// test drives [WatchedServer.simulateChange] instead. Avoids any reliance on
/// OS file-watcher behavior so the suite is reproducible in CI sandboxes.
class _NoopWatcher implements Watcher {
  @override
  String get path => '';

  @override
  Stream<WatchEvent> get events => const Stream<WatchEvent>.empty();

  @override
  bool get isReady => true;

  @override
  Future<void> get ready => Future<void>.value();
}

class _Probe {
  int startCount = 0;
  int stopCount = 0;
  StoppableProcess? lastProcess;
}
