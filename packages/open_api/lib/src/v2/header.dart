import 'package:conduit_codable/conduit_codable.dart';
import 'package:conduit_open_api/src/v2/property.dart';
import 'package:conduit_open_api/src/v2/types.dart';

/// Represents a header in the OpenAPI specification.
class APIHeader extends APIProperty {
  APIHeader();

  String? description;
  APIProperty? items;

  @override
  void decode(KeyedArchive object) {
    super.decode(object);
    description = object.decode("description");
    if (type == APIType.array) {
      items = object.decodeObject("items", () => APIProperty());
    }
  }

  @override
  void encode(KeyedArchive object) {
    super.encode(object);
    object.encode("description", description);
    if (type == APIType.array) {
      object.encodeObject("items", items);
    }
  }
}
