import 'dart:mirrors';

import 'package:conduit_common/conduit_common.dart';
import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_core/src/runtime/orm/entity_mirrors.dart';
import 'package:conduit_open_api/v3.dart';
import 'package:test/test.dart';

void main() {
  group("GeoPoint", () {
    test("accepts boundary values", () {
      expect(GeoPoint(90, 180).latitude, 90);
      expect(GeoPoint(-90, -180).longitude, -180);
      expect(GeoPoint(0, 0).latitude, 0);
    });

    test("rejects invalid values", () {
      expect(() => GeoPoint(90.0001, 0), throwsArgumentError);
      expect(() => GeoPoint(-90.0001, 0), throwsArgumentError);
      expect(() => GeoPoint(0, 180.0001), throwsArgumentError);
      expect(() => GeoPoint(0, -180.0001), throwsArgumentError);
      expect(() => GeoPoint(double.nan, 0), throwsArgumentError);
      expect(() => GeoPoint(0, double.nan), throwsArgumentError);
      expect(() => GeoPoint(double.infinity, 0), throwsArgumentError);
      expect(() => GeoPoint(0, double.negativeInfinity), throwsArgumentError);
    });

    test("equality and hashCode", () {
      expect(GeoPoint(1, 2), GeoPoint(1, 2));
      expect(GeoPoint(1, 2).hashCode, GeoPoint(1, 2).hashCode);
      expect(GeoPoint(1, 2), isNot(GeoPoint(2, 1)));
      expect(GeoPoint(1, 2).toString(), "GeoPoint(1.0, 2.0)");
    });

    test("JSON round trip", () {
      final p = GeoPoint(12.5, -45.25);
      expect(p.toJson(), {"latitude": 12.5, "longitude": -45.25});
      expect(GeoPoint.fromJson(p.toJson()), p);
      expect(
        GeoPoint.fromJson({"latitude": 1, "longitude": 2}),
        GeoPoint(1, 2),
      );
    });

    test("fromJson rejects malformed input", () {
      expect(() => GeoPoint.fromJson({}), throwsArgumentError);
      expect(() => GeoPoint.fromJson({"latitude": 1}), throwsArgumentError);
      expect(
        () => GeoPoint.fromJson({"latitude": "1", "longitude": 2}),
        throwsArgumentError,
      );
      expect(
        () => GeoPoint.fromJson({"latitude": 100, "longitude": 2}),
        throwsArgumentError,
      );
    });
  });

  group("geography ManagedPropertyType", () {
    test("is inferred from GeoPoint", () {
      final type = getManagedTypeFromType(reflectType(GeoPoint));
      expect(type.kind, ManagedPropertyType.geography);
      expect(ManagedType.supportedDartTypes, contains(GeoPoint));
    });

    test("isAssignableWith", () {
      final type = getManagedTypeFromType(reflectType(GeoPoint));
      expect(type.isAssignableWith(GeoPoint(1, 2)), true);
      expect(type.isAssignableWith(null), true);
      expect(type.isAssignableWith({"latitude": 1, "longitude": 2}), false);
      expect(type.isAssignableWith("1,2"), false);
      expect(type.isAssignableWith(1.0), false);
    });

    test("SchemaColumn type string round trip", () {
      expect(
        SchemaColumn.typeStringForType(ManagedPropertyType.geography),
        "geography",
      );
      expect(
        SchemaColumn.typeFromTypeString("geography"),
        ManagedPropertyType.geography,
      );
      final column = SchemaColumn.empty()
        ..name = "location"
        ..type = ManagedPropertyType.geography;
      final map = column.asMap();
      expect(map["type"], "geography");
      expect(SchemaColumn.fromMap(map).type, ManagedPropertyType.geography);
    });

    test("primitive conversion", () {
      final entity = ManagedDataModel([_Place]).entityForType(_Place);
      final prop = entity.attributes["location"]!;
      expect(prop.type!.kind, ManagedPropertyType.geography);
      expect(prop.convertToPrimitiveValue(GeoPoint(1, 2)), {
        "latitude": 1.0,
        "longitude": 2.0,
      });
      expect(
        prop.convertFromPrimitiveValue({"latitude": 1, "longitude": 2}),
        GeoPoint(1, 2),
      );
      expect(prop.convertFromPrimitiveValue(null), isNull);
      expect(
        () => prop.convertFromPrimitiveValue("1,2"),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => prop.convertFromPrimitiveValue({"latitude": 1}),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => prop.convertFromPrimitiveValue({"latitude": 91, "longitude": 0}),
        throwsA(isA<ValidationException>()),
      );
    });

    test("OpenAPI schema", () {
      final entity = ManagedDataModel([_Place]).entityForType(_Place);
      final schema = entity.attributes["location"]!.documentSchemaObject(
        APIDocumentContext(
          APIDocument()
            ..info = APIInfo("x", "1.0.0")
            ..paths = {}
            ..components = APIComponents(),
        ),
      );
      expect(schema.type, APIType.object);
      expect(schema.properties!["latitude"]!.minimum, -90);
      expect(schema.properties!["longitude"]!.maximum, 180);
      expect(schema.isRequired, ["latitude", "longitude"]);
    });
  });
}

class _Place extends ManagedObject<_$Place> implements _$Place;

class _$Place {
  @primaryKey
  int? id;

  GeoPoint? location;
}
