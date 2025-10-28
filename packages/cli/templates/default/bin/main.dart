import 'package:wildfire/wildfire.dart';

Future main(List<String> args) async {
  final app = Application<WildfireChannel>();
  app.options = ApplicationOptions.fromArgs(args);
  if (app.options.isolates == 0) {
    await app.startOnCurrentIsolate();
  } else {
    await app.start(numberOfInstances: app.options.isolates);
  }
}
