import 'dart:convert';

import 'package:conduit_codable/cast.dart' as cast;
import 'package:conduit_codable/conduit_codable.dart';
import 'package:test/test.dart';

void main() {
  group("Primitive decode", () {
    test("Can decode primitive type", () {
      final archive = getJSONArchive({"key": 2});
      final int? val = archive.decode("key");
      expect(val, 2);
    });

    test("Can decode List<dynamic> type", () {
      final archive = getJSONArchive({
        "key": [1, "2"]
      });
      final List<dynamic>? l = archive.decode("key");
      expect(l, [1, "2"]);
    });

    test("Can decode Map<String, dynamic>", () {
      final archive = getJSONArchive({
        "key": {"key": "val"}
      });
      final KeyedArchive? d = archive.decode("key");
      expect(d, {"key": "val"});
    });

    test("Can decode URI", () {
      final archive = getJSONArchive({"key": "https://host.com"});
      final Uri? d = archive.decode("key");
      expect(d!.host, "host.com");
    });

    test("Can decode DateTime", () {
      final date = DateTime.now();
      final archive = getJSONArchive({"key": date.toIso8601String()});
      final DateTime? d = archive.decode("key");
      expect(d!.isAtSameMomentAs(date), true);
    });

    test("If value is null, return null from decode", () {
      final archive = getJSONArchive({"key": null});
      final int? val = archive.decode("key");
      expect(val, isNull);
    });

    test("If archive does not contain key, return null from decode", () {
      final archive = getJSONArchive({});
      final int? val = archive.decode("key");
      expect(val, isNull);
    });
  });

  group("Primitive map decode", () {
    test("Can decode Map<String, String> from Map<String, dynamic>", () {
      final archive = getJSONArchive({
        "key": {"key": "val"}
      });
      archive.castValues({"key": const cast.Map(cast.string, cast.string)});
      final Map<String, String>? d = archive.decode("key");
      expect(d, {"key": "val"});
    });

    test("Can decode Map<String, List<String>>", () {
      final archive = getJSONArchive({
        "key": {
          "key": ["val"]
        }
      });
      archive.castValues(
        {"key": const cast.Map(cast.string, cast.List(cast.string))},
      );
      final Map<String, List<String?>>? d = archive.decode("key");
      expect(d, {
        "key": ["val"]
      });
    });

    test("Can decode Map<String, List<String?>> where elements are null", () {
      final archive = getJSONArchive({
        "key": {
          "key": [null, null]
        }
      });
      archive.castValues(
        {"key": const cast.Map(cast.string, cast.List(cast.string))},
      );
      final Map<String, List<String?>>? d = archive.decode("key");
      expect(d, {
        "key": [null, null]
      });
    });

    test("Can decode Map<String, Map<String, List<String?>>>", () {
      final archive = getJSONArchive({
        "key": {
          "key": {
            "key": ["val", null]
          }
        }
      });
      archive.castValues({
        "key": const cast.Map(
          cast.string,
          cast.Map(cast.string, cast.List(cast.string)),
        )
      });
      final Map<String, Map<String, List<String?>>>? d = archive.decode("key");
      expect(d, {
        "key": {
          "key": ["val", null]
        }
      });
    });
  });

  group("Primitive list decode", () {
    test("Can decode List<String> from List<dynamic>", () {
      final archive = getJSONArchive({
        "key": ["val", null]
      });
      archive.castValues({"key": const cast.List(cast.string)});
      final List<String?>? d = archive.decode("key");
      expect(d, ["val", null]);
    });

    test("Can decode List<Map<String, List<String>>>", () {
      final archive = getJSONArchive({
        "key": [
          {
            "key": ["val", null]
          },
          null
        ]
      });
      archive.castValues({
        "key": const cast.List(cast.Map(cast.string, cast.List(cast.string)))
      });
      final List<Map<String, List<String?>>?>? d = archive.decode("key");
      expect(d, [
        {
          "key": ["val", null]
        },
        null
      ]);
    });
  });

  group("Coding objects", () {
    test("Can decode Coding object", () {
      final archive = getJSONArchive({
        "key": {"name": "Bob"}
      });
      final Parent p = archive.decodeObject("key", () => Parent())!;
      expect(p.name, "Bob");
      expect(p.child, isNull);
      expect(p.children, isNull);
      expect(p.childMap, isNull);
    });

    test("If coding object is paired with non-Map, an exception is thrown", () {
      final archive = getJSONArchive({
        "key": [
          {"name": "Bob"}
        ]
      });
      try {
        archive.decodeObject("key", () => Parent());
        fail('unreachable');
      } on ArgumentError {
        // no action required
      }
    });

    test("Can decode list of Coding objects", () {
      final archive = getJSONArchive({
        "key": [
          {"name": "Bob"},
          null,
          {"name": "Sally"}
        ]
      });
      final List<Parent?>? p = archive.decodeObjects("key", () => Parent());
      expect(p![0]!.name, "Bob");
      expect(p[1], isNull);
      expect(p[2]!.name, "Sally");
    });

    test(
        "If coding object list is paired with non-List, an exception is thrown",
        () {
      final archive = getJSONArchive({
        "key": {"name": "Bob"}
      });
      try {
        archive.decodeObjects("key", () => Parent());
        fail('unreachable');
      } on ArgumentError {
        // no op
      }
    });

    test(
        "If any element of coding list is not a coding object, an exception is thrown",
        () {
      final archive = getJSONArchive({
        "key": [
          {"name": "Bob"},
          'foo'
        ]
      });
      try {
        archive.decodeObjects("key", () => Parent());
        fail('unreachable');
      } on TypeError {
        // no op
      }
    });

    test("Can decode map of Coding objects", () {
      final archive = getJSONArchive({
        "key": {
          "1": {"name": "Bob"},
          "2": null
        }
      });

      final map = archive.decodeObjectMap("key", () => Parent())!;
      expect(map.length, 2);
      expect(map["1"]!.name, "Bob");
      expect(map["2"], isNull);
    });

    test("If coding object map is paired with non-Map, an exception is thrown",
        () {
      final archive = getJSONArchive({"key": []});
      try {
        archive.decodeObjectMap("key", () => Parent());
        fail('unreachable');
      } on ArgumentError {
        // no op
      }
    });

    test(
        "If any element of coding map is not a coding object, an exception is thrown",
        () {
      final archive = getJSONArchive({
        "key": {"1": "2"}
      });
      try {
        archive.decodeObjectMap("key", () => Parent());
        fail('unreachable');
      } on TypeError {
        // no op
      }
    });
  });

  group("Deep Coding objects", () {
    test("Can decode single nested object", () {
      final archive = getJSONArchive({
        "key": {
          "name": "Bob",
          "child": {"name": "Sally"}
        }
      });

      final o = archive.decodeObject("key", () => Parent())!;
      expect(o.name, "Bob");
      expect(o.child!.name, "Sally");
      expect(o.childMap, isNull);
      expect(o.children, isNull);
    });

    test("Can decode list of nested objects", () {
      final archive = getJSONArchive({
        "key": {
          "name": "Bob",
          "children": [
            {"name": "Sally"}
          ]
        }
      });

      final o = archive.decodeObject("key", () => Parent())!;
      expect(o.name, "Bob");
      expect(o.child, isNull);
      expect(o.childMap, isNull);
      expect(o.children!.length, 1);
      expect(o.children?.first?.name, "Sally");
    });

    test("Can decode map of nested objects", () {
      final archive = getJSONArchive({
        "key": {
          "name": "Bob",
          "childMap": {
            "sally": {"name": "Sally"}
          }
        }
      });

      final o = archive.decodeObject("key", () => Parent())!;
      expect(o.name, "Bob");
      expect(o.children, isNull);
      expect(o.child, isNull);
      expect(o.childMap!.length, 1);
      expect(o.childMap!["sally"]!.name, "Sally");
    });
  });

  group("Coding object references", () {
    test("Parent can contain reference to child in single object decode", () {
      final archive = getJSONArchive(
        {
          "child": {"name": "Sally"},
          "parent": {
            "name": "Bob",
            "child": {"\$ref": "#/child"}
          }
        },
        allowReferences: true,
      );

      final p = archive.decodeObject("parent", () => Parent())!;
      expect(p.name, "Bob");
      expect(p.child!.name, "Sally");
      expect(p.child!.parent, isNull);
    });

    test(
        "If reference doesn't exist, an error is thrown when creating document",
        () {
      try {
        getJSONArchive(
          {
            "parent": {
              "name": "Bob",
              "child": {"\$ref": "#/child"}
            }
          },
          allowReferences: true,
        );
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("/child"));
      }
    });

    test("Parent can contain reference to child in a list of objects", () {
      final archive = getJSONArchive(
        {
          "child": {"name": "Sally"},
          "parent": {
            "name": "Bob",
            "children": [
              {"\$ref": "#/child"},
              {"name": "fred"}
            ]
          }
        },
        allowReferences: true,
      );

      final p = archive.decodeObject("parent", () => Parent())!;
      expect(p.name, "Bob");
      expect(p.children?.first?.name, "Sally");
      expect(p.children?.last?.name, "fred");
    });

    test("Cyclical references are resolved", () {
      final archive = getJSONArchive(
        {
          "child": {
            "name": "Sally",
            "parent": {"\$ref": "#/parent"}
          },
          "parent": {
            "name": "Bob",
            "children": [
              {"\$ref": "#/child"},
              {"name": "fred"}
            ]
          }
        },
        allowReferences: true,
      );

      final p = archive.decodeObject("parent", () => Parent())!;
      expect(p.name, "Bob");
      expect(p.children?.first?.name, "Sally");
      expect(p.children?.first?.parent!.name, "Bob");
      expect(p.children?.last?.name, "fred");

      expect(p.hashCode, isNot(p.children?.first?.parent.hashCode));
    });

    test("Can override castMap to coerce values", () {
      final archive = getJSONArchive({
        "key": {
          "name": "Bob",
          "things": ["value"]
        }
      });
      final p = archive.decodeObject("key", () => Parent())!;
      expect(p.things, ["value"]);
    });
  });
}

/// Strips type info from data
KeyedArchive getJSONArchive(dynamic data, {bool allowReferences = false}) {
  return KeyedArchive.unarchive(
    json.decode(json.encode(data)) as Map<String, dynamic>,
    allowReferences: allowReferences,
  );
}

class Parent extends Coding {
  String? name;
  Child? child;
  List<Child?>? children;
  Map<String?, Child?>? childMap;
  List<String?>? things;

  @override
  Map<String, cast.Cast<dynamic>> get castMap {
    return {"things": const cast.List(cast.string)};
  }

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    name = object.decode("name");
    child = object.decodeObject("child", () => Child());
    children = object.decodeObjects("children", () => Child());
    childMap = object.decodeObjectMap("childMap", () => Child());
    things = object.decode("things");
  }

  @override
  void encode(KeyedArchive object) {}
}

class Child extends Coding {
  String? name;

  Parent? parent;

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    name = object.decode("name");
    parent = object.decodeObject("parent", () => Parent());
  }

  @override
  void encode(KeyedArchive object) {}
}
