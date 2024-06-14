import 'package:wildfire/wildfire.dart';

Future main(List<String> args) async {
  final values = ApplicationOptions.parser.parse(args);
  if (values["help"] == true) {
    print(ApplicationOptions.parser.usage);
    return 0;
  }

  final app = Application<WildfireChannel>();
  app.options = ApplicationOptions()
    ..port = int.parse(values['port'] as String)
    ..address = values['address']
    ..isIpv6Only = values['ipv6-only'] == true
    ..configurationFilePath = values['config-path'] as String?
    ..certificateFilePath = values['ssl-certificate-path'] as String?
    ..privateKeyFilePath = values['ssl-key-path'] as String?;
  final isolateCountString = values['isolates'];
  if (isolateCountString == null) {
    await app.startOnCurrentIsolate();
  } else {
    await app.start(numberOfInstances: int.parse(isolateCountString as String));
  }
}
