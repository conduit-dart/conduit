import 'package:wildfire/conduit.g.dart' as conduit_runtime;
import 'package:wildfire/wildfire.dart';

Future main(List<String> args) async {
  // Installs the build_runner-generated runtime registry.
  // Required for AOT (`dart compile exe`) — under JIT this call is
  // still safe but redundant; the mirror-based fallback would discover
  // the same types.
  conduit_runtime.bootstrap();

  final app = Application<WildfireChannel>();
  app.options = ApplicationOptions.fromArgs(args);
  if (app.options.isolates == 0) {
    await app.startOnCurrentIsolate();
  } else {
    await app.start(numberOfInstances: app.options.isolates);
  }
}
