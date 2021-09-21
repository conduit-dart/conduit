import 'dart:collection';

import 'package:conduit_codable/cast.dart' as cast;
import 'package:conduit_codable/src/codable.dart';
import 'package:conduit_codable/src/coding.dart';
import 'package:conduit_codable/src/list.dart';
import 'package:conduit_codable/src/resolver.dart';

/// A container for a dynamic data object that can be decoded into [Coding] objects.
///
/// A [KeyedArchive] is a [Map], but it provides additional behavior for decoding [Coding] objects
/// and managing JSON Schema references ($ref) through methods like [decode], [decodeObject], etc.
///
/// You create a [KeyedArchive] by invoking [KeyedArchive.unarchive] and passing data decoded from a
/// serialization format like JSON and YAML. A [KeyedArchive] is then provided as an argument to
/// a [Coding] subclass' [Coding.decode] method.
///
///         final json = json.decode(...);
///         final archive = KeyedArchive.unarchive(json);
///         final person = Person()..decode(archive);
///
/// You may also create [KeyedArchive]s from [Coding] objects so that they can be serialized.
///
///         final person = Person()..name = "Bob";
///         final archive = KeyedArchive.archive(person);
///         final json = json.encode(archive);
///
class KeyedArchive extends Object
    with MapMixin<String, dynamic>
    implements Referencable {
  /// Use [unarchive] instead.
  KeyedArchive(this._map) {
    _recode();
  }

  /// Unarchives [data] into a [KeyedArchive] that can be used by [Coding.decode] to deserialize objects.
  ///
  /// Each [Map] in [data] (including [data] itself) is converted to a [KeyedArchive].
  /// Each [List] in [data] is converted to a [ListArchive]. These conversions occur for deeply nested maps
  /// and lists.
  ///
  /// If [allowReferences] is true, JSON Schema references will be traversed and decoded objects
  /// will contain values from the referenced object. This flag defaults to false.
  KeyedArchive.unarchive(this._map, {bool allowReferences = false}) {
    _recode();
    if (allowReferences) {
      resolveOrThrow(ReferenceResolver(this));
    }
  }

  /// Archives a [Coding] object into a [Map] that can be serialized into format like JSON or YAML.
  ///
  /// Note that the return value of this method, as well as all other [Map] and [List] objects
  /// embedded in the return value, are instances of [KeyedArchive] and [ListArchive]. These types
  /// implement [Map] and [List], respectively.
  ///
  /// If [allowReferences] is true, JSON Schema references in the emitted document will be validated.
  /// Defaults to false.
  static Map<String, dynamic> archive(
    Coding root, {
    bool allowReferences = false,
  }) {
    final archive = KeyedArchive({});
    root.encode(archive);
    if (allowReferences) {
      archive.resolveOrThrow(ReferenceResolver(archive));
    }
    return archive.toPrimitive();
  }

  KeyedArchive._empty() : _map = <String, dynamic>{};

  /// A reference to another object in the same document.
  ///
  /// This value is a path-only [Uri]. Each path segment is a key, starting
  /// at the document root this object belongs to. For example, the path '/components/all'
  /// would reference the object as returned by `document['components']['all']`.
  ///
  /// Assign values to this property using the default [Uri] constructor and its path argument.
  /// This property is serialized as a [Uri] fragment, e.g. `#/components/all`.
  ///
  /// Example:
  ///
  ///         final object = new MyObject()
  ///           ..referenceURI = Uri(path: "/other/object");
  ///         archive.encodeObject("object", object);
  ///
  Uri? referenceURI;

  Map<String, dynamic> _map;
  Coding? _inflated;
  KeyedArchive? _objectReference;

  /// Typecast the values in this archive.
  ///
  /// Prefer to override [Coding.castMap] instead of using this method directly.
  ///
  /// This method will recursively type values in this archive to the desired type
  /// for a given key. Use this method (or [Coding.castMap]) for decoding `List` and `Map`
  /// types, where the values are not `Coding` objects.
  ///
  /// You must `import 'package:codable/cast.dart' as cast;`.
  ///
  /// Usage:
  ///
  ///         final dynamicObject = {
  ///           "key": <dynamic>["foo", "bar"]
  ///         };
  ///         final archive = KeyedArchive.unarchive(dynamicObject);
  ///         archive.castValues({
  ///           "key": cast.List(cast.String)
  ///         });
  ///
  ///         // This now becomes a valid assignment
  ///         List<String> key = archive.decode("key");
  ///
  void castValues(Map<String, cast.Cast>? schema) {
    if (schema == null) {
      return;
    }

    final caster = cast.Keyed(schema);
    _map = caster.cast(_map);

    if (_objectReference != null) {
      // todo: can optimize this by only running it once
      _objectReference!._map = caster.cast(_objectReference!._map);
    }
  }

  /// store the [key]/[value] pair into the map
  @override
  void operator []=(covariant String key, dynamic value) {
    _map[key] = value;
  }

  @override
  dynamic operator [](covariant Object key) => _getValue(key as String);

  @override
  Iterable<String> get keys => _map.keys;

  @override
  void clear() => _map.clear();

  @override
  dynamic remove(Object? key) => _map.remove(key);

  Map<String, dynamic> toPrimitive() {
    final out = <String, dynamic>{};
    _map.forEach((key, val) {
      if (val is KeyedArchive) {
        out[key] = val.toPrimitive();
      } else if (val is ListArchive) {
        out[key] = val.toPrimitive();
      } else {
        out[key] = val;
      }
    });
    return out;
  }

  dynamic _getValue(String? key) {
    if (_map.containsKey(key)) {
      return _map[key];
    }

    return _objectReference?._getValue(key);
  }

  void _recode() {
    const caster = cast.Map(cast.string, cast.any);
    final keys = _map.keys.toList();
    for (final key in keys) {
      final val = _map[key];
      if (val is Map) {
        _map[key] = KeyedArchive(caster.cast(val));
      } else if (val is List) {
        _map[key] = ListArchive.from(val);
      } else if (key == r"$ref") {
        referenceURI = Uri.parse(Uri.parse(val.toString()).fragment);
      }
    }
  }

  /// Validates [referenceURI]s for this object and any objects it contains.
  ///
  /// This method is automatically invoked by both [KeyedArchive.unarchive] and [KeyedArchive.archive].
  @override
  void resolveOrThrow(ReferenceResolver coder) {
    if (referenceURI != null) {
      _objectReference = coder.resolve(referenceURI!);
      if (_objectReference == null) {
        throw ArgumentError(
          "Invalid document. Reference '#${referenceURI!.path}' does not exist in document.",
        );
      }
    }

    _map.forEach((key, val) {
      if (val is KeyedArchive) {
        val.resolveOrThrow(coder);
      } else if (val is ListArchive) {
        val.resolveOrThrow(coder);
      }
    });
  }

  /* decode */

  T? _decodedObject<T extends Coding?>(
    KeyedArchive? raw,
    T Function() inflate,
  ) {
    if (raw == null) {
      return null;
    }

    if (raw._inflated == null) {
      raw._inflated = inflate();
      raw._inflated!.decode(raw);
    }

    return raw._inflated as T?;
  }

  /// Returns the object associated by [key].
  ///
  /// If [T] is inferred to be a [Uri] or [DateTime],
  /// the associated object is assumed to be a [String] and an appropriate value is parsed
  /// from that string.
  ///
  /// If this object is a reference to another object (via [referenceURI]), this object's key-value
  /// pairs will be searched first. If [key] is not found, the referenced object's key-values pairs are searched.
  /// If no match is found, null is returned.
  T? decode<T>(String key) {
    final v = _getValue(key);
    if (v == null) {
      return null;
    }

    if (T == Uri) {
      return Uri.parse(v.toString()) as T;
    } else if (T == DateTime) {
      return DateTime.parse(v.toString()) as T;
    }

    return v as T?;
  }

  /// Returns the instance of [T] associated with [key].
  ///
  /// [inflate] must create an empty instance of [T]. The value associated with [key]
  /// must be a [KeyedArchive] (a [Map]). The values of the associated object are read into
  /// the empty instance of [T].
  T? decodeObject<T extends Coding>(String key, T Function() inflate) {
    final val = _getValue(key);
    if (val == null) {
      return null;
    }

    if (val is! KeyedArchive) {
      throw ArgumentError(
        "Cannot decode key '$key' into '$T', because the value is not a Map. Actual value: '$val'.",
      );
    }

    return _decodedObject(val, inflate);
  }

  /// Returns a list of [T]s associated with [key].
  ///
  /// [inflate] must create an empty instance of [T]. The value associated with [key]
  /// must be a [ListArchive] (a [List] of [Map]). For each element of the archived list,
  /// [inflate] is invoked and each object in the archived list is decoded into
  /// the instance of [T].
  List<T?>? decodeObjects<T extends Coding>(String key, T? Function() inflate) {
    final val = _getValue(key);
    if (val == null) {
      return null;
    }
    if (val is! List) {
      throw ArgumentError(
        "Cannot decode key '$key' as 'List<$T>', because value is not a List. Actual value: '$val'.",
      );
    }

    return val
        .map((v) => _decodedObject(v as KeyedArchive?, inflate))
        .toList()
        .cast<T?>();
  }

  /// Returns a map of [T]s associated with [key].
  ///
  /// [inflate] must create an empty instance of [T]. The value associated with [key]
  /// must be a [KeyedArchive] (a [Map]), where each value is a [T].
  /// For each key-value pair of the archived map, [inflate] is invoked and
  /// each value is decoded into the instance of [T].
  Map<String, T?>? decodeObjectMap<T extends Coding>(
    String key,
    T Function() inflate,
  ) {
    final v = _getValue(key);
    if (v == null) {
      return null;
    }

    if (v is! Map<String, dynamic>) {
      throw ArgumentError(
        "Cannot decode key '$key' as 'Map<String, $T>', because value is not a Map. Actual value: '$v'.",
      );
    }

    return {
      for (var k in v.keys) k: _decodedObject(v[k] as KeyedArchive?, inflate)
    };
  }

  /* encode */

  Map<String?, dynamic>? _encodedObject(Coding? object) {
    if (object == null) {
      return null;
    }

    // todo: an object can override the values it inherits from its
    // reference object. These values are siblings to the $ref key.
    // they are currently not being emitted. the solution is probably tricky.
    // letting encode run as normal would stack overflow when there is a cyclic
    // reference between this object and another.
    final json = KeyedArchive._empty()
      .._map = {}
      ..referenceURI = object.referenceURI;
    if (json.referenceURI != null) {
      json._map[r"$ref"] = Uri(fragment: json.referenceURI!.path).toString();
    } else {
      object.encode(json);
    }
    return json;
  }

  /// Encodes [value] into this object for [key].
  ///
  /// If [value] is a [DateTime], it is first encoded as an ISO 8601 string.
  /// If [value] is a [Uri], it is first encoded to a string.
  ///
  /// If [value] is null, no value is encoded and the [key] will not be present
  /// in the resulting archive.
  void encode(String key, dynamic value) {
    if (value == null) {
      return;
    }

    if (value is DateTime) {
      _map[key] = value.toIso8601String();
    } else if (value is Uri) {
      _map[key] = value.toString();
    } else {
      _map[key] = value;
    }
  }

  /// Encodes a [Coding] object into this object for [key].
  ///
  /// This invokes [Coding.encode] on [value] and adds the object
  /// to this archive for the key [key].
  void encodeObject(String key, Coding? value) {
    if (value == null) {
      return;
    }

    _map[key] = _encodedObject(value);
  }

  /// Encodes list of [Coding] objects into this object for [key].
  ///
  /// This invokes [Coding.encode] on each object in [value] and adds the list of objects
  /// to this archive for the key [key].
  void encodeObjects(String key, List<Coding?>? value) {
    if (value == null) {
      return;
    }

    _map[key] = ListArchive.from(value.map((v) => _encodedObject(v)).toList());
  }

  /// Encodes map of [Coding] objects into this object for [key].
  ///
  /// This invokes [Coding.encode] on each value in [value] and adds the map of objects
  /// to this archive for the key [key].
  void encodeObjectMap<T extends Coding?>(String key, Map<String, T>? value) {
    if (value == null) {
      return;
    }

    final object = KeyedArchive({});
    value.forEach((k, v) {
      object[k] = _encodedObject(v);
    });

    _map[key] = object;
  }
}
