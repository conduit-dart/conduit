import 'dart:convert';

import 'package:conduit_codable/conduit_codable.dart';
import 'package:test/test.dart';

void main() {
  group("Primitive encode", () {
    test("Can encode primitive type", () {
      final out = encode((obj) {
        obj.encode("int", 1);
        obj.encode("string", "1");
      });

      expect(out, {"int": 1, "string": "1"});
    });

    test("Can encode List<dynamic> type", () {
      final out = encode((obj) {
        obj.encode("key", [1, "2"]);
      });

      expect(out, {
        "key": [1, "2"]
      });
    });

    test("Can encode Map<String, dynamic>", () {
      final out = encode((obj) {
        obj.encode("key", {"1": 1, "2": "2"});
      });

      expect(out, {
        "key": {"1": 1, "2": "2"}
      });
    });

    test("Can encode URI", () {
      final out = encode((obj) {
        obj.encode("key", Uri.parse("https://host.com"));
      });

      expect(out, {"key": "https://host.com"});
    });

    test("Can encode DateTime", () {
      final out = encode((obj) {
        obj.encode("key", DateTime(2000));
      });

      expect(out, {"key": DateTime(2000).toIso8601String()});
    });

    test("If value is null, do not include key", () {
      final out = encode((obj) {
        obj.encode("key", null);
      });

      expect(out, {});
    });
  });

  group("Coding objects", () {
    test("Can encode Coding object", () {
      final out = encode((object) {
        object.encodeObject("key", Parent("Bob"));
      });

      expect(out, {
        "key": {"name": "Bob"}
      });
    });

    test("Can encode list of Coding objects", () {
      final out = encode((object) {
        object.encodeObject(
          "key",
          Parent("Bob", children: [Child("Fred"), null, Child("Sally")]),
        );
      });

      expect(out, {
        "key": {
          "name": "Bob",
          "children": [
            {"name": "Fred"},
            null,
            {"name": "Sally"}
          ]
        }
      });
    });

    test("Can encode map of Coding objects", () {
      final out = encode((object) {
        object.encodeObject(
          "key",
          Parent(
            "Bob",
            childMap: {
              "fred": Child("Fred"),
              "null": null,
              "sally": Child("Sally")
            },
          ),
        );
      });

      expect(out, {
        "key": {
          "name": "Bob",
          "childMap": {
            "fred": {"name": "Fred"},
            "null": null,
            "sally": {"name": "Sally"}
          }
        }
      });
    });
  });

  group("Coding object references", () {
    test("Parent can contain reference to child in single object encode", () {
      final container = Container(
        Parent(
          "Bob",
          child: Child._()..referenceURI = Uri(path: "/definitions/child"),
        ),
        {"child": Child("Sally")},
      );

      final out = KeyedArchive.archive(container, allowReferences: true);
      expect(out, {
        "definitions": {
          "child": {"name": "Sally"}
        },
        "root": {
          "name": "Bob",
          "child": {"\$ref": "#/definitions/child"}
        }
      });
    });

    test(
        "If reference doesn't exist, an error is thrown when creating document",
        () {
      final container = Container(
        Parent(
          "Bob",
          child: Child._()..referenceURI = Uri(path: "/definitions/child"),
        ),
        {},
      );

      try {
        KeyedArchive.archive(container, allowReferences: true);
        fail('unreachable');
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("#/definitions/child"));
      }
    });

    test(
        "If reference doesn't exist in objectMap, an error is thrown when creating document",
        () {
      final container = Container(
        Parent(
          "Bob",
          childMap: {
            "c": Child._()..referenceURI = Uri(path: "/definitions/child")
          },
        ),
        {},
      );

      try {
        KeyedArchive.archive(container, allowReferences: true);
        fail('unreachable');
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("#/definitions/child"));
      }
    });

    test(
        "If reference doesn't exist in objectList, an error is thrown when creating document",
        () {
      final container = Container(
        Parent(
          "Bob",
          children: [Child._()..referenceURI = Uri(path: "/definitions/child")],
        ),
        {},
      );

      try {
        KeyedArchive.archive(container, allowReferences: true);
        fail('unreachable');
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("#/definitions/child"));
      }
    });

    test("Parent can contain reference to child in a list of objects", () {
      final container = Container(
        Parent(
          "Bob",
          children: [
            Child("Sally"),
            Child._()..referenceURI = Uri(path: "/definitions/child")
          ],
        ),
        {"child": Child("Fred")},
      );

      final out = KeyedArchive.archive(container, allowReferences: true);
      expect(out, {
        "definitions": {
          "child": {"name": "Fred"}
        },
        "root": {
          "name": "Bob",
          "children": [
            {"name": "Sally"},
            {"\$ref": "#/definitions/child"}
          ]
        }
      });
    });

    test("Parent can contain reference to child in a map of objects", () {
      final container = Container(
        Parent(
          "Bob",
          childMap: {
            "sally": Child("Sally"),
            "ref": Child._()..referenceURI = Uri(path: "/definitions/child")
          },
        ),
        {"child": Child("Fred")},
      );

      final out = KeyedArchive.archive(container, allowReferences: true);
      expect(out, {
        "definitions": {
          "child": {"name": "Fred"}
        },
        "root": {
          "name": "Bob",
          "childMap": {
            "sally": {"name": "Sally"},
            "ref": {"\$ref": "#/definitions/child"}
          }
        }
      });
    });

    test("Cyclical references are resolved", () {
      final container = Container(
          Parent(
            "Bob",
            children: [
              Child("Sally"),
              Child._()..referenceURI = Uri(path: "/definitions/child")
            ],
          ),
          {
            "child": Child(
              "Fred",
              parent: Parent._()..referenceURI = Uri(path: "/root"),
            )
          });

      final out = KeyedArchive.archive(container, allowReferences: true);
      final expected = {
        "definitions": {
          "child": {
            "name": "Fred",
            "parent": {"\$ref": "#/root"}
          }
        },
        "root": {
          "name": "Bob",
          "children": [
            {"name": "Sally"},
            {"\$ref": "#/definitions/child"},
          ]
        }
      };
      expect(out, expected);

      // we'll also ensure that writing it out and reading it back in
      // works, to complete the lifecycle of a document. we are ensuring
      // that no state is accumulated in decoding that impacts encoding
      // and ensure that our data is valid json
      final washedData = json.decode(json.encode(out)) as Map<String, dynamic>;
      final doc = KeyedArchive.unarchive(washedData);
      final decodedContainer = Container._()..decode(doc);
      final reencodedArchive = KeyedArchive.archive(decodedContainer);
      expect(reencodedArchive, expected);
    });
  });

  test("toPrimitive does not include keyed archives or lists", () {
    final archive = KeyedArchive.unarchive({
      "value": "v",
      "archive": {"key": "value"},
      "list": [
        "value",
        {"key": "value"},
        ["value"]
      ]
    });

    final encoded = archive.toPrimitive();
    expect(encoded["value"], "v");
    expect(encoded["archive"] is Map<String, dynamic>, true);
    expect(encoded["archive"] is KeyedArchive, false);
    expect(encoded["list"] is List<dynamic>, true);
    expect(encoded["list"] is ListArchive, false);

    expect(encoded["list"][0], "value");

    expect(encoded["list"][1] is Map<String, dynamic>, true);

    expect(encoded["list"][1] is KeyedArchive, false);

    expect(encoded["list"][2] is List<dynamic>, true);

    expect(encoded["list"][2] is ListArchive, false);
  });
}

Map<String, dynamic>? encode(void Function(KeyedArchive object) encoder) {
  final archive = KeyedArchive({});
  encoder(archive);
  return json.decode(json.encode(archive)) as Map<String, dynamic>?;
}

class Container extends Coding {
  Container(this.root, this.definitions);

  Container._();

  Parent? root;
  Map<String, Coding?>? definitions;

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    root = object.decodeObject("root", () => Parent._());
    definitions = object.decodeObjectMap("definitions", () => Child._());
  }

  @override
  void encode(KeyedArchive object) {
    object.encodeObject("root", root);
    object.encodeObjectMap("definitions", definitions);
  }
}

class Parent extends Coding {
  Parent(this.name, {this.child, this.children, this.childMap, this.things});

  Parent._();

  String? name;
  Child? child;
  List<Child?>? children;
  Map<String, Child?>? childMap;
  List<String>? things;

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    name = object.decode("name");
    child = object.decodeObject("child", () => Child._());
    children = object.decodeObjects("children", () => Child._());
    childMap = object.decodeObjectMap("childMap", () => Child._());
  }

  @override
  void encode(KeyedArchive object) {
    object.encode("name", name);
    object.encodeObject("child", child);
    object.encodeObjects("children", children);
    object.encodeObjectMap("childMap", childMap);
    object.encode("things", things);
  }
}

class Child extends Coding {
  Child(this.name, {this.parent});

  Child._();

  String? name;
  Parent? parent;

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    name = object.decode("name");
    parent = object.decodeObject("parent", () => Parent._());
  }

  @override
  void encode(KeyedArchive object) {
    object.encode("name", name);
    object.encodeObject("parent", parent);
  }
}
