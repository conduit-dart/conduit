// ignore_for_file: avoid_catching_errors, empty_catches, cast_nullable_to_non_nullable

import 'dart:mirrors';

import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_core/src/runtime/orm/entity_mirrors.dart';
import 'package:test/test.dart';

void main() {
  ManagedContext? context;
  tearDown(() async {
    await context?.close();
    context = null;
  });

  test("Have access to type args in Map", () {
    final type = getManagedTypeFromType(typeOf(#mapOfInts));
    expect(type.kind, ManagedPropertyType.map);
    expect(type.elements!.kind, ManagedPropertyType.integer);
  });

  test("Have access to type args in list of maps", () {
    final type = getManagedTypeFromType(typeOf(#listOfIntMaps));
    expect(type.kind, ManagedPropertyType.list);
    expect(type.elements!.kind, ManagedPropertyType.map);
    expect(type.elements!.elements!.kind, ManagedPropertyType.integer);
  });

  test("Cannot create ManagedType from invalid types", () {
    try {
      getManagedTypeFromType(typeOf(#invalidMapKey));
      fail("unreachable");
    } on UnsupportedError {}
    try {
      getManagedTypeFromType(typeOf(#invalidMapValue));
      fail("unreachable");
    } on UnsupportedError {}
    try {
      getManagedTypeFromType(typeOf(#invalidList));
      fail("unreachable");
    } on UnsupportedError {}

    try {
      getManagedTypeFromType(typeOf(#uri));
      fail("unreachable");
    } on UnsupportedError {}
  });
  test("Private channel fails and notifies with appropriate message", () async {
    final crashingApp = Application<_PrivateChannel>();
    try {
      await crashingApp.start();
      expect(true, false);
    } catch (e) {
      expect(
        e.toString(),
        "Bad state: Channel type _PrivateChannel was not loaded in the current isolate. Check that the class was declared and public.",
      );
    }
  });
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @primaryKey
  int? id;

  String? n;
  DateTime? t;
  int? l;
  bool? b;
  double? d;
  Document? doc;
}

class TypeRepo {
  Map<String, int>? mapOfInts;
  List<Map<String, int>>? listOfIntMaps;

  Map<int, String>? invalidMapKey;
  Map<String, Uri>? invalidMapValue;

  List<Uri>? invalidList;

  Uri? uri;
}

TypeMirror typeOf(Symbol symbol) {
  return (reflectClass(TypeRepo).declarations[symbol] as VariableMirror).type;
}

class _PrivateChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = Router();
    return router;
  }
}
