import 'package:conduit/src/cli/command.dart';
import 'package:conduit/src/cli/metadata.dart';

abstract class CLIDocumentOptions implements CLICommand {
  @Flag("resolve-relative-urls",
      defaultsTo: true,
      abbr: "r",
      help:
          "Whether relative URLs are resolved against the first server in document")
  bool get resolveRelativeUrls => decode("resolve-relative-urls");

  @Option("title", help: "API Docs: Title")
  String? get title => decodeOptional("title");

  @Option("description", help: "API Docs: Description")
  String? get apiDescription => decodeOptional("description");

  @Option("api-version", help: "API Docs: Version")
  String? get apiVersion => decodeOptional("api-version");

  @Option("tos", help: "API Docs: Terms of Service URL")
  String? get termsOfServiceURL => decodeOptional("tos");

  @Option("contact-email", help: "API Docs: Contact Email")
  String? get contactEmail => decodeOptional("contact-email");

  @Option("contact-name", help: "API Docs: Contact Name")
  String? get contactName => decodeOptional("contact-name");

  @Option("contact-url", help: "API Docs: Contact URL")
  String? get contactURL => decodeOptional("contact-url");

  @Option("license-url", help: "API Docs: License URL")
  String? get licenseURL => decodeOptional("license-url");

  @Option("license-name", help: "API Docs: License Name")
  String? get licenseName => decodeOptional("license-name");

  @Option("config-path",
      abbr: "c",
      help:
          "The path to a configuration file that this application needs to initialize resources for the purpose of documenting its API.",
      defaultsTo: "config.src.yaml")
  String get configurationPath => decode("config-path");

  @MultiOption("host",
      help: "Scheme, host and port for available instances.",
      valueHelp: "https://api.myapp.com:8000")
  List<Uri> get hosts {
    List<String> hostValues = decodeOptional("host") ?? <String>[];
    if (hostValues.isEmpty) {
      hostValues = ["http://localhost:8888"];
    }
    return hostValues.map(parseHostOption).toList();
  }

  Uri parseHostOption(String str) {
    try {
      final uri = Uri.parse(str);
      return uri;
    } on FormatException catch (_) {
      throw CLIException("Invalid Host Option", instructions: [
        "Host names must identify scheme, host and port. Example: https://api.myapp.com:8000"
      ]);
    }
  }
}
