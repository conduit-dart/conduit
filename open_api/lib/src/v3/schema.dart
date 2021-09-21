import 'package:conduit_codable/cast.dart' as cast;
import 'package:conduit_codable/conduit_codable.dart';
import 'package:conduit_open_api/src/object.dart';
import 'package:conduit_open_api/src/v3/types.dart';

enum APISchemaAdditionalPropertyPolicy {
  /// When [APISchemaObject] prevents properties other than those defined by [APISchemaObject.properties] from being included
  disallowed,

  /// When [APISchemaObject] allows any additional properties
  freeForm,

  /// When [APISchemaObject.additionalPropertySchema] contains a schema object
  restricted
}

/// Represents a schema object in the OpenAPI specification.
class APISchemaObject extends APIObject {
  APISchemaObject();
  APISchemaObject.empty();

  APISchemaObject.string({this.format}) : type = APIType.string;
  APISchemaObject.number() : type = APIType.number;
  APISchemaObject.integer() : type = APIType.integer;
  APISchemaObject.boolean() : type = APIType.boolean;
  APISchemaObject.map({
    APIType? ofType,
    APISchemaObject? ofSchema,
    bool any = false,
  }) : type = APIType.object {
    if (ofType != null) {
      additionalPropertySchema = APISchemaObject()..type = ofType;
    } else if (ofSchema != null) {
      additionalPropertySchema = ofSchema;
    } else if (any) {
    } else {
      throw ArgumentError(
        "Invalid 'APISchemaObject.map' with neither 'ofType', 'any' or 'ofSchema' specified.",
      );
    }
  }
  APISchemaObject.array({APIType? ofType, APISchemaObject? ofSchema})
      : type = APIType.array {
    if (ofType != null) {
      items = APISchemaObject()..type = ofType;
    } else if (ofSchema != null) {
      items = ofSchema;
    } else {
      throw ArgumentError(
        "Invalid 'APISchemaObject.array' with neither 'ofType' or 'ofSchema' specified.",
      );
    }
  }
  APISchemaObject.object(this.properties) : type = APIType.object;
  APISchemaObject.file({bool isBase64Encoded = false})
      : type = APIType.string,
        format = isBase64Encoded ? "byte" : "binary";

  APISchemaObject.freeForm()
      : type = APIType.object,
        additionalPropertyPolicy = APISchemaAdditionalPropertyPolicy.freeForm;

  /// A title for the object.
  String? title;

  /// The value of "maximum" MUST be a number, representing an upper limit
  /// for a numeric instance.
  ///
  /// If the instance is a number, then this keyword validates if
  /// "exclusiveMaximum" is true and instance is less than the provided
  /// value, or else if the instance is less than or exactly equal to the
  /// provided value.
  num? maximum;

  ///  The value of "exclusiveMaximum" MUST be a boolean, representing
  ///  whether the limit in "maximum" is exclusive or not.
  ///
  ///  An undefined value is the same as false.
  ///
  ///  If "exclusiveMaximum" is true, then a numeric instance SHOULD NOT be
  ///  equal to the value specified in "maximum".  If "exclusiveMaximum" is
  ///  false (or not specified), then a numeric instance MAY be equal to the
  ///  value of "maximum".
  bool? exclusiveMaximum;

  /// The value of "minimum" MUST be a number, representing a lower limit
  /// for a numeric instance.

  /// If the instance is a number, then this keyword validates if
  /// "exclusiveMinimum" is true and instance is greater than the provided
  /// value, or else if the instance is greater than or exactly equal to
  /// the provided value.
  num? minimum;

  /// The value of "exclusiveMinimum" MUST be a boolean, representing
  /// whether the limit in "minimum" is exclusive or not.  An undefined
  /// value is the same as false.

  /// If "exclusiveMinimum" is true, then a numeric instance SHOULD NOT be
  /// equal to the value specified in "minimum".  If "exclusiveMinimum" is
  /// false (or not specified), then a numeric instance MAY be equal to the
  /// value of "minimum".
  bool? exclusiveMinimum;

  /// The value of this keyword MUST be a non-negative integer.
  ///
  /// The value of this keyword MUST be an integer.  This integer MUST be
  /// greater than, or equal to, 0.
  ///
  /// A string instance is valid against this keyword if its length is less
  /// than, or equal to, the value of this keyword.
  ///
  /// The length of a string instance is defined as the number of its
  /// characters as defined by RFC 7159 [RFC7159].
  int? maxLength;

  /// A string instance is valid against this keyword if its length is
  /// greater than, or equal to, the value of this keyword.
  ///
  /// The length of a string instance is defined as the number of its
  /// characters as defined by RFC 7159 [RFC7159].
  ///
  /// The value of this keyword MUST be an integer.  This integer MUST be
  /// greater than, or equal to, 0.
  ///
  /// "minLength", if absent, may be considered as being present with
  /// integer value 0.
  int? minLength;

  /// The value of this keyword MUST be a string.  This string SHOULD be a
  /// valid regular expression, according to the ECMA 262 regular
  /// expression dialect.
  ///
  /// A string instance is considered valid if the regular expression
  /// matches the instance successfully.  Recall: regular expressions are
  /// not implicitly anchored.
  String? pattern;

  /// The value of this keyword MUST be an integer.  This integer MUST be
  /// greater than, or equal to, 0.
  ///
  /// An array instance is valid against "maxItems" if its size is less
  /// than, or equal to, the value of this keyword.
  int? maxItems;

  /// The value of this keyword MUST be an integer.  This integer MUST be
  /// greater than, or equal to, 0.
  ///
  /// An array instance is valid against "minItems" if its size is greater
  /// than, or equal to, the value of this keyword.
  ///
  /// If this keyword is not present, it may be considered present with a
  /// value of 0.
  int? minItems;

  /// The value of this keyword MUST be a boolean.
  ///
  /// If this keyword has boolean value false, the instance validates
  /// successfully.  If it has boolean value true, the instance validates
  /// successfully if all of its elements are unique.

  /// If not present, this keyword may be considered present with boolean
  /// value false.
  bool? uniqueItems;

  /// The value of "multipleOf" MUST be a number, strictly greater than 0.

  /// A numeric instance is only valid if division by this keyword's value
  /// results in an integer.
  num? multipleOf;

  /// The value of this keyword MUST be an integer.  This integer MUST be
  /// greater than, or equal to, 0.
  ///
  /// An object instance is valid against "maxProperties" if its number of
  /// properties is less than, or equal to, the value of this keyword.
  int? maxProperties;

  /// The value of this keyword MUST be an integer.  This integer MUST be
  /// greater than, or equal to, 0.
  ///
  /// An object instance is valid against "minProperties" if its number of
  /// properties is greater than, or equal to, the value of this keyword.
  ///
  /// If this keyword is not present, it may be considered present with a
  /// value of 0.
  int? minProperties;

  /// The value of this keyword MUST be an array.  This array MUST have at
  /// least one element.  Elements of this array MUST be strings, and MUST
  /// be unique.
  ///
  /// An object instance is valid against this keyword if its property set
  /// contains all elements in this keyword's array value.
  List<String?>? isRequired;

  /// The value of this keyword MUST be an array.  This array SHOULD have
  /// at least one element.  Elements in the array SHOULD be unique.
  ///
  /// Elements in the array MAY be of any type, including null.
  ///
  /// An instance validates successfully against this keyword if its value
  /// is equal to one of the elements in this keyword's array value.
  List<dynamic>? enumerated;

  /* Modified JSON Schema for OpenAPI */

  APIType? type;
  List<APISchemaObject?>? allOf;
  List<APISchemaObject?>? anyOf;
  List<APISchemaObject?>? oneOf;
  APISchemaObject? not;

  APISchemaObject? items;
  Map<String, APISchemaObject?>? properties;
  APISchemaObject? additionalPropertySchema;
  APISchemaAdditionalPropertyPolicy? additionalPropertyPolicy;

  String? description;
  String? format;
  dynamic defaultValue;

  bool? get isNullable => _nullable ?? false;

  set isNullable(bool? n) {
    _nullable = n;
  }

  // APIDiscriminator discriminator;

  bool? get isReadOnly => _readOnly ?? false;

  set isReadOnly(bool? n) {
    _readOnly = n;
  }

  bool? get isWriteOnly => _writeOnly ?? false;

  set isWriteOnly(bool? n) {
    _writeOnly = n;
  }

  bool? _nullable;
  bool? _readOnly;
  bool? _writeOnly;
  bool? deprecated;

  @override
  Map<String, cast.Cast> get castMap =>
      {"required": const cast.List(cast.string)};

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    title = object.decode("title");
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
    minProperties = object.decode("minProperties");
    maxProperties = object.decode("maxProperties");
    isRequired = object.decode("required");

    //

    type = APITypeCodec.decode(object.decode("type"));
    allOf = object.decodeObjects("allOf", () => APISchemaObject());
    anyOf = object.decodeObjects("anyOf", () => APISchemaObject());
    oneOf = object.decodeObjects("oneOf", () => APISchemaObject());
    not = object.decodeObject("not", () => APISchemaObject());

    items = object.decodeObject("items", () => APISchemaObject());
    properties = object.decodeObjectMap("properties", () => APISchemaObject());

    final addlProps = object["additionalProperties"];
    if (addlProps is bool) {
      if (addlProps) {
        additionalPropertyPolicy = APISchemaAdditionalPropertyPolicy.freeForm;
      } else {
        additionalPropertyPolicy = APISchemaAdditionalPropertyPolicy.disallowed;
      }
    } else if (addlProps is KeyedArchive && addlProps.isEmpty) {
      additionalPropertyPolicy = APISchemaAdditionalPropertyPolicy.freeForm;
    } else {
      additionalPropertyPolicy = APISchemaAdditionalPropertyPolicy.restricted;
      additionalPropertySchema =
          object.decodeObject("additionalProperties", () => APISchemaObject());
    }

    description = object.decode("description");
    format = object.decode("format");
    defaultValue = object.decode("default");

    _nullable = object.decode("nullable");
    _readOnly = object.decode("readOnly");
    _writeOnly = object.decode("writeOnly");
    deprecated = object.decode("deprecated");
  }

  @override
  void encode(KeyedArchive object) {
    super.encode(object);

    object.encode("title", title);
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
    object.encode("minProperties", minProperties);
    object.encode("maxProperties", maxProperties);
    object.encode("required", isRequired);

    //

    object.encode("type", APITypeCodec.encode(type));
    object.encodeObjects("allOf", allOf);
    object.encodeObjects("anyOf", anyOf);
    object.encodeObjects("oneOf", oneOf);
    object.encodeObject("not", not);

    object.encodeObject("items", items);
    if (additionalPropertyPolicy != null || additionalPropertySchema != null) {
      if (additionalPropertyPolicy ==
          APISchemaAdditionalPropertyPolicy.disallowed) {
        object.encode("additionalProperties", false);
      } else if (additionalPropertyPolicy ==
          APISchemaAdditionalPropertyPolicy.freeForm) {
        object.encode("additionalProperties", true);
      } else {
        object.encodeObject("additionalProperties", additionalPropertySchema);
      }
    }
    object.encodeObjectMap("properties", properties);

    object.encode("description", description);
    object.encode("format", format);
    object.encode("default", defaultValue);

    object.encode("nullable", _nullable);
    object.encode("readOnly", _readOnly);
    object.encode("writeOnly", _writeOnly);
    object.encode("deprecated", deprecated);
  }
}
