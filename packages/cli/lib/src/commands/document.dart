import 'dart:async';
import 'dart:convert';

import 'package:conduit/src/command.dart';
import 'package:conduit/src/commands/document_serve.dart';
import 'package:conduit/src/commands/oai_client.dart';
import 'package:conduit/src/mixins/openapi_options.dart';
import 'package:conduit/src/mixins/project.dart';
import 'package:conduit/src/scripts/openapi_builder.dart';

class CLIDocument extends CLICommand with CLIProject, CLIDocumentOptions {
  CLIDocument() {
    registerCommand(CLIDocumentServe());
    registerCommand(CLIDocumentClient());
  }

  @override
  Future<int> handle() async {
    final documentMap = await documentProject(this, this);

    outputSink.writeln(json.encode(documentMap));

    return 0;
  }

  @override
  String get name {
    return "document";
  }

  @override
  String get description {
    return "Generates an OpenAPI specification of an application.";
  }

  @override
  String get detailedDescription {
    return "This tool will generate an OpenAPI specification of a Conduit application. It operates by invoking Application.document. "
        "This method locates the ApplicationChannel subclass and invokes the first three phases of initialization:\n\n"
        "\tApplicationChannel.initializeApplication\n"
        "\tAppplicationChannel.prepare\n"
        "\tAppplicationChannel.entryPoint\n\n"
        "After these initialization methods are called, ApplicationChannel.document is invoked. Note that the full initialization process does not"
        " occur: Application.willStartReceivingRequests is not called because no web server is started. However, it is important that"
        " the first three steps of initialization can occur without error when generating documentation. This often requires having a"
        " valid configuration file (--config-path) when running this tool. The suggested approach is to use config.src.yaml as the configuration"
        " file for the document tool.";
  }
}
