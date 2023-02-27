import 'package:conduit_codable/cast.dart' as cast;
import 'package:conduit_codable/conduit_codable.dart';
import 'package:conduit_open_api/src/v2/property.dart';

/// Represents a schema object in the OpenAPI specification.
class APISchemaObject extends APIProperty {
  APISchemaObject();

  String? title;
  String? description;
  String? example;
  List<String?>? isRequired = [];
  bool readOnly = false;

  /// Valid when type == array
  APISchemaObject? items;

  /// Valid when type == null
  Map<String, APISchemaObject?>? properties;

  /// Valid when type == object
  APISchemaObject? additionalProperties;

  @override
  APISchemaRepresentation get representation {
    if (properties != null) {
      return APISchemaRepresentation.structure;
    }

    return super.representation;
  }

  @override
  Map<String, cast.Cast> get castMap =>
      {"required": const cast.List(cast.string)};

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    title = object.decode("title");
    description = object.decode("description");
    isRequired = object.decode("required");
    example = object.decode("example");
    readOnly = object.decode("readOnly") ?? false;

    items = object.decodeObject("items", () => APISchemaObject());
    additionalProperties =
        object.decodeObject("additionalProperties", () => APISchemaObject());
    properties = object.decodeObjectMap("properties", () => APISchemaObject());
  }

  @override
  void encode(KeyedArchive object) {
    super.encode(object);

    object.encode("title", title);
    object.encode("description", description);
    object.encode("required", isRequired);
    object.encode("example", example);
    object.encode("readOnly", readOnly);

    object.encodeObject("items", items);
    object.encodeObject("additionalProperties", additionalProperties);
    object.encodeObjectMap("properties", properties);
  }
}
