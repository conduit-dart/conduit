import 'package:conduit_codable/conduit_codable.dart';
import 'package:conduit_open_api/src/object.dart';
import 'package:conduit_open_api/src/v2/types.dart';

enum APISchemaRepresentation {
  primitive,
  array,
  object,
  structure,
  unknownOrInvalid
}

enum APICollectionFormat { csv, ssv, tsv, pipes }

class APICollectionFormatCodec {
  static APICollectionFormat? decode(String? location) {
    switch (location) {
      case "csv":
        return APICollectionFormat.csv;
      case "ssv":
        return APICollectionFormat.ssv;
      case "tsv":
        return APICollectionFormat.tsv;
      case "pipes":
        return APICollectionFormat.pipes;
      default:
        return null;
    }
  }

  static String? encode(APICollectionFormat? location) {
    switch (location) {
      case APICollectionFormat.csv:
        return "csv";
      case APICollectionFormat.ssv:
        return "ssv";
      case APICollectionFormat.tsv:
        return "tsv";
      case APICollectionFormat.pipes:
        return "pipes";
      default:
        return null;
    }
  }
}

class APIProperty extends APIObject {
  APIType? type;
  String? format;

  APICollectionFormat? collectionFormat;
  dynamic defaultValue;
  num? maximum;
  bool? exclusiveMaximum;
  num? minimum;
  bool? exclusiveMinimum;
  int? maxLength;
  int? minLength;
  String? pattern;
  int? maxItems;
  int? minItems;
  bool? uniqueItems;
  num? multipleOf;
  List<dynamic>? enumerated;

  APISchemaRepresentation get representation {
    if (type == APIType.array) {
      return APISchemaRepresentation.array;
    } else if (type == APIType.object) {
      return APISchemaRepresentation.object;
    }

    return APISchemaRepresentation.primitive;
  }

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    type = APITypeCodec.decode(object.decode("type"));
    format = object.decode("format");
    collectionFormat =
        APICollectionFormatCodec.decode(object.decode("collectionFormat"));
    defaultValue = object.decode("default");
    maximum = object.decode("maximum");
    exclusiveMaximum = object.decode("exclusiveMaximum");
    minimum = object.decode("minimum");
    exclusiveMinimum = object.decode("exclusiveMinimum");
    maxLength = object.decode("maxLength");
    minLength = object.decode("minLength");
    pattern = object.decode("pattern");
    maxItems = object.decode("maxItems");
    minItems = object.decode("minItems");
    uniqueItems = object.decode("uniqueItems");
    multipleOf = object.decode("multipleOf");
    enumerated = object.decode("enum");
  }

  @override
  void encode(KeyedArchive object) {
    super.encode(object);

    object.encode("type", APITypeCodec.encode(type));
    object.encode("format", format);
    object.encode(
      "collectionFormat",
      APICollectionFormatCodec.encode(collectionFormat),
    );
    object.encode("default", defaultValue);
    object.encode("maximum", maximum);
    object.encode("exclusiveMaximum", exclusiveMaximum);
    object.encode("minimum", minimum);
    object.encode("exclusiveMinimum", exclusiveMinimum);
    object.encode("maxLength", maxLength);
    object.encode("minLength", minLength);
    object.encode("pattern", pattern);
    object.encode("maxItems", maxItems);
    object.encode("minItems", minItems);
    object.encode("uniqueItems", uniqueItems);
    object.encode("multipleOf", multipleOf);
    object.encode("enum", enumerated);
  }
}
