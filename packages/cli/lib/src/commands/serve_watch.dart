import 'dart:async';
import 'dart:io';

import 'package:conduit/src/running_process.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

/// Signature for the underlying "boot the application once" function.
///
/// Returns the [StoppableProcess] handle that owns the running app (typically
/// produced by `CLIServer._start()`).
typedef ServerStarter = Future<StoppableProcess> Function();

/// Reasons a [WatchedServer] notifies its listeners.
enum WatchedServerEventKind {
  /// The watched server started for the first time.
  started,

  /// A file change triggered a restart cycle.
  restarted,

  /// The watcher (and its child app) is shutting down.
  stopped,

  /// A restart attempt threw — kept around so the watcher loop can keep going.
  restartFailed,
}

/// A single notification emitted by [WatchedServer.events].
class WatchedServerEvent {
  WatchedServerEvent(this.kind, {this.changedPaths = const [], this.error});

  final WatchedServerEventKind kind;

  /// Paths that triggered this restart, in the order they were observed.
  final List<String> changedPaths;

  /// Populated for [WatchedServerEventKind.restartFailed].
  final Object? error;
}

/// Owns a child server process plus a file watcher, and restarts the child
/// whenever a `.dart`/`pubspec.yaml`/`analysis_options.yaml` change is seen
/// under one of [watchPaths].
///
/// The class is deliberately decoupled from `CLIServer` so it is unit-testable
/// against any [ServerStarter].
class WatchedServer {
  WatchedServer({
    required this.starter,
    required this.projectDirectory,
    required this.watchPaths,
    this.debounce = const Duration(milliseconds: 500),
    this.onLog,
    Watcher Function(String path)? watcherFactory,
  }) : _watcherFactory = watcherFactory ?? _defaultWatcherFactory;

  /// Boots a fresh child process. Called once at startup and again on every
  /// debounced change.
  final ServerStarter starter;

  /// Project root the watcher resolves [watchPaths] against.
  final Directory projectDirectory;

  /// Directories (or single files) to watch, relative to [projectDirectory] or
  /// absolute. Missing paths are skipped silently with a log message.
  final List<String> watchPaths;

  /// Debounce window for collapsing IDE save bursts.
  final Duration debounce;

  /// Optional logging hook. The CLI wires this to `displayInfo` /
  /// `displayProgress`; tests can capture lines.
  final void Function(String line)? onLog;

  final Watcher Function(String path) _watcherFactory;

  final List<StreamSubscription<dynamic>> _watcherSubs = [];
  final StreamController<WatchedServerEvent> _events =
      StreamController<WatchedServerEvent>.broadcast();

  final Set<String> _pendingChanges = <String>{};
  Timer? _debounceTimer;
  bool _restarting = false;
  bool _shuttingDown = false;
  StoppableProcess? _current;
  int _restartCount = 0;

  /// Stream of lifecycle events. Tests use this; the CLI listens to it for
  /// log-only purposes.
  Stream<WatchedServerEvent> get events => _events.stream;

  /// Number of completed restarts since the watcher started. Useful for tests.
  int get restartCount => _restartCount;

  /// True after [stop] has been called.
  bool get isShuttingDown => _shuttingDown;

  /// Boots the initial child and arms the watcher. Resolves once the first
  /// child has started.
  Future<void> start() async {
    _current = await starter();
    _events.add(WatchedServerEvent(WatchedServerEventKind.started));
    _attachWatchers();
  }

  /// Stops the current child (if any), tears down watchers, completes silently
  /// even if the child is already gone.
  Future<void> stop() async {
    if (_shuttingDown) {
      return;
    }
    _shuttingDown = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    for (final sub in _watcherSubs) {
      await sub.cancel();
    }
    _watcherSubs.clear();
    final c = _current;
    _current = null;
    if (c != null) {
      await c.stop(0, reason: "watch mode shutdown");
    }
    _events.add(WatchedServerEvent(WatchedServerEventKind.stopped));
    await _events.close();
  }

  /// Public entrypoint used by tests to simulate a file event without going
  /// through the OS-level watcher.
  void simulateChange(String path) {
    _onPathChanged(path);
  }

  void _attachWatchers() {
    for (final raw in watchPaths) {
      final resolved = _resolve(raw);
      if (resolved == null) {
        _log("Watch path not found, skipping: $raw");
        continue;
      }
      final watcher = _watcherFactory(resolved);
      final sub = watcher.events.listen(
        (e) => _onPathChanged(e.path),
        onError: (Object e) => _log("Watcher error on $resolved: $e"),
      );
      _watcherSubs.add(sub);
      _log("Watching $resolved");
    }
  }

  String? _resolve(String raw) {
    final asAbs = p.isAbsolute(raw)
        ? raw
        : p.normalize(p.join(projectDirectory.path, raw));
    if (FileSystemEntity.isDirectorySync(asAbs) ||
        FileSystemEntity.isFileSync(asAbs)) {
      return asAbs;
    }
    return null;
  }

  void _onPathChanged(String path) {
    if (_shuttingDown) {
      return;
    }
    if (!_isInteresting(path)) {
      return;
    }
    _pendingChanges.add(path);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _flush);
  }

  bool _isInteresting(String path) {
    final base = p.basename(path);
    if (base == 'pubspec.yaml' || base == 'analysis_options.yaml') {
      return true;
    }
    return p.extension(path) == '.dart';
  }

  Future<void> _flush() async {
    if (_shuttingDown || _restarting || _pendingChanges.isEmpty) {
      return;
    }
    _restarting = true;
    final changed = _pendingChanges.toList()..sort();
    _pendingChanges.clear();

    try {
      final old = _current;
      _current = null;
      _log("Change detected: ${changed.join(', ')}");
      _log("Restarting application…");
      if (old != null) {
        await old.stop(0, reason: "watch mode restart");
      }
      _current = await starter();
      _restartCount += 1;
      _events.add(
        WatchedServerEvent(WatchedServerEventKind.restarted, changedPaths: changed),
      );
      _log("Restart complete (#$_restartCount)");
    } catch (e) {
      _events.add(
        WatchedServerEvent(
          WatchedServerEventKind.restartFailed,
          changedPaths: changed,
          error: e,
        ),
      );
      _log("Restart failed: $e");
    } finally {
      _restarting = false;
      // If new events arrived during the restart, schedule another flush.
      if (_pendingChanges.isNotEmpty && !_shuttingDown) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(debounce, _flush);
      }
    }
  }

  void _log(String line) {
    onLog?.call(line);
  }

  static Watcher _defaultWatcherFactory(String path) {
    // `package:watcher` picks the best backend per platform (FSEvents on
    // macOS, ReadDirectoryChangesW on Windows, inotify on Linux), and falls
    // back to polling when those aren't available — which already covers the
    // "fall back to dart:io" requirement transparently.
    if (FileSystemEntity.isDirectorySync(path)) {
      return DirectoryWatcher(path);
    }
    return FileWatcher(path);
  }
}
