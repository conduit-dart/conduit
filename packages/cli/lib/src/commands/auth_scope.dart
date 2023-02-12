import 'dart:async';

import 'package:conduit/src/command.dart';
import 'package:conduit/src/metadata.dart';
import 'package:conduit/src/mixins/database_connecting.dart';
import 'package:conduit/src/mixins/database_managing.dart';
import 'package:conduit/src/mixins/project.dart';
import 'package:conduit_core/managed_auth.dart';
import 'package:conduit_core/conduit_core.dart';

class CLIAuthScopeClient extends CLICommand
    with CLIDatabaseConnectingCommand, CLIDatabaseManagingCommand, CLIProject {
  late ManagedContext context;

  @Option("id", abbr: "i", help: "The client ID to insert.")
  String? get clientID => decodeOptional("id");

  @Option(
    "scopes",
    help:
        "A space-delimited list of allowed scopes. Omit if application does not support scopes.",
    defaultsTo: "",
  )
  List<String>? get scopes {
    final String v = decode("scopes");
    if (v.isEmpty) {
      return null;
    }
    return v.split(" ").toList();
  }

  @override
  Future<int> handle() async {
    if (clientID == null) {
      displayError("Option --id required.");
      return 1;
    }
    if (scopes?.isEmpty ?? true) {
      displayError("Option --scopes required.");
      return 1;
    }

    final dataModel = ManagedDataModel.fromCurrentMirrorSystem();
    context = ManagedContext(dataModel, persistentStore);

    final scopingClient = AuthClient.public(
      clientID!,
      allowedScopes: scopes?.map((s) => AuthScope(s)).toList(),
    );

    final query = Query<ManagedAuthClient>(context)
      ..where((o) => o.id).equalTo(clientID)
      ..values.allowedScope =
          scopingClient.allowedScopes?.map((s) => s.toString()).join(" ");

    final result = await query.updateOne();
    if (result == null) {
      displayError("Client ID '$clientID' does not exist.");
      return 1;
    }

    displayInfo("Success", color: CLIColor.green);
    displayProgress("Client with ID '$clientID' has been updated.");
    displayProgress("Updated scope: ${result.allowedScope}");
    return 0;
  }

  @override
  Future cleanup() async {
    await context.close();
  }

  @override
  String get name {
    return "set-scope";
  }

  @override
  String get description {
    return "Sets the scope of an existing OAuth 2.0 client in a database that has been provisioned with the conduit/managed_auth package.";
  }
}
