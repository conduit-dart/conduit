// ignore_for_file: avoid_catching_errors

import 'package:conduit/conduit.dart';
import 'package:test/test.dart';

void main() {
  test("Cannot have unnamed constructor with required args", () {
    try {
      ManagedDataModel([DefaultConstructorHasRequiredArgs]);
      fail('unreachable');
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("DefaultConstructorHasRequiredArgs"));
      expect(e.toString(), contains("default, unnamed constructor"));
    }
  });
}

class DefaultConstructorHasRequiredArgs
    extends ManagedObject<_ConstructorTableDef> {
  // ignore: avoid_unused_constructor_parameters
  DefaultConstructorHasRequiredArgs(int foo);
}

class _ConstructorTableDef {
  @primaryKey
  int? id;
}
