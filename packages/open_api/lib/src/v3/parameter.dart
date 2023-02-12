import 'package:conduit_codable/conduit_codable.dart';
import 'package:conduit_open_api/src/object.dart';
import 'package:conduit_open_api/src/v3/document.dart';
import 'package:conduit_open_api/src/v3/media_type.dart';
import 'package:conduit_open_api/src/v3/schema.dart';

/// There are four possible parameter locations specified by the in field.
///
/// - path:
/// - query:
/// - header:
/// - cookie:
enum APIParameterLocation {
  /// Parameters that are appended to the URL.
  ///
  /// For example, in /items?id=###, the query parameter is id.
  query,

  /// Custom headers that are expected as part of the request.
  ///
  /// Note that RFC7230 states header names are case insensitive.
  header,

  /// Used together with Path Templating, where the parameter value is actually part of the operation's URL.
  ///
  /// This does not include the host or base path of the API. For example, in /items/{itemId}, the path parameter is itemId.
  path,

  /// Used to pass a specific cookie value to the API.
  cookie
}

class APIParameterLocationCodec {
  static APIParameterLocation? decode(String? location) {
    switch (location) {
      case "query":
        return APIParameterLocation.query;
      case "header":
        return APIParameterLocation.header;
      case "path":
        return APIParameterLocation.path;
      case "cookie":
        return APIParameterLocation.cookie;
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
      case APIParameterLocation.cookie:
        return "cookie";
      default:
        return null;
    }
  }
}

/// Describes a single operation parameter.
///
/// A unique parameter is defined by a combination of a [name] and [location].
class APIParameter extends APIObject {
  APIParameter(
    this.name,
    this.location, {
    this.description,
    this.schema,
    this.content,
    this.style,
    bool? isRequired,
    this.deprecated,
    this.allowEmptyValue,
    this.explode,
    this.allowReserved,
  }) : _required = isRequired;

  APIParameter.empty();

  APIParameter.header(
    this.name, {
    this.description,
    this.schema,
    this.content,
    this.style,
    bool? isRequired,
    this.deprecated,
    this.allowEmptyValue,
    this.explode,
    this.allowReserved,
  }) : _required = isRequired {
    location = APIParameterLocation.header;
  }

  APIParameter.query(
    this.name, {
    this.description,
    this.schema,
    this.content,
    this.style,
    bool? isRequired,
    this.deprecated,
    this.allowEmptyValue,
    this.explode,
    this.allowReserved,
  }) : _required = isRequired {
    location = APIParameterLocation.query;
  }

  APIParameter.path(this.name)
      : location = APIParameterLocation.path,
        schema = APISchemaObject.string(),
        _required = true;

  APIParameter.cookie(
    this.name, {
    this.description,
    this.schema,
    this.content,
    this.style,
    bool? isRequired,
    this.deprecated,
    this.allowEmptyValue,
    this.explode,
    this.allowReserved,
  }) : _required = isRequired {
    location = APIParameterLocation.cookie;
  }

  /// The name of the parameter.
  ///
  /// REQUIRED. Parameter names are case sensitive.
  /// If in is "path", the name field MUST correspond to the associated path segment from the path field in [APIDocument.paths]. See Path Templating for further information.
  /// If in is "header" and the name field is "Accept", "Content-Type" or "Authorization", the parameter definition SHALL be ignored.
  /// For all other cases, the name corresponds to the parameter name used by the in property.
  String? name;

  /// A brief description of the parameter.
  ///
  /// This could contain examples of use. CommonMark syntax MAY be used for rich text representation.
  String? description;

  /// Determines whether this parameter is mandatory.
  ///
  /// If the parameter location is "path", this property is REQUIRED and its value MUST be true. Otherwise, the property MAY be included and its default value is false.
  bool? get isRequired =>
      location == APIParameterLocation.path ? true : _required;

  set isRequired(bool? f) {
    _required = f;
  }

  bool? _required;

  /// Specifies that a parameter is deprecated and SHOULD be transitioned out of usage.

  bool? deprecated;

  /// The location of the parameter.
  ///
  /// REQUIRED. Possible values are "query", "header", "path" or "cookie".
  APIParameterLocation? location;

  /// The schema defining the type used for the parameter.
  APISchemaObject? schema;

  // Sets the ability to pass empty-valued parameters.
  //
  // This is valid only for query parameters and allows sending a parameter with an empty value. Default value is false. If style is used, and if behavior is n/a (cannot be serialized), the value of allowEmptyValue SHALL be ignored.
  bool? allowEmptyValue = false;

  /// Describes how the parameter value will be serialized depending on the type of the parameter value.
  ///
  /// Default values (based on value of in): for query - form; for path - simple; for header - simple; for cookie - form.
  String? style;

  /// When this is true, parameter values of type array or object generate separate parameters for each value of the array or key-value pair of the map.
  ///
  /// For other types of parameters this property has no effect. When style is form, the default value is true. For all other styles, the default value is false.
  bool? explode = false;

  /// Determines whether the parameter value SHOULD allow reserved characters, as defined by RFC3986 :/?#[]@!$&'()*+,;= to be included without percent-encoding.
  ///
  /// This property only applies to parameters with an in value of query. The default value is false.
  bool? allowReserved = false;

  /// A map containing the representations for the parameter.
  ///
  /// The key is the media type and the value describes it. The map MUST only contain one entry.
  Map<String, APIMediaType?>? content;

  // Currently missing:
  // example, examples

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    name = object.decode("name");
    description = object.decode("description");
    location = APIParameterLocationCodec.decode(object.decode("in"));
    _required = object.decode("required");

    deprecated = object.decode("deprecated");
    allowEmptyValue = object.decode("allowEmptyValue");

    schema = object.decodeObject("schema", () => APISchemaObject());
    style = object.decode("style");
    explode = object.decode("explode");
    allowReserved = object.decode("allowReserved");
    content = object.decodeObjectMap("content", () => APIMediaType());
  }

  @override
  void encode(KeyedArchive object) {
    super.encode(object);

    if (name == null || location == null) {
      throw ArgumentError(
        "APIParameter must have non-null values for: 'name', 'location'.",
      );
    }

    object.encode("name", name);
    object.encode("description", description);
    object.encode("in", APIParameterLocationCodec.encode(location));

    if (location == APIParameterLocation.path) {
      object.encode("required", true);
    } else {
      object.encode("required", _required);
    }

    object.encode("deprecated", deprecated);

    if (location == APIParameterLocation.query) {
      object.encode("allowEmptyValue", allowEmptyValue);
    }

    object.encodeObject("schema", schema);
    object.encode("style", style);
    object.encode("explode", explode);
    object.encode("allowReserved", allowReserved);
    object.encodeObjectMap("content", content);
  }
}
