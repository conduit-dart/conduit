import 'package:conduit_config/src/configuration.dart';

/// A [Configuration] to represent a database connection configuration.
class DatabaseConfiguration extends Configuration {
  /// Default constructor.
  DatabaseConfiguration();

  DatabaseConfiguration.fromFile(super.file) : super.fromFile();

  DatabaseConfiguration.fromString(super.yaml) : super.fromString();

  DatabaseConfiguration.fromMap(super.yaml) : super.fromMap();

  /// A named constructor that contains all of the properties of this instance.
  DatabaseConfiguration.withConnectionInfo(
    this.username,
    this.password,
    this.host,
    this.port,
    this.databaseName, {
    this.isTemporary = false,
  });

  /// The host of the database to connect to.
  ///
  /// This property is required.
  late String host;

  /// The port of the database to connect to.
  ///
  /// This property is required.
  late int port;

  /// The name of the database to connect to.
  ///
  /// This property is required.
  late String databaseName;

  /// A username for authenticating to the database.
  ///
  /// This property is optional.
  String? username;

  /// A password for authenticating to the database.
  ///
  /// This property is optional.
  String? password;

  /// A flag to represent permanence.
  ///
  /// This flag is used for test suites that use a temporary database to run tests against,
  /// dropping it after the tests are complete.
  /// This property is optional.
  bool isTemporary = false;

  @override
  void decode(dynamic value) {
    if (value is Map) {
      super.decode(value);
      return;
    }

    if (value is! String) {
      throw ConfigurationException(
        this,
        "'${value.runtimeType}' is not assignable; must be a object or string",
      );
    }

    final uri = Uri.parse(value);
    host = uri.host;
    port = uri.port;
    if (uri.pathSegments.length == 1) {
      databaseName = uri.pathSegments.first;
    }

    if (uri.userInfo == '') {
      validate();
      return;
    }

    final authority = uri.userInfo.split(":");
    if (authority.isNotEmpty) {
      username = Uri.decodeComponent(authority.first);
    }
    if (authority.length > 1) {
      password = Uri.decodeComponent(authority.last);
    }

    validate();
  }
}

/// A [Configuration] to represent an external HTTP API.
class APIConfiguration extends Configuration {
  APIConfiguration();

  APIConfiguration.fromFile(super.file) : super.fromFile();

  APIConfiguration.fromString(super.yaml) : super.fromString();

  APIConfiguration.fromMap(super.yaml) : super.fromMap();

  /// The base URL of the described API.
  ///
  /// This property is required.
  /// Example: https://external.api.com:80/resources
  late String baseURL;

  /// The client ID.
  ///
  /// This property is optional.
  String? clientID;

  /// The client secret.
  ///
  /// This property is optional.
  String? clientSecret;
}
