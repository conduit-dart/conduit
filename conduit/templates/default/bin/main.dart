import 'package:wildfire/wildfire.dart';

Future main() async {
  final app = Application<WildfireChannel>()
    ..options.configurationFilePath = "config.yaml"
    ..options.port = 8888;

  await app.startOnCurrentIsolate();

  // ignore: avoid_print
  print("Application started on port: ${app.options.port}.");
  // ignore: avoid_print
  print("Use Ctrl-C (SIGINT) to stop running the application.");
}
