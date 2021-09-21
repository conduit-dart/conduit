import 'package:conduit_codable/conduit_codable.dart';
import 'package:conduit_open_api/src/object.dart';
import 'package:conduit_open_api/src/v3/media_type.dart';
import 'package:conduit_open_api/src/v3/schema.dart';

/// Describes a single request body.
class APIRequestBody extends APIObject {
  APIRequestBody(this.content, {this.description, this.isRequired = false});

  APIRequestBody.empty();

  APIRequestBody.schema(
    APISchemaObject schema, {
    Iterable<String> contentTypes = const ["application/json"],
    this.description,
    this.isRequired = false,
  }) {
    content = contentTypes.fold({}, (prev, elem) {
      prev![elem] = APIMediaType(schema: schema);
      return prev;
    });
  }

  /// A brief description of the request body.
  ///
  /// This could contain examples of use. CommonMark syntax MAY be used for rich text representation.
  String? description;

  /// The content of the request body.
  ///
  /// REQUIRED. The key is a media type or media type range and the value describes it. For requests that match multiple keys, only the most specific key is applicable. e.g. text/plain overrides text/*
  Map<String, APIMediaType?>? content;

  /// Determines if the request body is required in the request.
  ///
  /// Defaults to false.
  bool isRequired = false;

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    description = object.decode("description");
    isRequired = object.decode("required") ?? false;
    content = object.decodeObjectMap("content", () => APIMediaType());
  }

  @override
  void encode(KeyedArchive object) {
    super.encode(object);

    if (content == null) {
      throw ArgumentError(
        "APIRequestBody must have non-null values for: 'content'.",
      );
    }

    object.encode("description", description);
    object.encode("required", isRequired);
    object.encodeObjectMap("content", content);
  }
}
