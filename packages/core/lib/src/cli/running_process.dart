import 'dart:async';
import 'dart:io';

class StoppableProcess {
  StoppableProcess(Future Function(String reason) onStop) : _stop = onStop {
    final l1 = ProcessSignal.sigint.watch().listen((_) {
      stop(0, reason: "Process interrupted.");
    });
    _listeners.add(l1);

    if (!Platform.isWindows) {
      final l2 = ProcessSignal.sigterm.watch().listen((_) {
        stop(0, reason: "Process terminated by OS.");
      });
      _listeners.add(l2);
    }
  }

  Future<int> get exitCode => _completer.future;

  final List<StreamSubscription> _listeners = [];

  final Future Function(String) _stop;
  final Completer<int> _completer = Completer<int>();

  Future stop(int exitCode, {String? reason}) async {
    if (_completer.isCompleted) {
      return;
    }

    await Future.forEach(_listeners, (StreamSubscription sub) => sub.cancel());
    await _stop(reason ?? "Terminated normally.");
    _completer.complete(exitCode);
  }
}
