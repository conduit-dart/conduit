import 'package:conduit_codable/conduit_codable.dart';
import 'package:conduit_open_api/src/v2/property.dart';
import 'package:conduit_open_api/src/v2/schema.dart';
import 'package:conduit_open_api/src/v2/types.dart';

/// Represents a parameter location in the OpenAPI specification.
enum APIParameterLocation { query, header, path, formData, body }

class APIParameterLocationCodec {
  static APIParameterLocation? decode(String? location) {
    switch (location) {
      case "query":
        return APIParameterLocation.query;
      case "header":
        return APIParameterLocation.header;
      case "path":
        return APIParameterLocation.path;
      case "formData":
        return APIParameterLocation.formData;
      case "body":
        return APIParameterLocation.body;
      default:
        return null;
    }
  }

  static String? encode(APIParameterLocation? location) {
    switch (location) {
      case APIParameterLocation.query:
        return "query";
      case APIParameterLocation.header:
        return "header";
      case APIParameterLocation.path:
        return "path";
      case APIParameterLocation.formData:
        return "formData";
      case APIParameterLocation.body:
        return "body";
      default:
        return null;
    }
  }
}

/// Represents a parameter in the OpenAPI specification.
class APIParameter extends APIProperty {
  APIParameter();

  String? name;
  String? description;
  bool isRequired = false;
  APIParameterLocation? location;

  // Valid if location is body.
  APISchemaObject? schema;

  // Valid if location is not body.
  bool allowEmptyValue = false;
  APIProperty? items;

  @override
  void decode(KeyedArchive object) {
    name = object.decode("name");
    description = object.decode("description");
    location = APIParameterLocationCodec.decode(object.decode("in"));
    if (location == APIParameterLocation.path) {
      isRequired = true;
    } else {
      isRequired = object.decode("required") ?? false;
    }

    if (location == APIParameterLocation.body) {
      schema = object.decodeObject("schema", () => APISchemaObject());
    } else {
      super.decode(object);
      allowEmptyValue = object.decode("allowEmptyValue") ?? false;
      if (type == APIType.array) {
        items = object.decodeObject("items", () => APIProperty());
      }
    }
  }

  @override
  void encode(KeyedArchive object) {
    object.encode("name", name);
    object.encode("description", description);
    object.encode("in", APIParameterLocationCodec.encode(location));
    object.encode("required", isRequired);

    if (location == APIParameterLocation.body) {
      object.encodeObject("schema", schema);
    } else {
      super.encode(object);
      if (allowEmptyValue) {
        object.encode("allowEmptyValue", allowEmptyValue);
      }
      if (type == APIType.array) {
        object.encodeObject("items", items);
      }
    }
  }
}
