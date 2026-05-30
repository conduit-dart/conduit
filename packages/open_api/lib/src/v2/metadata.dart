import 'package:conduit_codable/conduit_codable.dart';
import 'package:conduit_open_api/src/object.dart';

/// Represents a metadata for an API in the OpenAPI specification.
class APIInfo extends APIObject {
  /// Creates empty metadata for specification.
  APIInfo();

  String title = "API";
  String? description = "Description";
  String? version = "1.0";
  String? termsOfServiceURL = "";
  APIContact? contact = APIContact();
  APILicense? license = APILicense();

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    title = object.decode<String>("title") ?? '';
    description = object.decode("description");
    termsOfServiceURL = object.decode("termsOfService");
    contact = object.decodeObject("contact", APIContact.new);
    license = object.decodeObject("license", APILicense.new);
    version = object.decode("version");
  }

  @override
  void encode(KeyedArchive object) {
    super.encode(object);

    object.encode("title", title);
    object.encode("description", description);
    object.encode("version", version);
    object.encode("termsOfService", termsOfServiceURL);
    object.encodeObject("contact", contact);
    object.encodeObject("license", license);
  }
}

/// Represents contact information in the OpenAPI specification.
class APIContact extends APIObject {
  APIContact();

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    name = object.decode("name") ?? "default";
    url = object.decode("url") ?? "http://localhost";
    email = object.decode("email") ?? "default";
  }

  String name = "default";
  String url = "http://localhost";
  String email = "default";

  @override
  void encode(KeyedArchive object) {
    super.encode(object);

    object.encode("name", name);
    object.encode("url", url);
    object.encode("email", email);
  }
}

/// Represents a copyright/open source license in the OpenAPI specification.
class APILicense extends APIObject {
  APILicense();

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    name = object.decode("name") ?? "default";
    url = object.decode("url") ?? "http://localhost";
  }

  String name = "default";
  String url = "http://localhost";

  @override
  void encode(KeyedArchive object) {
    super.encode(object);

    object.encode("name", name);
    object.encode("url", url);
  }
}

class APITag extends APIObject {
  APITag();

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    name = object.decode("name");
    description = object.decode("description");
  }

  String? name;
  String? description;

  @override
  void encode(KeyedArchive object) {
    super.encode(object);

    object.encode("name", name);
    object.encode("description", description);
  }
}
