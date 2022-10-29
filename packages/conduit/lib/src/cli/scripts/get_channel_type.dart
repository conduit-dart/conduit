import 'dart:async';
import 'dart:mirrors';

import 'package:conduit/src/application/channel.dart';
import 'package:conduit_isolate_exec/conduit_isolate_exec.dart';
import 'package:conduit_runtime/runtime.dart';

class GetChannelExecutable extends Executable<String> {
  GetChannelExecutable(Map<String, dynamic> message) : super(message);

  @override
  Future<String> execute() async {
    final channels =
        RuntimeContext.current.runtimes.iterable.whereType<ChannelRuntime>();
    if (channels.length != 1) {
      throw StateError(
          "No ApplicationChannel subclass was found for this project. "
          "Make sure it is imported in your application library file.");
    }
    final runtime = channels.first;

    return MirrorSystem.getName(reflectClass(runtime.channelType).simpleName);
  }

  static List<String> importsForPackage(String? packageName) => [
        "package:conduit/conduit.dart",
        "package:$packageName/$packageName.dart",
        "package:conduit_runtime/runtime.dart"
      ];
}
