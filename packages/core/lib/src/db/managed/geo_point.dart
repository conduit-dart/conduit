/// A geographic coordinate pair, in degrees (WGS 84).
///
/// [GeoPoint]s may be properties of a [ManagedObject] table definition. They
/// are immutable and validated on construction: [latitude] must be within
/// -90 and 90, and [longitude] within -180 and 180 (both inclusive).
///
///         class Place extends ManagedObject<_Place> implements _Place {}
///         class _Place {
///           @primaryKey
///           int id;
///
///           GeoPoint location;
///         }
///
/// The JSON representation is `{"latitude": 1.0, "longitude": 2.0}`.
class GeoPoint {
  /// Creates a point.
  ///
  /// Throws an [ArgumentError] if either value is NaN or out of range.
  new(this.latitude, this.longitude) {
    if (latitude.isNaN || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(
        latitude,
        "latitude",
        "must be between -90 and 90",
      );
    }
    if (longitude.isNaN || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(
        longitude,
        "longitude",
        "must be between -180 and 180",
      );
    }
  }

  /// Creates a point from its JSON form, as emitted by [toJson].
  ///
  /// Throws an [ArgumentError] if [json] is missing a key, a value is not a
  /// number, or a value is out of range.
  factory fromJson(Map<String, dynamic> json) {
    final lat = json["latitude"];
    final lon = json["longitude"];
    if (lat is! num || lon is! num) {
      throw ArgumentError.value(
        json,
        "json",
        "must contain numeric 'latitude' and 'longitude'",
      );
    }
    return GeoPoint(lat.toDouble(), lon.toDouble());
  }

  /// Degrees north (positive) or south (negative) of the equator.
  final double latitude;

  /// Degrees east (positive) or west (negative) of the prime meridian.
  final double longitude;

  /// The JSON form of this point.
  Map<String, dynamic> toJson() => {
    "latitude": latitude,
    "longitude": longitude,
  };

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => "GeoPoint($latitude, $longitude)";
}
